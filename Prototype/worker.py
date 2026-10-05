"""Local Qwen ASR adapter. JSON lines over pipes; no server or network access."""
import argparse
import contextlib
import json
import os
from pathlib import Path
import resource
import sys
import time
import wave

os.environ.update(HF_HUB_OFFLINE="1", HF_HUB_DISABLE_TELEMETRY="1", DO_NOT_TRACK="1")


def send(message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


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


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, required=True)
    parser.add_argument("--recording-dir", type=Path, required=True)
    args = parser.parse_args()
    if not (args.model_dir / "config.json").is_file():
        send({"event": "error", "message": "Model missing. Run scripts/setup.sh first."})
        return 1
    # Keep library diagnostics off the protocol. No transcript or audio log files.
    with open(os.devnull, "w") as quiet:
        try:
            started = time.monotonic()
            with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                import numpy as np
                from mlx_qwen3_asr import Session
                session = Session(str(args.model_dir))
            send({"event": "ready", "load_seconds": round(time.monotonic() - started, 2)})
        except Exception as error:
            send({"event": "error", "message": "Model could not load (" + type(error).__name__ + ")."})
            return 1

        for line in sys.stdin:
            request = {}
            path = None
            try:
                request = json.loads(line)
                path = Path(request["path"])
                samples = read_audio(path, args.recording_dir)
                started = time.monotonic()
                text = ""
                if len(samples) >= 4000 and float(np.sqrt(np.mean(samples ** 2))) > 0.0004:
                    with contextlib.redirect_stdout(quiet), contextlib.redirect_stderr(quiet):
                        result = session.transcribe(
                            (samples, 16000), language="English",
                            context=request.get("context", "")[:2000],
                            max_new_tokens=1536, verbose=False,
                        )
                    text = result.text.strip()
                send({"event": "result", "id": request["id"], "text": text,
                      "seconds": round(time.monotonic() - started, 2),
                      "audio_seconds": round(len(samples) / 16000, 2),
                      "peak_memory_gb": round(resource.getrusage(resource.RUSAGE_SELF).ru_maxrss / 1e9, 2)})
            except Exception as error:
                send({"event": "error", "id": request.get("id"),
                      "message": "Transcription failed (" + type(error).__name__ + "). Try again."})
            finally:
                if path is not None and path.resolve().parent == args.recording_dir.resolve() and path.suffix == ".wav":
                    path.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

