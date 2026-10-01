import AppKit

final class SettingsWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    var onShortcutChange: ((DictationShortcut) -> String?)?
    var onCaptureChange: ((Bool) -> Void)?
    private(set) var isCapturingShortcut = false
    private let store: PreferencesStore
    private let container = NSView()
    private var panels: [NSView] = []
    private var tabs: [SetupButton] = []
    private var monitor: Any?
    private var capturedModifiers: ShortcutModifiers = []
    private let shortcutDisplay = NSTextField(labelWithString: "")
    private let shortcutMessage = NSTextField(wrappingLabelWithString: "")
    private let captureButton = SetupButton(title: "Record shortcut", target: nil, action: nil)
    private let table = NSTableView()
    private let phraseField = NSTextField()
    private let replacementField = NSTextField()
    private let dictionaryMessage = NSTextField(wrappingLabelWithString: "")
    private let deleteButton = SetupButton(title: "Delete selected", target: nil, action: nil)
    private var selectedEntry: UUID?
    private let insightsSwitch = NSButton(checkboxWithTitle: "Keep aggregate totals on this Mac", target: nil, action: nil)
    private let insightsSummary = NSTextField(wrappingLabelWithString: "")
    private let insightsReset = SetupButton(title: "Reset totals", target: nil, action: nil)

    init(store: PreferencesStore) {
        self.store = store
        let height = min(CGFloat(738), (NSScreen.main?.visibleFrame.height ?? 850) - 70)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: max(580, height)),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "Private Dictation Settings"; window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true; window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Palette.background; window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        build(window)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = secondary ? Palette.muted : Palette.ink
        return field
    }
    private func button(_ title: String, action: Selector, primary: Bool = false) -> SetupButton {
        let button = SetupButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded; button.isBordered = false; button.primary = primary
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
    private func stack(_ views: [NSView], spacing: CGFloat = 14) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = spacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    private func build(_ window: NSWindow) {
        window.contentView = SetupBackground(frame: NSRect(origin: .zero, size: window.contentLayoutRect.size))
        let content = window.contentView!
        let eyebrow = label("PRIVATE DICTATION / SETTINGS", size: 10, weight: .medium, secondary: true)
        eyebrow.attributedStringValue = NSAttributedString(string: eyebrow.stringValue, attributes: [.font: eyebrow.font!, .foregroundColor: Palette.muted, .kern: 1.1])
        let headline = label("Make it yours.", size: 34, weight: .semibold)
        let subhead = label("A shortcut that fits. Spellings that stick. Nothing recorded in a history.", size: 12, secondary: true)
        let header = stack([eyebrow, headline, subhead], spacing: 8)
        content.addSubview(header)
        let tabRow = NSStackView(); tabRow.orientation = .horizontal; tabRow.spacing = 8; tabRow.translatesAutoresizingMaskIntoConstraints = false
        for (index, title) in ["Shortcut", "Dictionary", "Insights"].enumerated() {
            let tab = button(title, action: #selector(tabClicked(_:))); tab.tag = index
            tabs.append(tab); tabRow.addArrangedSubview(tab)
        }
        content.addSubview(tabRow)
        container.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(container)
        panels = [shortcutPanel(), dictionaryPanel(), insightsPanel()]
        for panel in panels {
            panel.translatesAutoresizingMaskIntoConstraints = false; container.addSubview(panel)
            NSLayoutConstraint.activate([
                panel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                panel.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                panel.topAnchor.constraint(equalTo: container.topAnchor),
                panel.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor)
            ])
        }
        let privacy = label("LOCAL BY DESIGN  ·  NO CLIPBOARD  ·  NO DICTATION HISTORY", size: 10, weight: .medium, secondary: true)
        let done = button("Done", action: #selector(doneClicked), primary: true)
        let footer = NSStackView(views: [privacy, NSView(), done]); footer.orientation = .horizontal; footer.alignment = .centerY
        footer.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(footer)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 34),
            header.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -34),
            header.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            tabRow.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            tabRow.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 25),
            container.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            container.topAnchor.constraint(equalTo: tabRow.bottomAnchor, constant: 24),
            container.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -25),
            footer.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24)
        ])
        selectTab(0)
    }

    private func shortcutPanel() -> NSView {
        shortcutDisplay.font = .systemFont(ofSize: 35, weight: .medium); shortcutDisplay.textColor = Palette.mint
        shortcutMessage.font = .systemFont(ofSize: 12); shortcutMessage.textColor = Palette.muted
        shortcutMessage.maximumNumberOfLines = 4
        captureButton.target = self; captureButton.action = #selector(captureClicked); captureButton.bezelStyle = .rounded
        captureButton.isBordered = false; captureButton.primary = true
        let reset = button("Use Command–Option", action: #selector(resetShortcut))
        let row = NSStackView(views: [captureButton, reset, NSView()]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 10
        let panel = stack([
            label("One shortcut. Start and stop.", size: 19, weight: .medium),
            label("The same shortcut begins recording, then ends recording and inserts the result at your cursor.", size: 13, secondary: true),
            shortcutDisplay, row, shortcutMessage,
            label("Use a tap of at least two modifiers, or Command / Option / Control plus a key. Choose a combination you don’t use elsewhere. Reserved system shortcuts may be unavailable.", size: 12, secondary: true),
            label("Escape always discards a recording or a waiting result. No window appears while you dictate.", size: 12, secondary: true)
        ], spacing: 19)
        for field in panel.arrangedSubviews where field is NSTextField {
            field.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        }
        row.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true
        return panel
    }

    private func dictionaryPanel() -> NSView {
        let title = label("Names, terms, and your spelling.", size: 19, weight: .medium)
        let explanation = label("Add a phrase the model gets wrong and what you want written. These intentional entries stay on this Mac; they are never learned from or saved as dictation history.", size: 12, secondary: true)
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        scroll.borderType = .noBorder; scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 156).isActive = true
        table.delegate = self; table.dataSource = self; table.rowHeight = 32
        table.backgroundColor = Palette.card; table.gridColor = Palette.border
        table.selectionHighlightStyle = .regular; table.headerView = NSTableHeaderView()
        table.usesAlternatingRowBackgroundColors = false; table.allowsEmptySelection = true
        for (id, title, width) in [("phrase", "Heard phrase", 260.0), ("replacement", "Write instead", 350.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); column.title = title; column.width = width
            column.minWidth = 180; table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        scroll.documentView = table
        phraseField.placeholderString = "Heard phrase, e.g. acme corp"
        replacementField.placeholderString = "Write instead, e.g. AcmeCorp"
        for field in [phraseField, replacementField] {
            field.font = .systemFont(ofSize: 13); field.textColor = Palette.ink
            field.bezelStyle = .roundedBezel; field.drawsBackground = true; field.backgroundColor = Palette.card
            field.target = self; field.action = #selector(saveEntry)
        }
        let form = NSStackView(views: [phraseField, replacementField]); form.orientation = .horizontal; form.spacing = 10
        phraseField.widthAnchor.constraint(equalTo: replacementField.widthAnchor).isActive = true
        let save = button("Save entry", action: #selector(saveEntry), primary: true)
        let clear = button("New entry", action: #selector(clearEntry))
        deleteButton.target = self; deleteButton.action = #selector(deleteEntry)
        deleteButton.bezelStyle = .rounded; deleteButton.isBordered = false
        let row = NSStackView(views: [save, clear, NSView(), deleteButton]); row.orientation = .horizontal; row.spacing = 10
        dictionaryMessage.font = .systemFont(ofSize: 11); dictionaryMessage.textColor = Palette.muted
        dictionaryMessage.maximumNumberOfLines = 3
        let panel = stack([title, explanation, scroll, form, row, dictionaryMessage], spacing: 15)
        for view in [explanation, scroll, form, row, dictionaryMessage] { view.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true }
        return panel
    }

    private func insightsPanel() -> NSView {
        insightsSwitch.target = self; insightsSwitch.action = #selector(insightsChanged)
        insightsSwitch.contentTintColor = Palette.ink
        insightsSummary.font = .monospacedSystemFont(ofSize: 18, weight: .regular); insightsSummary.textColor = Palette.mint
        insightsSummary.maximumNumberOfLines = 6
        insightsReset.target = self; insightsReset.action = #selector(resetInsights)
        insightsReset.bezelStyle = .rounded; insightsReset.isBordered = false
        let panel = stack([
            label("A few numbers. Never your words.", size: 19, weight: .medium),
            label("Insights are off by default. If you enable them, we store only running totals: completed dictations, word count, speaking time, and processing time. No audio, transcript, timestamps, app names, or individual session records.", size: 13, secondary: true),
            insightsSwitch, insightsSummary, insightsReset,
            label("Turning insights off deletes the totals. Reset totals clears them while keeping your preference.", size: 12, secondary: true)
        ], spacing: 20)
        for field in panel.arrangedSubviews where field is NSTextField { field.widthAnchor.constraint(equalTo: panel.widthAnchor).isActive = true }
        return panel
    }

    func refresh() {
        if !isCapturingShortcut { shortcutDisplay.stringValue = store.shortcut.display }
        table.reloadData(); deleteButton.isEnabled = selectedEntry != nil
        if dictionaryMessage.stringValue.isEmpty {
            dictionaryMessage.stringValue = "Up to 200 entries. Whole phrases match without case sensitivity; longer phrases win. Replacements are literal and do not cascade. Entries also guide the local speech model."
        }
        refreshInsights()
        if shortcutMessage.stringValue.isEmpty { shortcutMessage.stringValue = "Click Record shortcut, press your combination, and release. Escape cancels." }
    }

    func refreshInsights() {
        insightsSwitch.state = store.insightsEnabled ? .on : .off
        let totals = store.insights
        insightsSummary.stringValue = store.insightsEnabled ?
            "\(totals.dictations) dictations inserted\n\(totals.words) words\n\(String(format: "%.1f", totals.audioSeconds / 60)) minutes speaking\n\(String(format: "%.1f", totals.dictations == 0 ? 0 : totals.processingSeconds / Double(totals.dictations))) seconds average processing" :
            "Insights are off.\nNo totals are being stored."
        insightsReset.isEnabled = store.insightsEnabled && totals.dictations > 0
    }

    private func selectTab(_ index: Int) {
        stopCapture()
        for (number, panel) in panels.enumerated() { panel.isHidden = number != index }
        for (number, tab) in tabs.enumerated() { tab.primary = number == index }
        refresh()
    }
    @objc private func tabClicked(_ sender: NSButton) { selectTab(sender.tag) }
    @objc private func captureClicked() {
        if isCapturingShortcut { stopCapture(); return }
        isCapturingShortcut = true; capturedModifiers = []; onCaptureChange?(true)
        captureButton.title = "Cancel recording"; captureButton.invalidateIntrinsicContentSize()
        shortcutDisplay.stringValue = "Press your shortcut…"
        shortcutMessage.stringValue = "Press a modifier-only combination, then release. Or press a modifier and a key. Escape cancels."
        shortcutMessage.textColor = Palette.muted
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self = self, self.isCapturingShortcut else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 { self.stopCapture(); return nil }
                guard !event.isARepeat else { return nil }
                let modifiers = ShortcutModifiers(event.modifierFlags).intersection(.supported)
                let name: String
                switch event.keyCode {
                case 49: name = "Space"
                case 36: name = "Return"
                case 51: name = "Delete"
                case 123: name = "←"
                case 124: name = "→"
                case 125: name = "↓"
                case 126: name = "↑"
                default:
                    let special: [UInt16: String] = [122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
                    name = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
                }
                self.accept(DictationShortcut(modifiers: modifiers, keyCode: event.keyCode, keyName: name)); return nil
            }
            let modifiers = ShortcutModifiers(event.modifierFlags)
            if modifiers.isEmpty, !self.capturedModifiers.isEmpty {
                self.accept(DictationShortcut(modifiers: self.capturedModifiers, keyCode: nil, keyName: nil))
            } else { self.capturedModifiers.formUnion(modifiers) }
            return nil
        }
    }

    private func accept(_ shortcut: DictationShortcut) {
        if let error = shortcut.validationError ?? onShortcutChange?(shortcut) {
            stopCapture(); shortcutMessage.stringValue = error; shortcutMessage.textColor = .systemOrange
            return
        }
        store.setShortcut(shortcut); stopCapture()
        shortcutMessage.stringValue = "Saved on this Mac. Your shortcut starts and stops dictation."
        shortcutMessage.textColor = Palette.mint; refresh()
    }
    private func stopCapture() {
        if let monitor = monitor { NSEvent.removeMonitor(monitor) }; monitor = nil
        if isCapturingShortcut { isCapturingShortcut = false; onCaptureChange?(false) }
        captureButton.title = "Record shortcut"; captureButton.invalidateIntrinsicContentSize()
        shortcutDisplay.stringValue = store.shortcut.display
    }
    @objc private func resetShortcut() { accept(.defaultShortcut) }

    func numberOfRows(in tableView: NSTableView) -> Int { store.dictionary.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < store.dictionary.count else { return nil }
        let entry = store.dictionary[row]
        let field = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "phrase" ? entry.phrase : entry.replacement)
        field.font = .systemFont(ofSize: 12); field.textColor = Palette.ink; field.lineBreakMode = .byTruncatingTail
        return field
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, table.selectedRow < store.dictionary.count else { selectedEntry = nil; deleteButton.isEnabled = false; return }
        let entry = store.dictionary[table.selectedRow]
        selectedEntry = entry.id; phraseField.stringValue = entry.phrase; replacementField.stringValue = entry.replacement
        deleteButton.isEnabled = true
    }
    @objc private func saveEntry() {
        if let error = store.saveEntry(id: selectedEntry, phrase: phraseField.stringValue, replacement: replacementField.stringValue) {
            dictionaryMessage.stringValue = error; dictionaryMessage.textColor = .systemOrange; return
        }
        clearEntry(); dictionaryMessage.stringValue = "Saved locally. This spelling applies to future dictations."
        dictionaryMessage.textColor = Palette.mint; refresh()
    }
    @objc private func clearEntry() {
        selectedEntry = nil; table.deselectAll(nil); phraseField.stringValue = ""; replacementField.stringValue = ""
        deleteButton.isEnabled = false
    }
    @objc private func deleteEntry() {
        guard let id = selectedEntry else { return }
        store.deleteEntry(id); clearEntry(); refresh()
        dictionaryMessage.stringValue = "Entry deleted from this Mac."; dictionaryMessage.textColor = Palette.muted
    }
    @objc private func insightsChanged() { store.setInsightsEnabled(insightsSwitch.state == .on); refresh() }
    @objc private func resetInsights() { store.resetInsights(); refresh() }
    @objc private func doneClicked() { window?.close() }
    func windowWillClose(_ notification: Notification) { stopCapture() }
    func present() {
        refresh(); showWindow(nil); NSApp.activate(ignoringOtherApps: true); window?.makeKeyAndOrderFront(nil)
    }
    deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
}
