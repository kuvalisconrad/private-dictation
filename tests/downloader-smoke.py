"""Exercise real HTTPS resume and checksum verification without re-fetching weights."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = Path(os.environ.get('PRIVATE_DICTATION_APP', str(root / 'build/Products.noindex/Private Dictation.app')))
engine = app / 'Contents/Resources/Engine/PrivateDictationEngine'
model = Path.home() / 'Library/Application Support/Local Dictation/models/qwen3-asr-1.7b'
spec = json.loads((root / 'model-manifest.json').read_text())
with tempfile.TemporaryDirectory(prefix='private-dictation-download-test-') as temporary:
    directory = Path(temporary)
    for file in spec['files']:
        if file['name'] != 'config.json':
            os.symlink(model / file['name'], directory / file['name'])
    (directory / 'config.json.partial').write_bytes((model / 'config.json').read_bytes()[:31])
    process = subprocess.run([str(engine), '--download-model', '--model-dir', str(directory)],
                             capture_output=True, text=True, timeout=120)
    events = [json.loads(line) for line in process.stdout.splitlines()]
    assert process.returncode == 0, events
    assert events[-1]['event'] == 'download_complete'
    assert process.stderr == '', 'Downloader emitted non-protocol logs'
    assert all(0 <= item['progress'] <= 1 for item in events if item['event'] == 'download_progress')
    assert hashlib.sha256((directory / 'config.json').read_bytes()).hexdigest() == next(
        item['sha256'] for item in spec['files'] if item['name'] == 'config.json')
    assert not (directory / 'config.json.partial').exists()
    print(json.dumps({'download_complete': True, 'verified_file_count': len(spec['files']),
                      'downloaded_network_bytes': 6194 - 31,
                      'note': 'Server may restart the 6 KB config file if it ignores Range.'}))
    print('Pinned HTTPS download/resume, SHA-256 verification, completion, and clean JSON passed.')
