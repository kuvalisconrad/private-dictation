import AppKit
import AVFoundation
import ApplicationServices

let files = FileManager.default
let dataRoot = files.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Local Dictation")
let python = dataRoot.appendingPathComponent("runtime/bin/python")

// Apply before creating the app, loading a model, or accessing the microphone.
guard enter_offline_sandbox() == 0 else {
    fputs("Local Dictation refused to launch: network sandbox could not be applied.\n", stderr)
    exit(1)
}

if CommandLine.arguments.contains("--self-test") {
    let parentDenied = outbound_network_is_denied() == 1
    let child = Process()
    child.executableURL = python
    child.arguments = ["-c", "import socket,sys,errno\ntry:\n s=socket.socket(); s.settimeout(1); s.connect(('1.1.1.1',443))\nexcept OSError as e:\n sys.exit(0 if e.errno in (errno.EPERM,errno.EACCES) else 2)\nsys.exit(1)"]
    do {
        try child.run(); child.waitUntilExit()
        print("App network blocked: \(parentDenied). Python child network blocked: \(child.terminationStatus == 0).")
        exit(parentDenied && child.terminationStatus == 0 ? 0 : 1)
    } catch { fputs("Privacy self-test could not run.\n", stderr); exit(1) }
}

final class Backend {
    var onMessage: (([String: Any]) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var shuttingDown = false

    func start(model: URL, recordings: URL) throws {
        let process = Process(), stdin = Pipe(), stdout = Pipe()
        process.executableURL = python
        process.arguments = ["-u", Bundle.main.resourceURL!.appendingPathComponent("worker.py").path,
                             "--model-dir", model.path, "--recording-dir", recordings.path]
        process.environment = ["HOME": files.homeDirectoryForCurrentUser.path,
                               "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
                               "TMPDIR": NSTemporaryDirectory(), "LANG": "en_US.UTF-8",
                               "HF_HUB_OFFLINE": "1", "HF_HUB_DISABLE_TELEMETRY": "1",
                               "DO_NOT_TRACK": "1", "PYTHONDONTWRITEBYTECODE": "1"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        output = stdout.fileHandleForReading
        output?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self, !self.shuttingDown else { return }
                self.onMessage?(["event": "exit", "message": "Transcription engine stopped. Quit and reopen the app."])
            }
        }
        self.process = process
        input = stdin.fileHandleForWriting
        try process.run()
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            if let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                onMessage?(message)
            }
        }
    }

    func transcribe(id: String, path: URL) throws {
        guard process?.isRunning == true, let input = input else {
            throw NSError(domain: "LocalDictation", code: 1)
        }
        var data = try JSONSerialization.data(withJSONObject: ["id": id, "path": path.path])
        data.append(10)
        try input.write(contentsOf: data)
    }

    func stop() {
        shuttingDown = true
        output?.readabilityHandler = nil
        try? input?.close()
        if process?.isRunning == true { process?.terminate() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, AVAudioRecorderDelegate {
    private var item: NSStatusItem!
    private var statusItem: NSMenuItem!
    private var toggleItem: NSMenuItem!
    private var cancelItem: NSMenuItem!
    private let backend = Backend()
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var recordingTimer: Timer?
    private var watchdog: Timer?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var shortcut = ModifierShortcut()
    private var ready = false
    private var requestID: String?
    private var requestCancelled = false
    private var pendingText: String?
    private var targetPID: pid_t?
    private var targetElement: AXUIElement?
    private var pasteInFlight = false
    private var restoreClipboard: (() -> Void)?
    private var wasTrusted = false
    private var recordings: URL!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // Only one app instance may own the microphone and shortcut.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: "local.mike.dictation")
        if others.contains(where: { $0.processIdentifier != getpid() }) { NSApp.terminate(nil); return }
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        statusItem = NSMenuItem(title: "Loading local model…", action: nil, keyEquivalent: "")
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem(title: "Qwen3-ASR 1.7B · English · Offline", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        toggleItem = add(menu, "Start dictation    ⌘ then ⌥", #selector(toggle))
        cancelItem = add(menu, "Cancel / discard", #selector(cancel))
        menu.addItem(.separator())
        add(menu, "Set up permissions…", #selector(permissions))
        add(menu, "Quit Local Dictation", #selector(quit))
        item.menu = menu
        updateStatus("Loading local model…")
        do {
            // Temp audio is private, never in iCloud or the repository.
            recordings = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("local.mike.dictation", isDirectory: true)
            try files.createDirectory(at: recordings, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            cleanRecordings()
            let configData = try Data(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("model.json"))
            let config = try JSONSerialization.jsonObject(with: configData) as! [String: String]
            guard let folder = config["folder"], !folder.contains("/"), !folder.contains("..") else {
                throw NSError(domain: "LocalDictation", code: 2)
            }
            backend.onMessage = { [weak self] in self?.handle($0) }
            try backend.start(model: dataRoot.appendingPathComponent("models/" + folder), recordings: recordings)
        } catch { updateStatus("Setup missing — run scripts/setup.sh") }
        installShortcut()
        wasTrusted = AXIsProcessTrusted()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted && !self.wasTrusted { self.installShortcut(); if self.ready { self.idleStatus() } }
            self.wasTrusted = trusted
        }
        if !AXIsProcessTrusted() || AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self.permissions() }
        }
    }

    @discardableResult private func add(_ menu: NSMenu, _ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self; menu.addItem(entry); return entry
    }

    private func installShortcut() {
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
        shortcut = ModifierShortcut()
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] in self?.keyEvent($0) }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.keyEvent(event); return event
        }
    }

    private func keyEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            shortcut.keyDown()
            if event.keyCode == 53 && (recorder != nil || pendingText != nil || requestID != nil) { cancel() }
            return
        }
        let flags = event.modifierFlags
        if shortcut.flagsChanged(command: flags.contains(.command), option: flags.contains(.option),
                                 other: !flags.intersection([.control, .shift, .function]).isEmpty) { toggle() }
    }

    @objc private func toggle() {
        guard !pasteInFlight else { return }
        if recorder != nil { finishRecording(); return }
        if pendingText != nil { attemptPaste(requireOriginalFocus: false); return }
        guard requestID == nil else { return }
        guard ready else { return }
        guard AXIsProcessTrusted(), AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            permissions(); return
        }
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        targetElement = focusedElement()
        let path = recordings.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            let audio = try AVAudioRecorder(url: path, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16000,
                AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
            ])
            audio.delegate = self
            guard audio.prepareToRecord(), audio.record() else { throw NSError(domain: "LocalDictation", code: 3) }
            recordingURL = path; recorder = audio
            updateStatus("Listening…")
            recordingTimer = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
                self?.finishRecording()
            }
        } catch {
            try? files.removeItem(at: path)
            updateStatus("Could not start the microphone. Check permissions.")
        }
    }

    private func finishRecording() {
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder?.stop(); recorder = nil
        guard let path = recordingURL else { return }
        requestID = UUID().uuidString
        requestCancelled = false
        updateStatus("Transcribing locally…")
        do { try backend.transcribe(id: requestID!, path: path) }
        catch { clearRecording(); requestID = nil; updateStatus("Transcription engine unavailable. Reopen the app.") }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        cancel(); updateStatus("Microphone recording failed. Try again.")
    }

    private func handle(_ message: [String: Any]) {
        switch message["event"] as? String {
        case "ready":
            ready = true; idleStatus()
        case "result":
            guard let id = message["id"] as? String, id == requestID else { return }
            requestID = nil; clearRecording()
            if requestCancelled { requestCancelled = false; idleStatus(); return }
            let text = (message["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { updateStatus("No speech detected · ready to try again"); return }
            pendingText = text
            attemptPaste(requireOriginalFocus: true)
        case "error", "exit":
            if message["event"] as? String == "exit" { ready = false }
            requestID = nil; clearRecording()
            updateStatus(message["message"] as? String ?? "Engine error")
        default: break
        }
    }

    private func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func attemptPaste(requireOriginalFocus: Bool) {
        guard let text = pendingText, AXIsProcessTrusted() else {
            updateStatus("Enable Accessibility to paste"); return
        }
        let sameApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == targetPID
        let sameField = targetElement.map { old in focusedElement().map { CFEqual(old, $0) } ?? false } ?? true
        let held = !NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        if held || (requireOriginalFocus && (!sameApp || !sameField)) {
            updateStatus("Ready to paste · ⌘ then ⌥")
            return
        }
        let pasteboard = NSPasteboard.general
        let previous: [[(NSPasteboard.PasteboardType, Data)]] = (pasteboard.pasteboardItems ?? []).map { entry in
            entry.types.compactMap { type in entry.data(forType: type).map { (type, $0) } }
        }
        pasteboard.clearContents()
        let entry = NSPasteboardItem()
        entry.setString(text, forType: .string)
        // Clipboard managers that honor these conventions should ignore this item.
        entry.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        entry.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        guard pasteboard.writeObjects([entry]) else { updateStatus("Clipboard unavailable. Tap ⌘ then ⌥ to retry."); return }
        let changeCount = pasteboard.changeCount
        restoreClipboard = {
            guard pasteboard.changeCount == changeCount else { return }
            pasteboard.clearContents()
            let items = previous.map { pairs -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in pairs { item.setData(data, forType: type) }
                return item
            }
            if !items.isEmpty { pasteboard.writeObjects(items) }
        }
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: false) else {
            restoreClipboard?(); restoreClipboard = nil
            updateStatus("Paste failed. Tap ⌘ then ⌥ to retry."); return
        }
        pasteInFlight = true
        down.flags = .maskCommand; up.flags = .maskCommand
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        // Give the destination time to consume the paste before restoring the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self = self else { return }
            self.restoreClipboard?(); self.restoreClipboard = nil
            self.pendingText = nil; self.pasteInFlight = false
            self.idleStatus()
        }
    }

    @objc private func cancel() {
        recordingTimer?.invalidate(); recordingTimer = nil
        recorder?.stop(); recorder = nil
        pendingText = nil
        // A running inference finishes in the background; ignore its result.
        if requestID != nil {
            requestCancelled = true
            updateStatus("Finishing cancelled transcription…"); return
        }
        clearRecording(); idleStatus()
    }

    private func clearRecording() {
        if let path = recordingURL { try? files.removeItem(at: path) }
        recordingURL = nil
    }

    private func cleanRecordings() {
        guard let recordings = recordings, let urls = try? files.contentsOfDirectory(at: recordings, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "wav" { try? files.removeItem(at: url) }
    }

    private func updateStatus(_ text: String) {
        statusItem.title = text
        let symbol = recorder != nil ? "mic.fill" : (requestID != nil || !ready ? "waveform" : (pendingText != nil ? "doc.on.clipboard" : "mic"))
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: text)
        item.button?.contentTintColor = recorder != nil ? .systemRed : nil
        item.button?.toolTip = "Local Dictation — " + text
        toggleItem.title = recorder != nil ? "Stop and paste    ⌘ then ⌥" : (pendingText != nil ? "Paste here    ⌘ then ⌥" : "Start dictation    ⌘ then ⌥")
        cancelItem.isEnabled = recorder != nil || pendingText != nil || requestID != nil
    }

    private func idleStatus() {
        updateStatus(ready ? (AXIsProcessTrusted() ? "Ready · network blocked" : "Enable Accessibility to use the shortcut") : "Model unavailable")
    }

    @objc private func permissions() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Local Dictation"
        alert.informativeText = "Tap Command and Option, then release to start. Repeat to stop and paste. Escape cancels.\n\nAllow Microphone for recording and Accessibility for the shortcut and automatic paste.\n\nSpeech is processed on this Mac. The app and model process have network access blocked. Recordings are deleted after transcription."
        alert.addButton(withTitle: "Enable permissions")
        alert.addButton(withTitle: "Later")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.requestAccessibility() }
            }
        } else { requestAccessibility() }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        }
    }

    private func requestAccessibility() {
        guard !AXIsProcessTrusted() else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        recordingTimer?.invalidate(); watchdog?.invalidate()
        recorder?.stop(); backend.stop(); restoreClipboard?(); cleanRecordings()
        if let monitor = globalMonitor { NSEvent.removeMonitor(monitor) }
        if let monitor = localMonitor { NSEvent.removeMonitor(monitor) }
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
