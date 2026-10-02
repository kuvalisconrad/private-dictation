# Private Dictation

A native Mac app for English dictation. Qwen3-ASR 1.7B recognizes speech locally through MLX, then inserts the result at your cursor. No account, cloud transcription, transcript history, or subscription is required. There is no floating recording panel.

The source is open under MIT at [kuvalisconrad/private-dictation](https://github.com/kuvalisconrad/private-dictation). The packaged app is planned as a **US$5 one-time purchase**; checkout is not live yet. You can build the source yourself. Third-party model and runtime licenses remain their own; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

See [ROADMAP.md](ROADMAP.md) for implemented features, pending validation and launch work. The polished v1 is a review build; final installation and live insertion verification are still pending.

## Requirements and current release status

| Requirement | Minimum / recommendation |
| --- | --- |
| Processor | Apple Silicon; **M4/M5 provisional launch guidance** |
| macOS | **14 Sonoma or later** |
| Unified memory | **16 GB app-enforced floor; 24 GB provisionally recommended** |
| Free disk space | **6 GB for model setup; 8 GB recommended** |
| Language | English only in version 1 |
| Permissions | Microphone and Accessibility |

The packaged transcription engine has been measured on an **M5 MacBook with 32 GB RAM and macOS 26.7**. M4 and actual 16 GB machines still need validation, as does final live insertion in the polished v1 build. Earlier Apple Silicon compatibility follows the upstream engine and compatible binary builds; their speed has not been tested by this project. The app checks Apple Silicon and memory, but does not impose an M4-only gate. These figures are provisional guidance, not a benchmark-established minimum or a claim that older chips cannot run the model. Sales remain disabled pending validation and release setup.

The download archive is approximately **66 MB**; the installed app is approximately **200 MiB**. Its first-run model download is **4,703,055,333 bytes** (about 4.7 GB). Minimum free space includes about 28% headroom over the model download; recommended space allows more room for the app and archive. The measured engine uses about **4.1 GB** for persistent model allocations and reached **8.2 GB** peak MLX allocations including loading. The RAM recommendation also leaves room for macOS and other apps.

This is a **public preview**. Review builds are ad hoc signed, not Developer ID signed or notarized. macOS may require **System Settings → Privacy & Security → Open Anyway** after a first launch attempt. Do not disable Gatekeeper globally. Apple signing and notarization remain release work before a smooth commercial launch.

## Install and dictate

Downloaded releases include their own Python runtime, MLX, and Metal resources. **Users need no Python, Xcode, Homebrew, Terminal setup, or API key.**

1. Unzip the app and move **Private Dictation.app** into Applications.
2. Open it. Complete the explicit model download and permission setup.
3. Allow **Microphone** for speech recording and **Accessibility** to detect the shortcut and insert text into the focused app.
4. Click a text field. Tap **Command–Option** to start, speak, then tap it again to stop and insert the result.

The default shortcut fires when the modifiers are released. Either modifier order works. Adding another ordinary key cancels the modifier-only shortcut, so normal shortcuts remain usable. The microphone in the menu bar and the macOS microphone indicator show recording. Recordings stop automatically after two minutes. **Escape** discards a recording or pending result.

Change the shortcut in **Settings → Shortcut**. Supported choices are a chord of at least two modifiers, or modifiers plus an ordinary key. Reserved editing shortcuts and unavailable key chords are rejected.

If you change the destination while transcription or insertion is in progress, the remaining result stays in memory for retry or discard. Use the shortcut after focusing the intended nonsecure text field. Direct insertion uses Accessibility with a Unicode typing fallback; some apps may not expose a compatible editable field. Secure fields and Secure Keyboard Entry are deliberately excluded. Pause another dictation app if it competes for the same shortcut.

## Dictionary and optional insights

**Dictionary** stores entries you explicitly create: a heard word or phrase and the spelling you want. Entries also provide local vocabulary hints to the model. Replacements are case-insensitive, respect word boundaries, prefer longer matches, and do not cascade into another rule. This corrects names and recurring mistakes without a cloud rewriting service.

**Insights are off by default.** If enabled, only total completed dictations, words, audio seconds, and processing seconds are stored locally. No transcript, audio, destination app, or per-dictation history is recorded. Disabling insights or choosing reset deletes those totals. Shortcut and dictionary settings are local preferences.

## Privacy boundaries

During dictation, the app and its speech engine run under a macOS profile that **denies network access**. The app refuses to start dictation if it cannot install this restriction. Hugging Face offline mode is also enabled. The engine receives an existing local model directory and communicates over pipes, not an HTTP server.

The first-run downloader is a separate, explicitly started setup process. It downloads only the pinned public model and verifies every file against SHA-256 checksums. No recording or transcription is allowed during download. Once the model is installed, dictation works offline. There are no background model downloads, cloud fallbacks, telemetry uploads, or training steps.

Audio is temporarily written to a private local WAV file, then deleted after transcription, cancellation, or normal quit. Crash leftovers are removed on the next launch. No transcript/audio log files or dictation history are implemented. Pending text and model inference buffers exist in memory. **Insertion does not access the system clipboard.** Explicit dictionary entries, shortcut settings, and optional aggregate insights are the local data retained by the app.

Ordinary deletion is not forensic erasure: operating-system memory, swap, backups, or crash metadata are outside the app's control. The model stays in `~/Library/Application Support/Local Dictation/models/qwen3-asr-1.7b`; that legacy folder and the existing bundle identifier are retained so upgrades preserve setup and permissions.

The receiving app controls what happens to inserted text. Dictating into a cloud chat, email service, or synced document does not make that destination private.

## Build from source

Contributors need Apple Silicon, macOS 14+, and Xcode command-line tools. Setup downloads a checksum-verified standalone CPython 3.12.14 runtime into the build directory, then installs pinned dependencies into `.build-env`. It does not change system Python or the user's installed dictation app.

```sh
git clone https://github.com/kuvalisconrad/private-dictation.git
cd private-dictation
bash scripts/setup.sh
bash scripts/build.sh
open "build/Private Dictation.app"
```

`build.sh` **only builds by default**. `bash scripts/build.sh --install` explicitly installs into `~/Applications/Private Dictation.app`; quit an installed build before replacing it. Re-enabling Accessibility may be necessary after an ad hoc rebuild.

```sh
bash scripts/package-release.sh
```

This produces the ZIP and `SHA256SUMS.txt` in `release/`. Developer ID signing is optional through `DEVELOPER_ID_IDENTITY`. Explicit notarization uses `NOTARY_PROFILE` and `scripts/package-release.sh --notarize`. Credentials are never embedded in the app.

## Verification and measured performance

The compiled privacy test must report permission-denied network attempts from both the app and engine:

```sh
"build/Private Dictation.app/Contents/MacOS/LocalDictation" --self-test
.build-env/bin/python tests/bundled-smoke.py
.build-env/bin/python tests/downloader-smoke.py
.build-env/bin/python tests/measure-engine.py
```

The bundled smoke test uses synthetic speech and silence, checks temporary-file deletion on success and failure, and runs under a profile denying both network access and access to installed Python runtimes. The downloader test exercises actual pinned HTTPS resume and checksum verification without downloading another copy of the large weights. Benchmark reports contain machine/model identifiers and timings/memory, with no transcripts or audio; the methodology below explains their limits.

On the tested M5/32 GB machine, the bundled engine processed a synthetic 30-second recording in **4.6 seconds** and a 120-second recording in **19.3 seconds** after loading. First-use shader compilation and other apps can change timings. These are functionality and resource measurements, **not a real-world accuracy benchmark or a head-to-head comparison with Wispr Flow**. Test natural speech, names, numbers, and technical terms that matter to you.

### Synthetic hardware benchmark

`scripts/benchmark.py` measures the actual frozen engine using only generated speech from an already installed English macOS voice. It never records a microphone, reads private audio, or downloads anything. The benchmark and its children inherit a network-denying sandbox, verified before synthesis. Temporary synthetic audio is removed on completion, failure, or normal cancellation. Abrupt power loss or an uncatchable process kill can prevent cleanup.

After building the app and installing the model through its setup:

```sh
mkdir -p release
.build-env/bin/python scripts/benchmark.py --quick --output release/benchmark-quick.json
.build-env/bin/python scripts/benchmark.py --output release/benchmark-full.json
```

The quick run uses two fresh engine processes and warm 4/30/120-second clips with 2/1/1 samples; it is intended to finish within a minute on the tested M5. It is a verification run, not evidence for tail latency. The default full run uses five fresh processes plus five warm samples at each duration and takes several minutes. `--startup-repeats` and `--repeats` adjust those counts. Use `--app "/Applications/Private Dictation.app"` to test an installed release instead of the local build. `--voice` selects another voice that is already installed.

**Fresh-process startup** means wall time from engine spawn until its model-ready response. The first 4-second request in each fresh process is reported separately. **Warm session** means subsequent requests in the last process after that first request has primed it. File caches and Metal shader caches are uncontrolled: these are never claimed to be cold-cache measurements, and later process starts may benefit from caches. Wall request latency excludes speaking time, the native UI, and text insertion. Repeating a short synthetic phrase can be easier than varied natural speech and measures performance, not recognition accuracy.

Reports include raw timings and sample counts. P50/P95 use the nearest-rank method only when **N ≥ 5**; at N=5 P95 is simply the maximum, so meaningful tail claims need substantially more samples. Kernel-reported lifetime peak process RSS and MLX allocator peak are separate, overlapping measurements and must not be added together. The MLX peak includes model loading and is not a per-request memory peak. Thermal state and background applications are uncontrolled; record them separately and repeat under comparable conditions. Power source and Low Power Mode are included when macOS exposes them.

The JSON records chip, physical/guest-visible RAM, macOS, model revision, app/engine hashes, and benchmark source status. It contains no serial number, hostname, private file paths, raw transcripts, or audio. App source commits cannot be inferred reliably from unsigned binaries: pass `--app-commit` with the actual full 40-character build commit if known; otherwise the report says `unknown`. The benchmark's checkout commit is recorded separately. `--environment bare-metal` or `--environment virtual-machine` is an operator-supplied label, not automatic verification; the default is `unknown`. Get written provider confirmation before treating a rented machine as physical hardware with its advertised RAM.

**True minimum requirements need actual machines at the proposed minimum.** A 64 GB Mac with a memory limit does not simulate a 16 GB Mac's unified-memory contention, swap, GPU behavior, or user experience. Test real 16 GB hardware, representative background applications, repeated long dictations, and native shortcut/insertion behavior, with headroom. This synthetic tool alone cannot establish supported hardware or parity with Wispr Flow.

## Model maintenance

Current model: [Qwen/Qwen3-ASR-1.7B](https://huggingface.co/Qwen/Qwen3-ASR-1.7B), pinned to revision `7278e1e70fe206f11671096ffdd38061171dd6e5`, with unquantized 16-bit inference. The adapter is [mlx-qwen3-asr](https://github.com/moona3k/mlx-qwen3-asr).

`Sources/worker.py` is the model adapter; `model.json`, `model-manifest.json`, and `requirements.txt` pin the model, file integrity, and runtime. Adding a replacement model requires reviewing its license, updating the adapter and verified manifest, rebuilding, and testing. This version has no automatic model switching or update service. Model improvements can be added without replacing the recording, shortcut, or insertion UI.
