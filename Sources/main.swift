import AppKit
import AVFoundation
import ApplicationServices
import Darwin

private let files = FileManager.default
private let dataRoot = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Local Dictation")
private let python = dataRoot.appendingPathComponent("runtime/bin/python")
private let resources = Bundle.main.resourceURL!
private let config = (try? Data(contentsOf: resources.appendingPathComponent("model.json")))
    .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
private let modelFolder: String = {
    guard let folder = config?["folder"] as? String,
          !folder.isEmpty, folder != ".", folder != "..", !folder.contains("/") else { return "qwen3-asr-1.7b" }
    return folder
}()
private let modelDirectory = dataRoot.appendingPathComponent("models/" + modelFolder)
private let bundledEngine = resources.appendingPathComponent("Engine/PrivateDictationEngine")
private var networkBlocked = false
private let minimumMemory: UInt64 = 16 * 1_024 * 1_024 * 1_024
private var hardwareSupported: Bool {
    #if arch(arm64)
    return ProcessInfo.processInfo.physicalMemory >= minimumMemory
    #else
    return false
    #endif
}

private func modelIsInstalled() -> Bool {
    guard files.fileExists(atPath: modelDirectory.appendingPathComponent("config.json").path),
          files.fileExists(atPath: modelDirectory.appendingPathComponent("tokenizer.json").path),
          let data = try? Data(contentsOf: modelDirectory.appendingPathComponent("model.safetensors.index.json")),
          let index = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let weights = index["weight_map"] as? [String: String], !weights.isEmpty else { return false }
    return Set(weights.values).allSatisfy { file in
        guard !file.contains("/"), !file.contains(".."), file.hasSuffix(".safetensors"),
              let attributes = try? files.attributesOfItem(atPath: modelDirectory.appendingPathComponent(file).path),
              let size = attributes[.size] as? NSNumber else { return false }
        return size.int64Value > 0
    }
}

@discardableResult private func lockNetworking() -> Bool {
    if networkBlocked { return true }
    guard enter_offline_sandbox() == 0 else { return false }
    networkBlocked = true
    return true
}

// Existing installs lock down before creating the app. First-time setup can
// download the model only; microphone/ASR code separately requires this lock.
if modelIsInstalled() || CommandLine.arguments.contains("--self-test") {
    guard lockNetworking() else {
        fputs("Private Dictation refused to launch: its offline sandbox could not be applied.\n", stderr)
        exit(1)
    }
}

if CommandLine.arguments.contains("--self-test") {
    let parentDenied = outbound_network_is_denied() == 1
    let child = Process()
    if files.isExecutableFile(atPath: bundledEngine.path) {
        child.executableURL = bundledEngine; child.arguments = ["--network-test"]
    } else {
        child.executableURL = python
        child.arguments = ["-c", "import socket,sys,errno\ntry:\n s=socket.socket(); s.settimeout(1); s.connect(('1.1.1.1',443))\nexcept OSError as e:\n sys.exit(0 if e.errno in (errno.EPERM,errno.EACCES) else 2)\nsys.exit(1)"]
    }
    child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
    do {
        try child.run(); child.waitUntilExit()
        print("App network blocked: \(parentDenied). Speech engine network blocked: \(child.terminationStatus == 0).")
        exit(parentDenied && child.terminationStatus == 0 ? 0 : 1)
    } catch { fputs("Privacy self-test could not run.\n", stderr); exit(1) }
}

