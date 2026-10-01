"""Private ASR pipes and an explicit first-run, checksum-verified downloader."""
import argparse
import errno
import gc
import hashlib
import json
import os
from pathlib import Path
import resource
import shutil
import signal
import socket
import ssl
import sys
import time
import urllib.request
import wave

# Native libraries cannot contaminate the JSON protocol or log user dictation.
PROTOCOL = os.fdopen(os.dup(sys.stdout.fileno()), "w", encoding="utf-8", buffering=1)
_quiet = open(os.devnull, "w")
os.dup2(_quiet.fileno(), 1)
os.dup2(_quiet.fileno(), 2)
os.environ.update(HF_HUB_DISABLE_TELEMETRY="1", DO_NOT_TRACK="1",
                  PYTHONDONTWRITEBYTECODE="1", TOKENIZERS_PARALLELISM="false")


def send(message):
    PROTOCOL.write(json.dumps(message, ensure_ascii=False) + "\n")
    PROTOCOL.flush()


def manifest():
    resources = Path(getattr(sys, "_MEIPASS", Path(__file__).resolve().parent))
    if not (resources / "model-manifest.json").is_file():
        resources = resources.parent  # Contributor Sources/worker.py layout.
    return json.loads((resources / "model-manifest.json").read_text())


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as file:
        while chunk := file.read(8 * 1024 * 1024):
            checksum.update(chunk)
    return checksum.hexdigest()


def network_test():
    try:
        with socket.socket() as connection:
            connection.settimeout(2)
            connection.connect(("1.1.1.1", 443))
    except OSError as error:
        denied = error.errno in (errno.EPERM, errno.EACCES)
        send({"event": "network_test", "network_denied": denied})
        return 0 if denied else 1
    send({"event": "network_test", "network_denied": False})
    return 1


def download_model(directory):
    """Resume pinned HTTPS files and verify SHA-256 before making them usable."""
    import truststore
    os.environ.pop("HF_HUB_OFFLINE", None)
    context = truststore.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    spec = manifest()
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(directory, 0o700)
    total = sum(file["size"] for file in spec["files"])
    finished = 0
    last_progress = 0.0

    def progress(current, force=False):
        nonlocal last_progress
        now = time.monotonic()
        if force or now - last_progress >= 0.25:
            send({"event": "download_progress", "progress": min(current / total, 1.0),
                  "downloaded_bytes": current, "total_bytes": total})
            last_progress = now

    progress(0, True)
    for file in spec["files"]:
        destination = directory / file["name"]
        if destination.is_file() and destination.stat().st_size == file["size"]:
            if digest(destination) == file["sha256"]:
                finished += file["size"]
                progress(finished, True)
                continue
        partial = directory / (file["name"] + ".partial")
        if partial.exists() and partial.stat().st_size > file["size"]:
            partial.unlink()
        offset = partial.stat().st_size if partial.exists() else 0
        if shutil.disk_usage(directory).free < file["size"] - offset + 300_000_000:
            raise RuntimeError("Not enough free disk space. Free at least 6 GB, then retry.")
        if offset < file["size"]:
            url = ("https://huggingface.co/" + spec["repository"] + "/resolve/"
                   + spec["revision"] + "/" + file["name"])
            headers = {"User-Agent": "PrivateDictation/1.0 (model setup)"}
            if offset:
                headers["Range"] = "bytes=" + str(offset) + "-"
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, context=context, timeout=60) as response:
                if not response.geturl().startswith("https://"):
                    raise RuntimeError("The model server returned an insecure redirect.")
                if offset and response.status == 200:
                    offset = 0
                elif offset and not response.headers.get("Content-Range", "").startswith(
                        "bytes " + str(offset) + "-"):
                    raise RuntimeError("The model server returned an invalid resume range.")
                with partial.open("ab" if offset else "wb") as output:
                    os.chmod(partial, 0o600)
                    progress(finished + offset, True)
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
                        offset += len(chunk)
                        if offset > file["size"]:
                            raise RuntimeError("The downloaded model file exceeded its expected size.")
                        progress(finished + offset)
        if partial.stat().st_size != file["size"]:
            raise RuntimeError("The download was interrupted. Retry to resume it.")
        if digest(partial) != file["sha256"]:
            partial.unlink()
            raise RuntimeError("Model verification failed. Retry to download a fresh copy.")
        partial.replace(destination)
        finished += file["size"]
        progress(finished, True)
    send({"event": "download_complete", "total_bytes": total})
    return 0


