"""Real offline inference, deletion, and portability checks for the frozen engine."""
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import tempfile
import wave

root = Path(__file__).resolve().parents[1]
app = Path(os.environ.get('PRIVATE_DICTATION_APP', str(root / 'build/Private Dictation.app')))
engine = app / 'Contents/Resources/Engine/PrivateDictationEngine'
data = Path.home() / 'Library/Application Support/Local Dictation'
model = data / 'models/qwen3-asr-1.7b'
profile = ('(version 1)(allow default)(deny network*)'
           '(deny file-read* (subpath "/Library/Frameworks/Python.framework")'
           '(subpath "/private/tmp/free-dictation-build-runtime")'
           '(subpath "/private/tmp/free-dictation-build-current")'
           '(subpath "/private/tmp/free-dictation-python-current")'
           '(subpath "' + str(root / '.build-env') + '")'
           '(subpath "' + str(root / 'build/python-standalone') + '")'
           '(subpath "' + str(data / 'runtime') + '"))')
environment = {**os.environ, 'PATH': '/nonexistent', 'PYTHONPATH': '/nonexistent',
               'PYTHONHOME': '/nonexistent', 'HF_HUB_OFFLINE': '1'}
network = subprocess.run(['/usr/bin/sandbox-exec', '-p', profile, str(engine), '--network-test'],
                         env=environment, capture_output=True, text=True, timeout=10)
assert network.returncode == 0, (network.stdout, network.stderr)
assert json.loads(network.stdout)['network_denied'] is True
print('Bundled engine network denied; installed Python runtimes inaccessible.', flush=True)

with tempfile.TemporaryDirectory(prefix='private-dictation-bundled-test-') as temporary:
    directory = Path(temporary)
    aiff = directory / 'synthetic.aiff'
    speech = directory / 'synthetic.wav'
    subprocess.run(['/usr/bin/say', '-v', 'Samantha', '-o', str(aiff),
                    'The meeting starts at nine thirty tomorrow morning. Please send the report to Mike.'], check=True)
    subprocess.run(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1',
                    str(aiff), str(speech)], check=True)
    process = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', profile, str(engine),
                                '--model-dir', str(model), '--recording-dir', str(directory)],
                               stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, text=True, env=environment)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)

    def receive():
        if not selector.select(timeout=120):
            raise TimeoutError('Bundled engine did not respond')
        line = process.stdout.readline()
        if not line:
            raise RuntimeError(process.stderr.read()[:2000])
        message = json.loads(line)
        print(json.dumps(message), flush=True)
        return message

    try:
        assert receive()['event'] == 'ready'
        for index in range(3):
            audio = directory / ('sample-' + str(index) + '.wav')
            if index == 1:
                with wave.open(str(audio), 'wb') as wav:
                    wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                    wav.writeframes(b'\0\0' * 32000)
            else:
                shutil.copyfile(speech, audio)
            process.stdin.write(json.dumps({'id': str(index), 'path': str(audio),
                                           'context': 'Mike, Private Dictation'}) + '\n')
            process.stdin.flush()
            message = receive()
            assert message['event'] == 'result' and message['id'] == str(index)
            assert not audio.exists(), 'Audio retained after completion'
            if index == 1:
                assert message['text'] == '', 'Silence hallucinated a transcript'
            else:
                assert 'meeting' in message['text'].lower() and 'report' in message['text'].lower()
        malformed = directory / 'malformed.wav'
        malformed.write_bytes(b'not an audio file')
        process.stdin.write(json.dumps({'id': 'invalid', 'path': str(malformed)}) + '\n')
        process.stdin.flush()
        assert receive()['event'] == 'error'
        assert not malformed.exists(), 'Invalid audio retained after failure'
        process.stdin.close()
        assert process.wait(timeout=10) == 0
        assert process.stderr.read() == '', 'Engine emitted non-protocol logs'
        print('Real speech, repeated inference, silence, error cleanup, offline, and portability passed.')
    finally:
        selector.close()
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
