import AppKit
import QuartzCore

struct SetupStatus {
    var headline: String
    var detail: String
    var modelDetail: String
    var modelAction: String
    var modelEnabled: Bool
    var progress: Double?
    var microphoneReady: Bool
    var microphoneDenied: Bool
    var accessibilityReady: Bool
    var offline: Bool
    var ready: Bool
}

enum Palette {
    static let background = NSColor(calibratedRed: 0.055, green: 0.069, blue: 0.064, alpha: 1)
    static let card = NSColor(calibratedRed: 0.096, green: 0.112, blue: 0.103, alpha: 1)
    static let border = NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.19, alpha: 1)
    static let ink = NSColor(calibratedRed: 0.93, green: 0.94, blue: 0.88, alpha: 1)
    static let muted = NSColor(calibratedRed: 0.60, green: 0.67, blue: 0.61, alpha: 1)
    static let mint = NSColor(calibratedRed: 0.67, green: 0.89, blue: 0.73, alpha: 1)
}

final class SetupDocument: NSView {
    override var isFlipped: Bool { true }
}

final class SetupBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        Palette.background.setFill(); dirtyRect.fill()
    }
}

/// A vector mark: a sound wave inside a shield, never a recording overlay.
final class PrivacyMark: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let tile = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 16, yRadius: 16)
        Palette.card.setFill(); tile.fill()
        Palette.border.setStroke(); tile.lineWidth = 1; tile.stroke()
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 32, y: 49)); shield.line(to: NSPoint(x: 47, y: 43))
        shield.line(to: NSPoint(x: 46, y: 28))
        shield.curve(to: NSPoint(x: 32, y: 14), controlPoint1: NSPoint(x: 44, y: 21), controlPoint2: NSPoint(x: 36, y: 16))
        shield.curve(to: NSPoint(x: 18, y: 28), controlPoint1: NSPoint(x: 28, y: 16), controlPoint2: NSPoint(x: 20, y: 21))
        shield.line(to: NSPoint(x: 17, y: 43)); shield.close()
        Palette.mint.withAlphaComponent(0.07).setFill(); shield.fill()
        Palette.mint.setStroke(); shield.lineWidth = 1.5; shield.stroke()
        for (x, height) in [(24.0, 6.0), (28.0, 12.0), (32.0, 18.0), (36.0, 12.0), (40.0, 6.0)] {
            let wave = NSBezierPath(roundedRect: NSRect(x: x - 1, y: 32 - height / 2, width: 2, height: height), xRadius: 1, yRadius: 1)
            Palette.mint.setFill(); wave.fill()
        }
    }
}

final class SetupButton: NSButton {
    var primary = false { didSet { needsDisplay = true } }
    private var hover = false
    private var tracking: NSTrackingArea?
    override var intrinsicContentSize: NSSize {
        NSSize(width: max(112, (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width + 26), height: 32)
    }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hover = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hover = false; needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        let fill = primary && isEnabled ? Palette.mint : (hover && isEnabled ? Palette.border : Palette.card)
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 8, yRadius: 8)
        fill.withAlphaComponent(pressed ? 0.78 : 1).setFill(); shape.fill()
        if !primary || !isEnabled { Palette.border.setStroke(); shape.lineWidth = 1; shape.stroke() }
        let ink = primary && isEnabled ? Palette.background : (isEnabled ? Palette.ink : Palette.muted)
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: ink]
        let size = (title as NSString).size(withAttributes: style)
        (title as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: style)
    }
}

