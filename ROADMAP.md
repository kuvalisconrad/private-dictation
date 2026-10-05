# Private Dictation roadmap

Updated **5 October 2026** (Asia/Bangkok). This tracks the Mac app, website and launch together. A checked item means the stated work is implemented; it does not mean the entire product is ready to sell.

## Product commitments

- English-only local dictation for version 1, with a planned US$5 one-time packaged-app price and public MIT source.
- Start/stop from the keyboard and insert at the cursor, without a recording overlay.
- No audio or transcript history, cloud transcription, online activation, or clipboard use in the release build.
- Retain only explicit preferences, dictionary entries and optional aggregate counters. Insights default to off.
- Verify accuracy and usable hardware before advertising performance or model superiority. Text inserted into another app follows that app's own storage and privacy behavior.

## Built so far

### Mac app — implemented in the v1 review build

- [x] Custom charcoal/mint setup and settings windows, icon, download progress, transitions and reduced-motion support.
- [x] Command–Option start/stop, configurable modifier chords and ordinary-key shortcuts, conflict validation, and Escape to discard.
- [x] Local correction dictionary with explicit heard-text → preferred-spelling rules and vocabulary hints.
- [x] Optional aggregate insights: dictation count, word count, audio time and processing time; no per-dictation records.
- [x] Clipboard-free Accessibility insertion with a Unicode typing fallback, secure-field rejection and focus checks.
- [x] Pending results held in memory for retry/discard when insertion cannot safely finish.
- [x] Explicit checksum-verified model setup, bundled Python/MLX runtime, and offline dictation enforced by a network-denying sandbox.
- [x] Temporary recording cleanup, cancellation, two-minute recording limit, timeouts and engine recovery.
- [x] Temporary playback muting during recording, restoring the previous output state after stop/cancel/normal quit, with route/profile monitoring. Implemented in both the personal prototype and v1 source.
- [x] Native unit checks, packaged-engine smoke/cleanup/offline checks, UI rendering checks and a portable review ZIP.

**Installed locally:** at the owner's request, the development Mac was reverted to the original v0.1 prototype on 5 October. It runs at `/Applications/Private Dictation.app`, with the existing Dock icon and stable Apple Development permission identity retained. The prototype source was recovered into `Prototype/` and committed before modification. Personal build 3 adds output muting during recording and selects the built-in Mac microphone before each capture; its original paste method, speech worker and model configuration are preserved. This personal rollback briefly uses the clipboard and restores prior clipboard contents; it does not implement the release build's clipboard-free promise. The polished build 102 is preserved in `build/Rollbacks.noindex`; build 103's focus repair is staged separately. Neither its release installation nor live insertion verification is complete. Source improvements remain intact. Developer ID distribution signing/notarization remains launch work.

### Website and content — implemented and published

- [x] Designed product, setup, privacy, purchase-terms, checkout and journal pages, with links to the public app source.
- [x] Owner-only Markdown editor/import, preview, drafts, scheduled publication and publishing API.
- [x] Article sources and fact-check dates, canonical URLs, structured data, RSS and sitemap; unpublished articles stay private.
- [x] Anonymous page/day totals for the owner dashboard, without visitor identifiers.
- [x] Starter articles and a saved Tuesday/Friday 09:00 Bangkok content schedule.
- [x] Guarded checkout and private release delivery implementation; sales remain disabled.

**Current status:** the generated hosting domain is live. `privatedictation.app` is attached but still awaiting ownership verification. The recurring content schedule exists and is **paused**; it is not currently publishing automatically.

### Research and packaging

- [x] Public source repository renamed to `private-dictation`, with MIT license and third-party notices/licenses.
- [x] Synthetic offline benchmark command with machine/model identifiers, raw timing samples and separate memory measurements.
- [x] M5 / 32 GB engine measurements; performance results explicitly exclude accuracy and native insertion.
- [x] Signing/notarization and private release-upload scripts prepared.
- [x] Initial model/dependency commercial-license and launch-disclosure review. This is not a completed jurisdiction-specific legal clearance.

## Next: finish the app you will actually use

1. [ ] Restore a verified clipboard-free polished build after the temporary prototype rollback. Preserve model/settings, the single canonical Applications copy and its Dock icon.
2. [x] Verify normal desktop launch recognizes Microphone and Accessibility: the owner's live test starts recording and reaches a transcribed result. This does not establish successful insertion; headless permission booleans alone would not establish the desktop grants.
3. [ ] Verify live insertion in a genuinely foreground TextEdit document for both Accessibility and Unicode paths. Earlier tests never reached actual insertion because their TextEdit focus prerequisite failed. This is an incomplete integration test, not evidence that insertion works.
4. [ ] Test normal dictation in Codex/browser fields, TextEdit and other common apps; cover focus changes, unsupported fields, cancellation and partial-result retry/discard.
5. [ ] Exercise custom shortcuts and dictionary corrections through real recording sessions. Confirm recording has no floating panel and insertion never touches the clipboard.
6. [ ] Run a clean first-install/model-download/permission flow on another Mac, including recovery from interrupted setup.

