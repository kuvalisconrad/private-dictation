"""Measure this exact release on the current Mac; this is not an accuracy benchmark."""
import json
from pathlib import Path
import selectors
import subprocess
import tempfile
import time
import wave

root = Path(__file__).resolve().parents[1]
engine = root / 'build/Private Dictation.app/Contents/Resources/Engine/PrivateDictationEngine'
model = Path.home() / 'Library/Application Support/Local Dictation/models/qwen3-asr-1.7b'
profile = '(version 1)(allow default)(deny network*)'
measurements = {'hardware': 'Apple M5, 32 GB unified memory',
                'model': 'Qwen3-ASR-1.7B, unquantized float16 inference',
                'purpose': 'Synthetic speech throughput and memory; not an accuracy benchmark',
                'model_disk_bytes': 4703055333, 'samples': []}

with tempfile.TemporaryDirectory(prefix='private-dictation-measure-') as temporary:
    directory = Path(temporary)
    aiff = directory / 'synthetic.aiff'
    speech = directory / 'synthetic.wav'
    subprocess.run(['/usr/bin/say', '-v', 'Samantha', '-o', str(aiff),
                    'The meeting starts at nine thirty tomorrow morning. Please send the report to Mike.'], check=True)
    subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1',
                    str(aiff), str(speech)], check=True)
    with wave.open(str(speech), 'rb') as wav:
        original = wav.readframes(wav.getnframes())
    process = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', profile, str(engine),
                                '--model-dir', str(model), '--recording-dir', str(directory)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    def receive():
        if not selector.select(timeout=180):
            raise TimeoutError('Measurement timed out')
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read()[:2000])
        response = json.loads(line)
        if response['event'] == 'error':
            raise RuntimeError(response)
        return response

    try:
        ready = receive()
        measurements['load_seconds'] = ready['load_seconds']
        measurements['model_active_memory_gb'] = ready['model_memory_gb']
        rss = int(subprocess.check_output(['/bin/ps', '-o', 'rss=', '-p', str(process.pid)], text=True).strip()) * 1024
        measurements['idle_process_rss_gb'] = round(rss / 1e9, 3)
        print(json.dumps({'ready': ready, 'idle_process_rss_gb': measurements['idle_process_rss_gb']}), flush=True)
        for duration in [len(original) / 32000, 30, 120]:
            frames = int(duration * 16000)
            audio = directory / ('sample-' + str(frames) + '.wav')
            repetitions = (frames * 2 + len(original) - 1) // len(original)
            with wave.open(str(audio), 'wb') as wav:
                wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                wav.writeframes((original * repetitions)[:frames * 2])
            process.stdin.write(json.dumps({'id': str(frames), 'path': str(audio)}) + '\n')
            process.stdin.flush()
            response = receive()
            assert response['event'] == 'result' and not audio.exists()
            sample = {key: response[key] for key in ['audio_seconds', 'seconds', 'peak_memory_gb', 'peak_mlx_memory_gb']}
            sample['audio_seconds_per_processing_second'] = round(response['audio_seconds'] / response['seconds'], 2)
            sample['transcript_word_count'] = len(response['text'].split())
            measurements['samples'].append(sample)
            print(json.dumps(sample), flush=True)
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        assert not process.stderr.read()
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)

destination = root / 'release/engine-measurements-m5.json'
destination.parent.mkdir(exist_ok=True)
destination.write_text(json.dumps(measurements, indent=2) + '\n')
print('Saved technical measurements to', destination, flush=True)
