# Private Dictation roadmap

Updated **2 October 2026** (Asia/Bangkok). This tracks the Mac app, website and launch together. A checked item means the stated work is implemented; it does not mean the entire product is ready to sell.

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
- [x] Native unit checks, packaged-engine smoke/cleanup/offline checks, UI rendering checks and a portable review ZIP.

**Not promoted yet:** the development Mac still runs the v0.1 prototype, which uses the clipboard temporarily. The polished v1 build exists in `build/Private Dictation.app`; final installation and live insertion checks are pending. It is ad hoc signed, not notarized.

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

1. [ ] Install the polished build safely, preserving the existing model/settings and checking Microphone/Accessibility permissions after upgrade.
2. [ ] Verify live insertion in a genuinely foreground TextEdit document for both Accessibility and Unicode paths. Earlier automation could not make TextEdit foreground; the safety guard correctly refused insertion.
3. [ ] Test normal dictation in Codex/browser fields, TextEdit and other common apps; cover focus changes, unsupported fields, cancellation and partial-result retry/discard.
4. [ ] Exercise custom shortcuts and dictionary corrections through real recording sessions. Confirm recording has no floating panel and insertion never touches the clipboard.
5. [ ] Run a clean first-install/model-download/permission flow on another Mac, including recovery from interrupted setup.

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
