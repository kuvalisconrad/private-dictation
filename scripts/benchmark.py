#!/usr/bin/env python3
"""Offline synthetic performance of the shipped engine, never dictation accuracy."""
import argparse
import errno
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import plistlib
import re
import selectors
import signal
import socket
import subprocess
import sys
import tempfile
import time
import wave

ROOT = Path(__file__).resolve().parents[1]
PROFILE = '(version 1)(allow default)(deny network*)'
PHRASE = 'Please send the report tomorrow morning. The meeting begins at nine thirty.'


class BenchmarkError(Exception):
    pass


def command(arguments):
    result = subprocess.run(arguments, capture_output=True, text=True, timeout=30)
    if result.returncode:
        raise BenchmarkError('A required local system command failed.')
    return result.stdout.strip()


def optional_command(arguments):
    try:
        return command(arguments)
    except (BenchmarkError, OSError, subprocess.TimeoutExpired):
        return ''


def sha256(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def summarize(values):
    ordered = sorted(values)
    result = {'n': len(values), 'samples': [round(x, 4) for x in values],
              'min': round(ordered[0], 4), 'max': round(ordered[-1], 4)}
    if len(values) >= 5:
        # Nearest rank: with five samples P95 is just the maximum, not a tail estimate.
        for name, percentile in [('p50', 0.50), ('p95', 0.95)]:
            result[name] = round(ordered[math.ceil(percentile * len(ordered)) - 1], 4)
    return result


def verify_offline(engine):
    try:
        with socket.socket() as connection:
            connection.settimeout(2)
            connection.connect(('127.0.0.1', 9))
    except OSError as error:
        if error.errno not in (errno.EPERM, errno.EACCES):
            raise BenchmarkError('Network sandbox verification failed; no benchmark started.') from None
    else:
        raise BenchmarkError('Network is available; no benchmark started.')
    result = subprocess.run([str(engine), '--network-test'], capture_output=True,
                            text=True, timeout=15)
    try:
        denied = json.loads(result.stdout)['network_denied'] is True
    except (ValueError, KeyError, TypeError):
        denied = False
    if result.returncode or not denied:
        raise BenchmarkError('Frozen engine network sandbox verification failed.')


class Engine:
    def __init__(self, executable, model, directory):
        environment = {**os.environ, 'HF_HUB_OFFLINE': '1',
                       'HF_HUB_DISABLE_TELEMETRY': '1', 'DO_NOT_TRACK': '1'}
        self.selector = selectors.DefaultSelector()
        self.started = time.perf_counter()
        self.process = subprocess.Popen(
            [str(executable), '--model-dir', str(model), '--recording-dir', str(directory)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            text=True, env=environment)
        self.selector.register(self.process.stdout, selectors.EVENT_READ)

    def receive(self):
        if not self.selector.select(timeout=180):
            raise BenchmarkError('The frozen engine timed out.')
        line = self.process.stdout.readline()
        try:
            message = json.loads(line)
        except (ValueError, TypeError):
            raise BenchmarkError('The frozen engine returned an invalid protocol response.') from None
        if message.get('event') == 'error':
            raise BenchmarkError('The frozen engine reported a load or transcription error.')
        return message

    def ready(self):
        message = self.receive()
        if message.get('event') != 'ready':
            raise BenchmarkError('The frozen engine did not become ready.')
        elapsed = time.perf_counter() - self.started
        return {'spawn_to_ready_seconds': elapsed,
                'engine_reported_load_seconds': message['load_seconds'],
                'model_active_mlx_gb': message['model_memory_gb']}

    def transcribe(self, audio, identifier):
        started = time.perf_counter()
        self.process.stdin.write(json.dumps({'id': str(identifier), 'path': str(audio)}) + '\n')
        self.process.stdin.flush()
        message = self.receive()
        elapsed = time.perf_counter() - started
        if message.get('event') != 'result' or message.get('id') != str(identifier):
            raise BenchmarkError('The frozen engine returned an unexpected result.')
        if audio.exists():
            raise BenchmarkError('The engine retained a temporary synthetic recording.')
        if not message.pop('text', '').strip():
            raise BenchmarkError('The synthetic speech produced no text.')
        return {'request_to_result_seconds': round(elapsed, 4),
                'engine_reported_seconds': message['seconds'],
                'audio_seconds': message['audio_seconds'],
                'audio_seconds_per_wall_second': round(message['audio_seconds'] / elapsed, 3),
                'lifetime_peak_process_rss_gb': message['peak_memory_gb'],
                'lifetime_peak_mlx_allocator_gb': message['peak_mlx_memory_gb']}

    def close(self, interrupted=False):
        try:
            if self.process.poll() is None:
                if interrupted:
                    self.process.terminate()
                else:
                    self.process.stdin.close()
                try:
                    self.process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=5)
            if not interrupted and self.process.returncode:
                raise BenchmarkError('The frozen engine did not exit cleanly.')
        finally:
            self.selector.close()
            self.process.stdout.close()
            if not self.process.stdin.closed:
                self.process.stdin.close()


def run(args):
    began = time.perf_counter()
    engine = args.app / 'Contents/Resources/Engine/PrivateDictationEngine'
    native = args.app / 'Contents/MacOS/LocalDictation'
    manifest_path = args.app / 'Contents/Resources/model-manifest.json'
    if not engine.is_file() or not native.is_file() or not manifest_path.is_file():
        raise BenchmarkError('Build the portable app or select it with --app first.')
    verify_offline(engine)  # Fail closed before synthesis or inference.
    manifest = json.loads(manifest_path.read_text())
    if any(not (args.model_dir / f['name']).is_file() or
           (args.model_dir / f['name']).stat().st_size != f['size'] for f in manifest['files']):
        raise BenchmarkError('The installed model is missing or incomplete; download it in setup first.')
    version = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
    power = optional_command(['/usr/bin/pmset', '-g', 'batt'])
    mode = re.search(r'lowpowermode\s+([01])', optional_command(['/usr/bin/pmset', '-g']))
    commit = optional_command(['/usr/bin/git', '-C', str(ROOT), 'rev-parse', 'HEAD'])
    source_dirty = bool(optional_command(['/usr/bin/git', '-C', str(ROOT), 'status', '--porcelain'])) if commit else None
    report = {
        'schema_version': 1, 'purpose': 'Synthetic performance, not dictation accuracy',
        'started_utc': datetime.now(timezone.utc).isoformat(timespec='seconds'),
        'hardware': {'chip': command(['/usr/sbin/sysctl', '-n', 'machdep.cpu.brand_string']),
                     'ram_bytes': int(command(['/usr/sbin/sysctl', '-n', 'hw.memsize'])),
                     'macos': command(['/usr/bin/sw_vers', '-productVersion']),
                     'environment': args.environment,
                     'environment_evidence': 'unknown' if args.environment == 'unknown' else
                         'operator supplied; not independently verified by this tool',
                     'power_source': 'AC' if 'AC Power' in power else
                         'battery' if 'Battery Power' in power else 'unknown',
                     'low_power_mode': bool(int(mode[1])) if mode else None},
        'app': {'version': version, 'app_commit': args.app_commit or 'unknown',
                'app_commit_evidence': 'operator supplied' if args.app_commit else 'not embedded in app',
                'native_sha256': sha256(native), 'engine_sha256': sha256(engine)},
        'benchmark': {'source_commit': commit or 'unknown', 'source_dirty': source_dirty,
                      'script_sha256': sha256(Path(__file__)), 'quick': args.quick},
        'model': {'repository': manifest['repository'], 'revision': manifest['revision'],
                  'disk_bytes': sum(f['size'] for f in manifest['files']),
                  'manifest_sha256': sha256(manifest_path),
                  'integrity_check': 'Installed file sizes checked; weights not rehashed for this run'},
        'methodology': {
            'offline': 'Network denied for the benchmark and all descendants; verified before audio generation',
            'audio': 'Installed macOS voice; fixed public phrase repeated/cropped to mono 16 kHz PCM16',
            'voice': args.voice, 'durations_seconds': [4, 30, 120],
            'fresh_process': 'New engine process and model session each time; spawn-to-ready wall time',
            'first_request': '4-second request immediately after each fresh session becomes ready',
            'warm_session': 'Last process reused after its first request; model remains resident',
            'cache_state': 'OS file caches and Metal shader caches uncontrolled; never a cold-cache measurement',
            'latency': 'Wall time from pipe request to result; excludes recording, native insertion and app UI',
            'percentiles': 'Nearest rank, only for N >= 5; N=5 P95 is the maximum, not a reliable tail estimate',
            'memory': 'Kernel getrusage lifetime peak process RSS and MLX allocator peak are separate overlapping views; never sum them',
            'conditions': 'Thermal state and other applications uncontrolled; no artificial RAM limit',
        },
        'fresh_process_load': [], 'first_request': [], 'warm_session': {},
    }
    startups = args.startup_repeats or (2 if args.quick else 5)
    all_samples = []
    with tempfile.TemporaryDirectory(prefix='private-dictation-benchmark-') as temporary:
        directory = Path(temporary)
        aiff, master = directory / 'synthetic.aiff', directory / 'synthetic.wav'
        command(['/usr/bin/say', '-v', args.voice, '-r', '180', '-o', str(aiff), PHRASE])
        command(['/usr/bin/afconvert', '-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', str(aiff), str(master)])
        with wave.open(str(master), 'rb') as wav:
            pcm = wav.readframes(wav.getnframes())
        if not pcm:
            raise BenchmarkError('The installed voice produced no synthetic audio.')
        counter = 0

        def clip(seconds):
            nonlocal counter
            counter += 1
            path = directory / (str(counter) + '.wav')
            length = seconds * 32000
            with wave.open(str(path), 'wb') as wav:
                wav.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
                wav.writeframes((pcm * math.ceil(length / len(pcm)))[:length])
            return path

        for index in range(startups):
            current = Engine(engine, args.model_dir, directory)
            completed = False
            try:
                report['fresh_process_load'].append(current.ready())
                sample = current.transcribe(clip(4), counter)
                report['first_request'].append(sample)
                all_samples.append(sample)
                if index == startups - 1:
                    for duration in (4, 30, 120):
                        repetitions = args.repeats or (2 if args.quick and duration == 4 else
                                                      1 if args.quick else 5)
                        samples = [current.transcribe(clip(duration), counter) for _ in range(repetitions)]
                        all_samples.extend(samples)
                        report['warm_session'][str(duration)] = {
                            'samples': samples,
                            'wall_seconds': summarize([s['request_to_result_seconds'] for s in samples])}
                completed = True
            finally:
                current.close(interrupted=not completed)
    report['fresh_process_load_wall_seconds'] = summarize(
        [sample['spawn_to_ready_seconds'] for sample in report['fresh_process_load']])
    report['first_request_wall_seconds'] = summarize(
        [sample['request_to_result_seconds'] for sample in report['first_request']])
    report['memory'] = {
        'model_active_mlx_gb': max(s['model_active_mlx_gb'] for s in report['fresh_process_load']),
        'peak_process_rss_gb': max(s['lifetime_peak_process_rss_gb'] for s in all_samples),
        'peak_mlx_allocator_gb': max(s['lifetime_peak_mlx_allocator_gb'] for s in all_samples)}
    report['temporary_synthetic_audio_deleted'] = True
    report['elapsed_seconds'] = round(time.perf_counter() - began, 3)
    encoded = json.dumps(report, indent=2) + '\n'
    if args.output:
        args.output.write_text(encoded)
    else:
        sys.stdout.write(encoded)


def positive(value):
    number = int(value)
    if not 1 <= number <= 50:
        raise argparse.ArgumentTypeError('Choose a count from 1 to 50.')
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=ROOT / 'build/Private Dictation.app')
    parser.add_argument('--model-dir', type=Path, default=Path.home() /
                        'Library/Application Support/Local Dictation/models/qwen3-asr-1.7b')
    parser.add_argument('--quick', action='store_true', help='Two fresh starts and 2/1/1 warm clips; usually under a minute on M5')
    parser.add_argument('--repeats', type=positive, help='Warm samples per duration (default 5; quick 2/1/1)')
    parser.add_argument('--startup-repeats', type=positive, help='Fresh process samples (default 5; quick 2)')
    parser.add_argument('--voice', default='Samantha', help='An already installed English macOS voice; no voice downloads')
    parser.add_argument('--app-commit', help='Actual source commit used to build this app; not inferred from benchmark checkout')
    parser.add_argument('--environment', choices=['unknown', 'bare-metal', 'virtual-machine'], default='unknown',
                        help='Operator supplied environment label; the tool does not verify it')
    parser.add_argument('--output', type=Path, help='Write JSON instead of stdout; its parent directory must exist')
    parser.add_argument('--offline-child', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.app_commit and not re.fullmatch('[0-9a-fA-F]{40}', args.app_commit):
        parser.error('--app-commit must be a full 40-character Git SHA')

    def interrupted(_signal, _frame):
        raise KeyboardInterrupt

    signal.signal(signal.SIGTERM, interrupted)
    try:
        if sys.platform != 'darwin':
            raise BenchmarkError('This benchmark requires Apple Silicon macOS.')
        if not args.offline_child:
            child = subprocess.Popen(['/usr/bin/sandbox-exec', '-p', PROFILE, sys.executable, '-B',
                                      str(Path(__file__).resolve()), '--offline-child', *sys.argv[1:]])
            try:
                return child.wait()
            except KeyboardInterrupt:
                child.terminate()
                try:
                    child.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=5)
                return 130
        run(args)
        return 0
    except KeyboardInterrupt:
        print('Benchmark cancelled; temporary synthetic audio removed.', file=sys.stderr)
        return 130
    except Exception as error:
        print(str(error) if isinstance(error, BenchmarkError) else
              'Benchmark failed (' + type(error).__name__ + '); no audio or transcript report saved.', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
