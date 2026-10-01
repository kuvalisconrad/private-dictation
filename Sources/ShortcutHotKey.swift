import AppKit
import Carbon

extension ShortcutModifiers {
    init(_ flags: NSEvent.ModifierFlags) {
        var value: Self = []
        if flags.contains(.command) { value.insert(.command) }
        if flags.contains(.option) { value.insert(.option) }
        if flags.contains(.control) { value.insert(.control) }
        if flags.contains(.shift) { value.insert(.shift) }
        if flags.contains(.function) { value.insert(.function) }
        self = value
    }
    var carbon: UInt32 {
        var value: UInt32 = 0
        if contains(.command) { value |= UInt32(cmdKey) }
        if contains(.option) { value |= UInt32(optionKey) }
        if contains(.control) { value |= UInt32(controlKey) }
        if contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}

final class ShortcutHotKey {
    var onPressed: (() -> Void)?
    var onReleased: (() -> Void)?
    private var handler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var held = false
    private let signature: OSType = 0x50444943 // PDIC

    init() {
        var types = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                     EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event = event, let context = context else { return OSStatus(eventNotHandledErr) }
            let owner = Unmanaged<ShortcutHotKey>.fromOpaque(context).takeUnretainedValue()
            var key = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &key) == noErr,
                  key.signature == owner.signature else { return OSStatus(eventNotHandledErr) }
            if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                let wasHeld = owner.held; owner.held = false
                if wasHeld { owner.onReleased?() }
            }
            else if !owner.held { owner.held = true; owner.onPressed?() }
            return noErr
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ shortcut: DictationShortcut) -> String? {
        unregister()
        guard let key = shortcut.keyCode else { return nil }
        let status = RegisterEventHotKey(UInt32(key), shortcut.modifiers.carbon,
                                        EventHotKeyID(signature: signature, id: 1),
                                        GetApplicationEventTarget(), 0, &hotKey)
        return status == noErr ? nil : "That shortcut is unavailable or already in use. Choose another."
    }
    func unregister() { if let hotKey = hotKey { UnregisterEventHotKey(hotKey) }; hotKey = nil; held = false }
    deinit { unregister(); if let handler = handler { RemoveEventHandler(handler) } }
}