def read_audio(path, directory):
    import numpy as np
    resolved = Path(path).resolve()
    if resolved.parent != directory.resolve() or resolved.suffix != ".wav":
        raise ValueError("Audio must be in the app's temporary recording directory")
    if resolved.stat().st_size > 8_000_000:
        raise ValueError("Recording too large")
    with wave.open(str(resolved), "rb") as audio:
        if (audio.getnchannels(), audio.getsampwidth(), audio.getframerate()) != (1, 2, 16000):
            raise ValueError("Expected mono 16 kHz PCM16 WAV")
        samples = np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2").astype(np.float32) / 32768
    return samples


def remove_audio(path, directory):
    if path is not None and path.resolve().parent == directory.resolve() and path.suffix == ".wav":
        path.unlink(missing_ok=True)


def transcribe(args):
    os.environ["HF_HUB_OFFLINE"] = "1"
    spec = manifest()
    if any(not (args.model_dir / file["name"]).is_file()
           or (args.model_dir / file["name"]).stat().st_size != file["size"]
           for file in spec["files"]):
        send({"event": "error", "message": "Model missing or incomplete. Open setup to download it."})
        return 1
    try:
        started = time.monotonic()
        if args.diagnostics:
            os.dup2(PROTOCOL.fileno(), 2)
        import numpy as np
        import mlx.core as mx
        from mlx_qwen3_asr import Session
        session = Session(str(args.model_dir))
        send({"event": "ready", "load_seconds": round(time.monotonic() - started, 2),
              "model_memory_gb": round(mx.get_active_memory() / 1e9, 3)})
    except Exception as error:
        send({"event": "error", "message": "Model could not load (" + type(error).__name__ + ").",
              **({"diagnostic": str(error), "cause": repr(error.__cause__),
                  "context": repr(error.__context__)} if args.diagnostics else {})})
        return 1

    def interrupted(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    for line in sys.stdin:
        request = {}
        path = None
        samples = result = None
        try:
            request = json.loads(line)
            path = Path(request["path"])
            samples = read_audio(path, args.recording_dir)
            started = time.monotonic()
            text = ""
            if len(samples) >= 4000 and float(np.sqrt(np.mean(samples ** 2))) > 0.0004:
                result = session.transcribe(
                    (samples, 16000), language="English",
                    context=str(request.get("context", ""))[:2000],
                    max_new_tokens=1536, verbose=False,
                )
                text = result.text.strip()
            path.unlink(missing_ok=True)
            send({"event": "result", "id": request["id"], "text": text,
                  "seconds": round(time.monotonic() - started, 2),
                  "audio_seconds": round(len(samples) / 16000, 2),
                  "peak_mlx_memory_gb": round(mx.get_peak_memory() / 1e9, 2),
                  "peak_memory_gb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9, 2)})
        except KeyboardInterrupt:
            break
        except Exception as error:
            remove_audio(path, args.recording_dir)
            send({"event": "error", "id": request.get("id"),
                  "message": "Transcription failed (" + type(error).__name__ + "). Try again."})
        finally:
            remove_audio(path, args.recording_dir)
            samples = result = None
            request = {}
            text = ""
            gc.collect()
            mx.clear_cache()
    return 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path)
    parser.add_argument("--recording-dir", type=Path)
    parser.add_argument("--download-model", action="store_true")
    parser.add_argument("--network-test", action="store_true")
    parser.add_argument("--diagnostics", action="store_true",
                        help="Include technical model-load errors; never logs audio or transcripts")
    args = parser.parse_args()
    if args.network_test:
        return network_test()
    if not args.model_dir:
        send({"event": "error", "message": "A local model directory is required."})
        return 1
    if args.download_model:
        try:
            return download_model(args.model_dir)
        except KeyboardInterrupt:
            return 0
        except Exception as error:
            message = str(error) if isinstance(error, RuntimeError) else (
                "Model download failed (" + type(error).__name__ + "). Check your connection and retry.")
            send({"event": "error", "message": message})
            return 1
    if not args.recording_dir:
        send({"event": "error", "message": "A temporary recording directory is required."})
        return 1
    return transcribe(args)


if __name__ == "__main__":
    raise SystemExit(main())