/// A deliberate setup window. Recording and transcription never show a window.
final class SetupWindow: NSWindowController {
    var onModel: (() -> Void)?
    var onMicrophone: (() -> Void)?
    var onAccessibility: (() -> Void)?
    private let headline = NSTextField(labelWithString: "Your voice.\nYour Mac.")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let modelDetail = NSTextField(wrappingLabelWithString: "")
    private let modelButton = SetupButton(title: "Download model", target: nil, action: nil)
    private let microphoneDetail = NSTextField(wrappingLabelWithString: "")
    private let microphoneButton = SetupButton(title: "Allow microphone", target: nil, action: nil)
    private let accessibilityDetail = NSTextField(wrappingLabelWithString: "")
    private let accessibilityButton = SetupButton(title: "Open settings", target: nil, action: nil)
    private let shortcutDetail = NSTextField(wrappingLabelWithString: "")
    private let privacy = NSTextField(wrappingLabelWithString: "")
    private let connection = NSTextField(labelWithString: "○  SETUP")
    private let progress = NSProgressIndicator()
    private let doneButton = SetupButton(title: "Keep running in menu bar", target: nil, action: nil)
    private let column = NSStackView()
    private var lastReady = false
    private var presented = false

    init() {
        let height = min(CGFloat(812), (NSScreen.main?.visibleFrame.height ?? 880) - 70)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: max(580, height)),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Private Dictation"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.background
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        build(window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func build(_ window: NSWindow) {
        window.contentView = SetupBackground(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        let content = window.contentView!
        let scroll = NSScrollView()
        scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(scroll)
        let document = SetupDocument()
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        column.orientation = .vertical; column.alignment = .leading; column.spacing = 16
        column.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(column)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor, constant: 42),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -78),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            column.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 34),
            column.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -34),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12)
        ])

        let mark = PrivacyMark()
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 64).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 64).isActive = true
        let brand = label("Private Dictation", size: 18, weight: .semibold)
        let eyebrow = label("ENGLISH V1  /  MADE TO STAY LOCAL", size: 10, weight: .medium, secondary: true)
        eyebrow.attributedStringValue = NSAttributedString(string: eyebrow.stringValue, attributes: [.font: eyebrow.font!, .foregroundColor: Palette.muted, .kern: 1.1])
        let identity = NSView()
        identity.translatesAutoresizingMaskIntoConstraints = false
        brand.translatesAutoresizingMaskIntoConstraints = false
        eyebrow.translatesAutoresizingMaskIntoConstraints = false
        identity.addSubview(brand); identity.addSubview(eyebrow)
        NSLayoutConstraint.activate([
            identity.widthAnchor.constraint(equalToConstant: 250),
            identity.heightAnchor.constraint(equalToConstant: 41),
            brand.leadingAnchor.constraint(equalTo: identity.leadingAnchor),
            brand.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
            brand.topAnchor.constraint(equalTo: identity.topAnchor),
            brand.heightAnchor.constraint(equalToConstant: 21),
            eyebrow.leadingAnchor.constraint(equalTo: identity.leadingAnchor),
            eyebrow.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
            eyebrow.bottomAnchor.constraint(equalTo: identity.bottomAnchor),
            eyebrow.heightAnchor.constraint(equalToConstant: 13)
        ])
        let masthead = NSStackView(views: [mark, identity, NSView()])
        masthead.orientation = .horizontal; masthead.alignment = .centerY; masthead.spacing = 15
        column.addArrangedSubview(masthead)
        masthead.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        headline.font = .systemFont(ofSize: 37, weight: .semibold)
        headline.textColor = Palette.ink
        headline.maximumNumberOfLines = 2
        detail.font = .systemFont(ofSize: 13)
        detail.textColor = Palette.muted
        detail.maximumNumberOfLines = 3
        let intro = NSStackView(views: [headline, detail])
        intro.orientation = .vertical; intro.alignment = .leading; intro.spacing = 9
        column.addArrangedSubview(intro)
        intro.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        detail.widthAnchor.constraint(equalTo: intro.widthAnchor).isActive = true

        modelButton.target = self; modelButton.action = #selector(modelClicked); modelButton.primary = true
        microphoneButton.target = self; microphoneButton.action = #selector(microphoneClicked)
        accessibilityButton.target = self; accessibilityButton.action = #selector(accessibilityClicked)
        doneButton.target = self; doneButton.action = #selector(doneClicked); doneButton.primary = true
        doneButton.keyEquivalent = "\r"
        for button in [modelButton, microphoneButton, accessibilityButton, doneButton] {
            button.bezelStyle = .rounded; button.isBordered = false
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        progress.style = .bar; progress.minValue = 0; progress.maxValue = 1
        progress.isIndeterminate = false; progress.translatesAutoresizingMaskIntoConstraints = false
        progress.heightAnchor.constraint(equalToConstant: 4).isActive = true
        progress.isHidden = true
        let steps = NSStackView(views: [
            card("01", "The local speech model", modelDetail, modelButton, extra: progress),
            card("02", "Your microphone", microphoneDetail, microphoneButton),
            card("03", "The shortcut & insertion", accessibilityDetail, accessibilityButton)
        ])
        steps.orientation = .vertical; steps.alignment = .leading; steps.spacing = 9
        column.addArrangedSubview(steps)
        steps.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        for card in steps.arrangedSubviews { card.widthAnchor.constraint(equalTo: steps.widthAnchor).isActive = true }

        let shortcutTitle = label("A shortcut. And nothing in your way.", size: 13, weight: .semibold)
        shortcutDetail.font = .systemFont(ofSize: 12)
        shortcutDetail.textColor = Palette.muted
        shortcutDetail.stringValue = "Tap ⌘ Command + ⌥ Option, then release. Speak.\nTap again to stop and insert at your cursor. Escape discards.\nUp to two minutes per dictation. Status stays in your menu bar."
        let shortcut = NSStackView(views: [shortcutTitle, shortcutDetail])
        shortcut.orientation = .vertical; shortcut.alignment = .leading; shortcut.spacing = 7
        column.addArrangedSubview(shortcut)
        privacy.font = .systemFont(ofSize: 11); privacy.textColor = Palette.muted
        privacy.maximumNumberOfLines = 4
        column.addArrangedSubview(privacy)
        privacy.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        let requirements = label("Apple silicon · macOS 14+ · 16 GB memory minimum; 24 GB recommended.\nModel: 4.7 GB. 6 GB free disk space minimum; 8 GB recommended.\nTested on M5 with 32 GB; speed varies by Mac.", size: 10, secondary: true)
        column.addArrangedSubview(requirements)
        requirements.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true

        connection.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        connection.textColor = Palette.mint
        let footer = NSStackView(views: [connection, NSView(), doneButton])
        footer.orientation = .horizontal; footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(footer)
        let rule = NSBox(); rule.boxType = .separator; rule.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(rule)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            rule.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            rule.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),
            footer.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            footer.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -22)
        ])
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? Palette.muted : Palette.ink
        return field
    }

    private func card(_ number: String, _ title: String, _ detail: NSTextField, _ button: SetupButton,
                      extra: NSView? = nil) -> NSView {
        let box = NSBox()
        box.boxType = .custom; box.borderWidth = 1
        box.borderColor = Palette.border; box.fillColor = Palette.card; box.cornerRadius = 11
        box.contentViewMargins = NSSize(width: 0, height: 0)
        box.translatesAutoresizingMaskIntoConstraints = false
        let body = NSStackView()
        body.orientation = .vertical; body.alignment = .leading; body.spacing = 7
        body.translatesAutoresizingMaskIntoConstraints = false
        let numberLabel = label(number, size: 10, weight: .medium, secondary: true)
        numberLabel.font = .monospacedSystemFont(ofSize: 10, weight: .medium)
        let row = NSStackView(views: [numberLabel, label(title, size: 13, weight: .medium), NSView(), button])
        row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        detail.font = .systemFont(ofSize: 12); detail.textColor = Palette.muted
        detail.maximumNumberOfLines = 3
        body.addArrangedSubview(row); body.addArrangedSubview(detail)
        if let extra = extra { body.addArrangedSubview(extra); extra.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true }
        let inner = box.contentView!
        inner.addSubview(body)
        NSLayoutConstraint.activate([
            body.leadingAnchor.constraint(equalTo: inner.leadingAnchor, constant: 17),
            body.trailingAnchor.constraint(equalTo: inner.trailingAnchor, constant: -17),
            body.topAnchor.constraint(equalTo: inner.topAnchor, constant: 11),
            body.bottomAnchor.constraint(equalTo: inner.bottomAnchor, constant: -13),
            row.widthAnchor.constraint(equalTo: body.widthAnchor),
            detail.widthAnchor.constraint(equalTo: body.widthAnchor)
        ])
        return box
    }

    func update(_ status: SetupStatus) {
        headline.stringValue = status.ready ? "Ready when\nyou are." : "Your voice.\nYour Mac."
        detail.stringValue = status.ready ? "Click a text field in any app. The shortcut turns your voice into text, entirely on this Mac." : status.detail
        modelDetail.stringValue = status.modelDetail
        modelButton.title = status.modelAction; modelButton.isEnabled = status.modelEnabled
        modelButton.invalidateIntrinsicContentSize(); modelButton.needsDisplay = true
        progress.isHidden = status.progress == nil
        progress.doubleValue = status.progress ?? 0
        microphoneDetail.stringValue = status.microphoneReady ? "Allowed. Recording starts only when you use the shortcut." :
            (status.microphoneDenied ? "Enable Private Dictation in System Settings → Privacy & Security → Microphone." : "macOS will ask once. Audio is processed on this Mac.")
        microphoneButton.title = status.microphoneReady ? "Allowed ✓" : (status.microphoneDenied ? "Open settings" : "Allow microphone")
        microphoneButton.isEnabled = !status.microphoneReady
        microphoneButton.invalidateIntrinsicContentSize(); microphoneButton.needsDisplay = true
        accessibilityDetail.stringValue = status.accessibilityReady ? "Allowed. The shortcut and automatic insertion are ready." :
            "Enable Private Dictation in System Settings. Needed for the shortcut and insertion; the app does not read document text."
        accessibilityButton.title = status.accessibilityReady ? "Allowed ✓" : "Open settings"
        accessibilityButton.isEnabled = !status.accessibilityReady
        accessibilityButton.invalidateIntrinsicContentSize(); accessibilityButton.needsDisplay = true
        privacy.stringValue = status.offline ?
            "Network access is blocked for the app and speech engine. Temporary audio is deleted after transcription. No transcript history or clipboard use. Inserted text follows the destination app’s policies." :
            "The one-time model download needs internet. Before any recording, the app blocks its own and the speech engine’s network access. No account, analytics, or transcript history."
        connection.stringValue = status.offline ? "●  OFFLINE BY DESIGN" : "○  ONE-TIME SETUP"
        doneButton.title = status.ready ? "Start dictating →" : "Keep running in menu bar"
        doneButton.invalidateIntrinsicContentSize(); doneButton.needsDisplay = true
        if status.ready && !lastReady && presented && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            headline.alphaValue = 0.5
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25; headline.animator().alphaValue = 1
            }
        }
        lastReady = status.ready
    }

    func present() {
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !presented && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            column.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22; column.animator().alphaValue = 1
            }
        }
        presented = true
    }

    func updateShortcut(_ shortcut: DictationShortcut) {
        let start = shortcut.keyCode == nil ? "Tap \(shortcut.display), then release. Speak." : "Press \(shortcut.display) to start. Speak."
        shortcutDetail.stringValue = start + "\nRepeat to stop and insert at your cursor. Escape discards.\nUp to two minutes per dictation. Change the shortcut in Settings."
    }
    @objc private func modelClicked() { onModel?() }
    @objc private func microphoneClicked() { onMicrophone?() }
    @objc private func accessibilityClicked() { onAccessibility?() }
    @objc private func doneClicked() { window?.close() }
}