// A fixed, synthetic sentence for verifying real field insertion without a
// microphone, a transcript argument, or a clipboard operation. Not dictation.
if CommandLine.arguments.contains("--insertion-self-test") || CommandLine.arguments.contains("--unicode-insertion-self-test") {
    guard lockNetworking(), AXIsProcessTrusted() else {
        fputs("Insertion self-test requires this app’s Accessibility permission.\n", stderr); exit(2)
    }
    let app = NSApplication.shared
    app.setActivationPolicy(.prohibited)
    let testInserter = DirectTextInsertion()
    let deadline = ProcessInfo.processInfo.systemUptime + 20
    var stableElement: AXUIElement?
    var stablePID: pid_t?
    var stableSince: TimeInterval?
    print("Waiting up to 20 seconds: focus a blank new TextEdit document and release all modifiers.")
    fflush(stdout)
    func waitForTestField() {
        let now = ProcessInfo.processInfo.systemUptime
        let frontmost = NSWorkspace.shared.frontmostApplication
        let textEditFrontmost = frontmost?.bundleIdentifier == "com.apple.TextEdit"
        let element = DirectTextInsertion.focusedElement()
        let textual = DirectTextInsertion.isTextField(element)
        let nonsecure = element != nil && !DirectTextInsertion.isSecure(element)
        let modifiersReleased = NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if textEditFrontmost, let pid = frontmost?.processIdentifier, let element = element,
           textual, nonsecure, modifiersReleased {
            if stablePID != pid || stableElement.map({ CFEqual($0, element) }) != true {
                stablePID = pid; stableElement = element; stableSince = now
            }
            if let stableSince = stableSince, now - stableSince >= 0.2 {
                testInserter.insert("Private Dictation direct insertion test: café, £5, and 🦊.", element: element, pid: pid,
                                    preferAccessibility: !CommandLine.arguments.contains("--unicode-insertion-self-test")) { remaining, error in
                    if let error = error { fputs((error + "\n").cString(using: .utf8)!, stderr); exit(1) }
                    print("Direct insertion self-test completed; no clipboard API was used.")
                    exit(remaining == nil ? 0 : 1)
                }
                return
            }
        } else {
            stablePID = nil; stableElement = nil; stableSince = nil
        }
        guard now < deadline else {
            var focusedPID: pid_t = 0
            let focusedPIDAvailable = element.map { AXUIElementGetPid($0, &focusedPID) == .success } == true
            let focusedPIDMatchesFrontmost = focusedPIDAvailable && frontmost?.processIdentifier == focusedPID
            let focusedPIDIsTextEdit = focusedPIDAvailable && NSRunningApplication(processIdentifier: focusedPID)?.bundleIdentifier == "com.apple.TextEdit"
            let diagnostic = "Insertion self-test timed out: TextEdit frontmost=\(textEditFrontmost), frontmost PID available=\(frontmost != nil), frontmost bundle identifier available=\(frontmost?.bundleIdentifier != nil), frontmost is test process=\(frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier), focused element available=\(element != nil), focused PID available=\(focusedPIDAvailable), focused PID matches frontmost=\(focusedPIDMatchesFrontmost), focused PID belongs to TextEdit=\(focusedPIDIsTextEdit), text field=\(textual), nonsecure=\(nonsecure), modifiers released=\(modifiersReleased).\n"
            fputs(diagnostic.cString(using: .utf8)!, stderr); exit(2)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { waitForTestField() }
    }
    DispatchQueue.main.async { waitForTestField() }
    app.run()
    exit(1)
}

/// A private JSON-lines pipe, with no local HTTP server or persistent logs.
final class EngineProcess {
    var onMessage: (([String: Any]) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var generation = UUID()
    var isRunning: Bool { process?.isRunning == true }

    func start(arguments: [String], offline: Bool) throws {
        stop()
        let generation = self.generation
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        if files.isExecutableFile(atPath: bundledEngine.path) {
            process.executableURL = bundledEngine; process.arguments = arguments
        } else {
            process.executableURL = python
            process.arguments = ["-u", resources.appendingPathComponent("worker.py").path] + arguments
        }
        var environment = ["HOME": files.homeDirectoryForCurrentUser.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                           "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8",
                           "HF_HUB_DISABLE_TELEMETRY": "1", "DO_NOT_TRACK": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        if offline { environment["HF_HUB_OFFLINE"] = "1" }
        process.environment = environment
        process.standardInput = stdin; process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async {
                guard let self = self, self.generation == generation else { return }
                self.receive(data)
            }
        }
        process.terminationHandler = { [weak self] process in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                guard let self = self, self.generation == generation else { return }
                self.onMessage?(["event": "exit", "status": process.terminationStatus])
            }
        }
        self.process = process; input = stdin.fileHandleForWriting
        do { try process.run() } catch { stop(); throw error }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        guard buffer.count <= 1_048_576 else {
            stop(); onMessage?(["event": "error", "message": "The speech engine sent an invalid response. Restart the engine."]); return
        }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] { onMessage?(message) }
        }
    }

    func transcribe(id: String, path: URL, context: String) throws {
        guard isRunning, let input = input else { throw NSError(domain: "FreeDictation", code: 1) }
        var data = try JSONSerialization.data(withJSONObject: ["id": id, "path": path.path, "context": context])
        data.append(10); try input.write(contentsOf: data)
    }

    func stop() {
        generation = UUID()
        output?.readabilityHandler = nil; output = nil
        try? input?.close(); input = nil; buffer.removeAll(keepingCapacity: false)
        if let process = process, process.isRunning {
            process.terminate()
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        process = nil
    }
}