### Current regression investigation

The archived v0.1 prototype and first release were compared against the original conversation and source. Both use the same Qwen3-ASR-1.7B model revision and MLX/ASR versions. The commercial polish replaced temporary clipboard paste/restore with Accessibility and Unicode insertion to honor the explicit no-clipboard requirement. It also added stricter focused-field availability, editability and identity checks. The original prototype had passed the owner's live dictation test; the replacement had only passed engine and safety checks before installation.

The owner's “Text ready · click its destination and use the shortcut” screenshot establishes that recording and transcription succeeded and the pre-insertion focus gate refused the result. The installed build groups held modifiers, missing focus/app information and changed destination into that same message, so the exact failed subcondition is not yet established. No clipboard fallback or privacy restriction rollback is part of the repair. Live insertion verification is required before calling the regression fixed. The installed personal prototype build 3 adds muting and built-in microphone selection to its capture lifecycle; it preserves the recovered original paste method. Fake-output regression checks cover route/profile changes, previous mute state, volume fallback and partial failure restoration. A microphone-free check on the actual output passed mute, rapid-restart and restoration under the offline sandbox. The owner’s live build-2 test found a 3–4-second playback volume surge after recording stopped. At their explicit request, build 3 now sets the Mac’s default input to the built-in microphone before each capture, avoiding use of the AirPods microphone. A sandboxed check confirmed built-in input selection and an unchanged playback route without opening the microphone. The owner confirmed on 5 October that personal prototype build 3 works correctly: playback is muted during dictation and resumes at its normal volume when Command–Option stops recording. This is the verified personal working baseline; clipboard-free v1 insertion remains a separate unverified release task. The app source for that baseline is commit de325d8.

## Then: establish trustworthy launch requirements and accuracy

1. [ ] Benchmark physical M2 / 16 GB and M4 / 16 GB machines using the same packaged engine and model revision. Rentals need an account and a spending authorization; none have been purchased.
2. [ ] Measure repeated startup/processing times, sustained dictation, memory pressure/swap and representative background-app load. Validate laptop thermal behavior separately.
3. [ ] Check macOS 14 on actual supported hardware. A binary minimum-OS audit does not replace an installation test.
4. [ ] Compare natural English speech with reference transcripts, including names, numbers, accents and technical vocabulary; measure errors and corrections needed.
5. [ ] Run an honestly documented comparison with Wispr Flow using the same speech and disclosed settings; publish no unsupported accuracy rankings.
6. [ ] Set supported/recommended hardware and latency expectations from results, with headroom. The current 16 GB app floor and M4/M5 guidance are provisional product choices, not demonstrated physical limits.

## Before accepting payment

1. [ ] Finish custom-domain verification, then update canonical URLs to the active domain.
2. [ ] Configure Apple Developer ID signing/notarization and validate the actual release archive on a clean Mac.
3. [ ] Supply the merchant account, seller identity and support address; finalize applicable tax/refund/disclosure requirements and name-rights review.
4. [ ] Test payment, authenticated download, failed payment and refund with the actual merchant setup; keep sales disabled until the release and hardware gates pass.
5. [ ] Publish the validated requirements, release notes, install guide and known app-compatibility limits.
6. [ ] Review the paused content schedule with the owner before resuming it; verify a real scheduled run, queue filtering and publication read-back. Continue sourced articles at a measured pace.

## After the core experience is dependable

- [ ] Evaluate launch-at-login and microphone selection as small convenience features.
- [ ] Consider idle model unloading or a memory control, measuring the startup-delay tradeoff.
- [ ] Add another local model only after license, English accuracy, speed and memory comparisons justify it. Hardware detection can recommend an option with a manual override; version 1 currently uses the same Qwen3-ASR-1.7B model on every supported Mac.
- [ ] Maintain reproducible benchmarks, compatibility notes, dependency/model updates and regression checks.
- [ ] Assess manually authored notes separately if useful. Do not turn dictations into an automatic notes feed or history.

Transcript history, cloud fallback and automatic clipboard insertion are outside the product's scope.

## Where things live

- App source and this roadmap: [github.com/kuvalisconrad/private-dictation](https://github.com/kuvalisconrad/private-dictation).
- Live website: [private-dictation.vimes177.chatgpt.site](https://private-dictation.vimes177.chatgpt.site).
- Local website checkout is separate from the public app repository. Its README documents the owner publishing and release-delivery workflows.
- Build/ZIP measurements and release metadata are local review artifacts, not a published paid release.