private enum Phase {
    case needsModel, downloading, loading, ready, recording, transcribing, pending, failed
}

final class AppDelegate: NSObject, NSApplicationDelegate, AVAudioRecorderDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var statusItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private var retryItem: NSMenuItem!
    private let engine = EngineProcess(), downloader = EngineProcess()
    private let setup = SetupWindow()
    private let preferences = PreferencesStore()
    private lazy var settings = SettingsWindow(store: preferences)
    private let hotKey = ShortcutHotKey()
    private let inserter = DirectTextInsertion()
    private var phase: Phase = .loading
    private var status = "Loading speech model…"
    private var engineReady = false
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var taskTimer: Timer?
    private var watchdog: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shortcut = ShortcutMatcher(.defaultShortcut)
    private var pendingHotKeyToggle = false
    private var hotKeyReleased = false
    private var requestID: String?
    private var pendingText: String?
    private var targetPID: pid_t?
    private var targetElement: AXUIElement?
    private var insertionCancelled = false
    private var pendingWordCount = 0
    private var pendingAudioSeconds = 0.0
    private var pendingProcessingSeconds = 0.0
    private var wasTrusted = false
    private var recordings: URL!
    private var downloadProgress: Double = 0
    private var downloadedBytes: Int64 = 0
    private var downloadCompleted = false
    private var downloadStallTimer: Timer?
    private var lastDownloadActivity = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mike.dictation")
        if let other = others.first(where: { $0.processIdentifier != getpid() }) {
            other.activate(options: []); NSApp.terminate(nil); return
        }
        buildMenu()
        buildApplicationMenu()
        setup.onModel = { [weak self] in
            guard let self = self else { return }
            if self.phase == .downloading { self.cancel() }
            else if modelIsInstalled() { self.restartEngine() }
            else { self.startDownload() }
        }
        setup.onMicrophone = { [weak self] in self?.requestMicrophone() }
        setup.onAccessibility = { [weak self] in self?.requestAccessibility() }
        settings.onShortcutChange = { [weak self] candidate in
            guard let self = self else { return "Settings unavailable." }
            if let error = self.hotKey.register(candidate) {
                _ = self.hotKey.register(self.preferences.shortcut)
                return error
            }
            self.preferences.setShortcut(candidate); self.shortcut = ShortcutMatcher(candidate)
            self.setup.updateShortcut(candidate); self.refreshUI()
            return nil
        }
        settings.onCaptureChange = { [weak self] capturing in
            guard let self = self else { return }
            if capturing { self.hotKey.unregister(); self.pendingHotKeyToggle = false }
            else { self.installShortcut() }
        }
        hotKey.onPressed = { [weak self] in
            guard let self = self, !self.settings.isCapturingShortcut else { return }
            self.pendingHotKeyToggle = true; self.hotKeyReleased = false
        }
        hotKey.onReleased = { [weak self] in self?.hotKeyReleased = true; self?.fireReleasedHotKey() }
        setup.updateShortcut(preferences.shortcut)
        engine.onMessage = { [weak self] in self?.handleEngine($0) }
        downloader.onMessage = { [weak self] in self?.handleDownload($0) }
        do {
            recordings = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("local.mike.dictation", isDirectory: true)
            try files.createDirectory(at: recordings, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: recordings.path)
            cleanRecordings()
            if !hardwareSupported { setPhase(.failed, "Requires an Apple silicon Mac with at least 16 GB of memory.") }
            else if modelIsInstalled() { restartEngine() }
            else { setPhase(.needsModel, "Download the model to get started") }
        } catch { setPhase(.failed, "Temporary audio folder unavailable. Quit and reopen Private Dictation.") }
        installShortcut()
        wasTrusted = AXIsProcessTrusted()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted && !self.wasTrusted { self.installShortcut() }
            self.wasTrusted = trusted
            self.refreshUI()
        }
        if !modelIsInstalled() || !permissionsReady || !UserDefaults.standard.bool(forKey: "FreeDictationSetupSeen") {
            UserDefaults.standard.set(true, forKey: "FreeDictationSetupSeen")
            DispatchQueue.main.async { self.showSetup() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSetup(); return true
    }

    private var permissionsReady: Bool {
        AXIsProcessTrusted() && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    private func buildMenu() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu(); menu.autoenablesItems = false; menu.delegate = self
        let brand = NSMenuItem(title: "Private Dictation", action: nil, keyEquivalent: "")
        brand.isEnabled = false; menu.addItem(brand)
        statusItem = NSMenuItem(title: status, action: nil, keyEquivalent: ""); statusItem.isEnabled = false
        menu.addItem(statusItem)
        let model = NSMenuItem(title: "Qwen3-ASR 1.7B · English", action: nil, keyEquivalent: "")
        model.isEnabled = false; menu.addItem(model)
        menu.addItem(.separator())
        toggleItem = add(menu, "Start dictation    ⌘ ⌥", #selector(toggle))
        cancelItem = add(menu, "Discard dictation", #selector(cancel))
        retryItem = add(menu, "Restart speech engine", #selector(restartEngine))
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(showSettings), key: ",")
        add(menu, "Setup & permissions…", #selector(showSetup))
        add(menu, "About Private Dictation", #selector(about))
        menu.addItem(.separator())
        add(menu, "Quit Private Dictation", #selector(quit), key: "q")
        item.menu = menu
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
        entry.target = self; menu.addItem(entry); return entry
    }

    func menuWillOpen(_ menu: NSMenu) { refreshUI() }

    private func buildApplicationMenu() {
        let menu = NSMenu(), appMenu = NSMenu(), root = NSMenuItem()
        root.submenu = appMenu; menu.addItem(root)
        add(appMenu, "About Private Dictation", #selector(about))
        add(appMenu, "Settings…", #selector(showSettings), key: ",")
        add(appMenu, "Setup & permissions…", #selector(showSetup))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        appMenu.addItem(.separator())
        add(appMenu, "Quit Private Dictation", #selector(quit), key: "q")
        NSApp.mainMenu = menu
    }

    private func installShortcut() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        shortcut = ShortcutMatcher(preferences.shortcut)
        pendingHotKeyToggle = false; hotKeyReleased = false
        if let error = hotKey.register(preferences.shortcut) { status = error }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.keyEvent($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.keyEvent(event); return event
        }
    }

    private func keyEvent(_ event: NSEvent) {
        guard !settings.isCapturingShortcut else { return }
        if event.type == .keyDown {
            shortcut.keyDown()
            if !event.isARepeat && event.keyCode == 53 && (recorder != nil || pendingText != nil || requestID != nil || inserter.isInserting) { cancel() }
            return
        }
        if preferences.shortcut.keyCode != nil { fireReleasedHotKey() }
        else if shortcut.flagsChanged(ShortcutModifiers(event.modifierFlags)) { toggle() }
    }

    private func fireReleasedHotKey() {
        guard pendingHotKeyToggle, hotKeyReleased, !settings.isCapturingShortcut,
              ShortcutModifiers(NSEvent.modifierFlags).intersection(.supported).isEmpty else { return }
        pendingHotKeyToggle = false; hotKeyReleased = false; toggle()
    }

    @objc private func toggle() {
        guard !inserter.isInserting else { return }
        if recorder != nil { finishRecording(); return }
        if pendingText != nil { attemptInsertion(requireOriginalFocus: false); return }
        guard requestID == nil, engineReady else { NSSound.beep(); return }
        guard permissionsReady else { setPhase(.ready, "Permissions needed — open Setup & permissions"); NSSound.beep(); return }
        guard networkBlocked else { setPhase(.failed, "Offline protection unavailable. Quit and reopen Private Dictation."); return }
        // Do not dictate while our setup window owns focus.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != getpid() else {
            setPhase(.ready, "Click a text field in another app, then use the shortcut"); NSSound.beep(); return
        }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetElement = DirectTextInsertion.focusedElement()
        guard !DirectTextInsertion.isSecure(targetElement) else {
            setPhase(.ready, "Dictation is disabled in secure fields."); NSSound.beep(); return
        }
        guard DirectTextInsertion.isTextField(targetElement) else {
            setPhase(.ready, "Click a text field first, then use the shortcut."); NSSound.beep(); return
        }
        let path = recordings.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            let audio = try AVAudioRecorder(url: path, settings: [AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])
            audio.delegate = self
            guard audio.prepareToRecord(), audio.record() else { throw NSError(domain: "FreeDictation", code: 3) }
            recordingURL = path; recorder = audio
            setPhase(.recording, "Listening · use the shortcut to stop")
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in self?.finishRecording() }
        } catch {
            try? files.removeItem(at: path)
            setPhase(.ready, "Microphone unavailable. Check your input device and permissions.")
        }
    }

    private func finishRecording() {
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder?.stop(); recorder = nil
        guard let path = recordingURL else { idle(); return }
        let id = UUID().uuidString; requestID = id
        setPhase(.transcribing, "Transcribing on this Mac…")
        do {
            try engine.transcribe(id: id, path: path, context: preferences.vocabularyContext)
            taskTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                guard let self = self, self.requestID == id else { return }
                self.engine.stop(); self.engineReady = false; self.requestID = nil; self.clearRecording()
                self.setPhase(.failed, "Transcription timed out. Restart the speech engine to try again.")
            }
        } catch {
            clearRecording(); requestID = nil; engineReady = false
            setPhase(.failed, "Speech engine unavailable. Choose Restart speech engine.")
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        cancel(); setPhase(engineReady ? .ready : .failed, "Recording failed. Check your microphone and try again.")
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        guard !flag, self.recorder === recorder else { return }
        cancel(); setPhase(engineReady ? .ready : .failed, "Recording interrupted. Check your microphone and try again.")
    }

    @objc private func restartEngine() {
        guard hardwareSupported, recorder == nil, requestID == nil, pendingText == nil, phase != .downloading,
              let recordings = recordings else { return }
        guard modelIsInstalled() else { setPhase(.needsModel, "Download the model to get started"); return }
        guard lockNetworking() else { setPhase(.failed, "Offline protection failed. Recording is disabled."); return }
        taskTimer?.invalidate(); engine.stop(); engineReady = false
        setPhase(.loading, "Loading speech model…")
        do {
            try engine.start(arguments: ["--model-dir", modelDirectory.path, "--recording-dir", recordings.path], offline: true)
            taskTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { [weak self] _ in
                guard let self = self, !self.engineReady else { return }
                self.engine.stop(); self.setPhase(.failed, "Model loading timed out. Restart the speech engine to retry.")
            }
        } catch { setPhase(.failed, "Speech engine could not start. Reinstall Private Dictation, then try again.") }
    }

    private func handleEngine(_ message: [String: Any]) {
        switch message["event"] as? String {
        case "ready": taskTimer?.invalidate(); taskTimer = nil; engineReady = true; idle()
        case "result":
            guard let id = message["id"] as? String, id == requestID else { return }
            taskTimer?.invalidate(); taskTimer = nil; requestID = nil; clearRecording()
            let rawText = (message["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let text = preferences.rules.apply(to: rawText)
            guard !text.isEmpty else { setPhase(.ready, "No speech detected · ready to try again"); return }
            pendingWordCount = text.split(whereSeparator: { $0.isWhitespace }).count
            pendingAudioSeconds = (message["audio_seconds"] as? NSNumber)?.doubleValue ?? 0
            pendingProcessingSeconds = (message["seconds"] as? NSNumber)?.doubleValue ?? 0
            pendingText = text; attemptInsertion(requireOriginalFocus: true)
        case "error":
            if let id = message["id"] as? String, id != requestID { return }
            taskTimer?.invalidate(); taskTimer = nil; requestID = nil; clearRecording()
            if !engine.isRunning { engineReady = false }
            if !engineReady { engine.stop() }
            setPhase(engineReady ? .ready : .failed, message["message"] as? String ?? "Transcription failed. Try again.")
        case "exit":
            taskTimer?.invalidate(); taskTimer = nil
            engineReady = false; requestID = nil; clearRecording()
            if pendingText != nil { setPhase(.pending, "Text ready · use the shortcut to insert") }
            else { setPhase(.failed, "Speech engine stopped. Choose Restart speech engine.") }
        default: break
        }
    }

    private func startDownload() {
        guard hardwareSupported else {
            setPhase(.failed, "Requires an Apple silicon Mac with at least 16 GB of memory."); return
        }
        guard !networkBlocked, phase != .downloading else {
            setPhase(.failed, "Quit and reopen Private Dictation to download the model."); return
        }
        guard let capacity = try? dataRoot.deletingLastPathComponent().resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage,
              capacity >= 6_000_000_000 else {
            setPhase(.needsModel, "At least 6 GB of free disk space is needed for the model."); return
        }
        downloadCompleted = false; downloadProgress = 0; downloadedBytes = 0
        lastDownloadActivity = Date(); setPhase(.downloading, "Downloading speech model…")
        do {
            try downloader.start(arguments: ["--download-model", "--model-dir", modelDirectory.path], offline: false)
            downloadStallTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                guard let self = self, self.phase == .downloading,
                      Date().timeIntervalSince(self.lastDownloadActivity) > 300 else { return }
                self.downloader.stop(); self.downloadStallTimer?.invalidate()
                self.setPhase(.needsModel, "Download stalled. Check your connection, then resume the download.")
            }
        } catch { setPhase(.needsModel, "Download could not start. Reinstall Private Dictation and try again.") }
    }

    private func handleDownload(_ message: [String: Any]) {
        guard phase == .downloading else { return }
        lastDownloadActivity = Date()
        switch message["event"] as? String {
        case "download_progress":
            downloadProgress = min(1, max(0, (message["progress"] as? NSNumber)?.doubleValue ?? 0))
            downloadedBytes = (message["downloaded_bytes"] as? NSNumber)?.int64Value ?? 0
            status = "Downloading model · \(Int(downloadProgress * 100))%"; refreshUI()
        case "download_complete":
            downloadCompleted = true; downloader.stop(); downloadStallTimer?.invalidate(); downloadStallTimer = nil
            guard modelIsInstalled() else { setPhase(.needsModel, "Download incomplete. Resume to repair the model."); return }
            phase = .needsModel
            restartEngine()
        case "error", "exit":
            guard !downloadCompleted else { return }
            downloader.stop(); downloadStallTimer?.invalidate(); downloadStallTimer = nil
            setPhase(.needsModel, message["message"] as? String ?? "Download interrupted. Resume to try again.")
        default: break
        }
    }

    private func attemptInsertion(requireOriginalFocus: Bool) {
        guard let text = pendingText else { return }
        guard AXIsProcessTrusted() else { setPhase(.pending, "Text ready · enable Accessibility, then use the shortcut"); return }
        let focus = DirectTextInsertion.focusedElement()
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let sameApp = pid == targetPID
        let sameField = targetElement.map { old in focus.map { CFEqual(old, $0) } ?? false } ?? false
        let held = !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        guard !held, let focus = focus, let pid = pid, pid != getpid(),
              !requireOriginalFocus || (sameApp && sameField) else {
            setPhase(.pending, "Text ready · click its destination and use the shortcut"); return
        }
        guard !DirectTextInsertion.isSecure(focus) else {
            setPhase(.pending, "Secure field blocked. Click a normal text field, or discard."); return
        }
        insertionCancelled = false
        inserter.insert(text, element: focus, pid: pid) { [weak self] remaining, error in
            guard let self = self else { return }
            if self.insertionCancelled { self.pendingText = nil; self.clearPendingMetrics(); self.idle(); return }
            if let error = error {
                self.pendingText = remaining
                self.setPhase(remaining == nil ? .ready : .pending, error)
                if remaining == nil { self.clearPendingMetrics() }
                return
            }
            self.preferences.recordInsertion(words: self.pendingWordCount,
                audioSeconds: self.pendingAudioSeconds, processingSeconds: self.pendingProcessingSeconds)
            self.pendingText = nil; self.clearPendingMetrics(); self.targetElement = nil; self.targetPID = nil
            self.settings.refreshInsights(); self.idle()
        }
        refreshUI()
    }

    private func clearPendingMetrics() {
        pendingWordCount = 0; pendingAudioSeconds = 0; pendingProcessingSeconds = 0
    }

    @objc private func cancel() {
        if inserter.isInserting {
            insertionCancelled = true; inserter.cancel(); pendingText = nil; clearPendingMetrics(); idle(); return
        }
        if phase == .downloading {
            downloader.stop(); downloadStallTimer?.invalidate(); downloadStallTimer = nil
            setPhase(.needsModel, "Download paused. Resume when you’re ready."); return
        }
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder?.stop(); recorder = nil; pendingText = nil; clearPendingMetrics(); targetElement = nil; targetPID = nil
        if requestID != nil {
            taskTimer?.invalidate(); taskTimer = nil; requestID = nil; engineReady = false
            engine.stop(); clearRecording(); restartEngine(); return
        }
        clearRecording(); idle()
    }

    private func clearRecording() {
        if let path = recordingURL { try? files.removeItem(at: path) }; recordingURL = nil
    }

    private func cleanRecordings() {
        guard let recordings = recordings, let urls = try? files.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "wav" { try? files.removeItem(at: url) }
    }

    private func setPhase(_ phase: Phase, _ text: String) { self.phase = phase; status = text; refreshUI() }
    private func idle() { setPhase(engineReady ? .ready : .failed, engineReady ? "Ready · offline" : "Speech engine unavailable") }

    private func refreshUI() {
        guard item != nil else { return }
        let text = phase == .ready && !permissionsReady ? "Permissions needed — open Setup & permissions" : status
        statusItem.title = text
        let symbol: String
        switch phase {
        case .recording: symbol = "mic.fill"
        case .transcribing, .loading: symbol = "waveform"
        case .pending: symbol = "text.cursor"
        case .needsModel, .downloading: symbol = "arrow.down.circle"
        case .failed: symbol = "exclamationmark.circle"
        case .ready: symbol = permissionsReady ? "mic" : "exclamationmark.circle"
        }
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Private Dictation: " + text)
        item.button?.contentTintColor = phase == .recording ? .systemRed : nil
        item.button?.toolTip = "Private Dictation — " + text
        toggleItem.title = recorder != nil ? "Stop and insert    " + preferences.shortcut.display : (pendingText != nil ? "Insert here    " + preferences.shortcut.display : "Start dictation    " + preferences.shortcut.display)
        toggleItem.isEnabled = !inserter.isInserting && (recorder != nil || pendingText != nil || (engineReady && permissionsReady && requestID == nil))
        cancelItem.title = phase == .downloading ? "Pause model download" : "Discard dictation"
        cancelItem.isEnabled = (recorder != nil || pendingText != nil || requestID != nil || inserter.isInserting || phase == .downloading)
        retryItem.isEnabled = hardwareSupported && modelIsInstalled() && recorder == nil && requestID == nil && pendingText == nil && !inserter.isInserting && phase != .loading && phase != .downloading
        if setup.window?.isVisible == true { updateSetup(text) }
    }

    private func updateSetup(_ text: String) {
        let installed = modelIsInstalled()
        let ready = installed && engineReady && permissionsReady
        let modelDetail: String
        if phase == .downloading {
            let amount = ByteCountFormatter.string(fromByteCount: downloadedBytes, countStyle: .decimal)
            modelDetail = "\(Int(downloadProgress * 100))% · \(amount) downloaded. You can pause and resume."
        } else if installed {
            modelDetail = "Qwen3-ASR 1.7B · full precision · English only. Stored locally."
        } else {
            modelDetail = "One-time download of about 4.7 GB from Hugging Face. At least 6 GB of disk space required."
        }
        let action = phase == .downloading ? "Pause" : (installed ? (engineReady ? "Installed ✓" : (phase == .loading ? "Loading…" : "Retry engine")) : "Download model")
        setup.update(SetupStatus(headline: ready ? "You’re ready to dictate." : "Set up Private Dictation",
                                detail: ready ? "Click a text field in any app, then use your dictation shortcut. Private Dictation runs quietly in your menu bar." : text,
                                modelDetail: modelDetail, modelAction: action,
                                modelEnabled: hardwareSupported && (phase == .downloading || (!installed && !networkBlocked) || (installed && !engineReady && phase != .loading)),
                                progress: phase == .downloading ? downloadProgress : nil,
                                microphoneReady: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                                microphoneDenied: [.denied, .restricted].contains(AVCaptureDevice.authorizationStatus(for: .audio)),
                                accessibilityReady: AXIsProcessTrusted(), offline: networkBlocked, ready: ready))
    }

    @objc private func showSettings() {
        guard recorder == nil, requestID == nil, !inserter.isInserting else {
            status = "Finish or discard dictation before changing settings."; refreshUI(); NSSound.beep(); return
        }
        settings.present()
    }

    @objc private func showSetup() { updateSetup(status); setup.present() }

    private func requestMicrophone() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.refreshUI() } }
        } else {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Private Dictation", .applicationVersion: "1.0",
            .version: "English · Qwen3-ASR 1.7B", .credits: NSAttributedString(string: "Private, local dictation for your Mac.\nNo account. No transcript history. No clipboard use.\n\nThe model download requires internet. During dictation, app and engine network access is blocked. Inserted text follows the destination app’s policies.")])
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        recordingTimer?.invalidate(); taskTimer?.invalidate(); watchdog?.invalidate(); downloadStallTimer?.invalidate()
        recorder?.stop(); engine.stop(); downloader.stop(); insertionCancelled = true; inserter.cancel(); hotKey.unregister(); pendingText = nil; cleanRecordings()
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
