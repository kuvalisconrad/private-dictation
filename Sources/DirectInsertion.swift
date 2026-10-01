import AppKit
import ApplicationServices
import Carbon

/// Inserts through Accessibility or Unicode key events. It never accesses the
/// pasteboard, reads document text, or types into a secure/noneditable field.
final class DirectTextInsertion {
    private(set) var isInserting = false
    private var generation = UUID()
    private var completion: ((String?, String?) -> Void)?
    private var sequence = UnicodeInsertionSequence("")

    static func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }
    static func isSecure(_ element: AXUIElement?) -> Bool {
        InsertionSafety.secure(subrole: element.flatMap { stringAttribute($0, kAXSubroleAttribute as CFString) },
                               secureEventInput: IsSecureEventInputEnabled())
    }
    static func isTextField(_ element: AXUIElement?) -> Bool {
        guard let element = element else { return false }
        return InsertionSafety.textual(role: stringAttribute(element, kAXRoleAttribute as CFString))
    }
    static func focusedElement() -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private func stillFocused(_ element: AXUIElement, pid: pid_t) -> Bool {
        NSWorkspace.shared.frontmostApplication?.processIdentifier == pid &&
            Self.focusedElement().map { CFEqual($0, element) } == true &&
            !Self.isSecure(element) &&
            NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
    }

    func insert(_ text: String, element: AXUIElement, pid: pid_t, preferAccessibility: Bool = true,
                completion: @escaping (String?, String?) -> Void) {
        guard !isInserting else { completion(text, "Insertion is already in progress."); return }
        guard AXIsProcessTrusted(), stillFocused(element, pid: pid) else {
            completion(text, "Click a nonsecure text field, then use the shortcut again."); return
        }
        isInserting = true; sequence = UnicodeInsertionSequence(text); self.completion = completion
        generation = UUID()
        guard Self.isTextField(element) else {
            finish("This field does not support direct insertion. Choose another text field, or discard."); return
        }
        var enabled: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXEnabledAttribute as CFString, &enabled) == .success,
           (enabled as? Bool) == false {
            finish("This text field is disabled. Choose another field, or discard."); return
        }
        var editable: CFTypeRef?, valueSettable: DarwinBoolean = false
        let explicitEditable = AXUIElementCopyAttributeValue(element, "AXEditable" as CFString, &editable) == .success ? editable as? Bool : nil
        guard explicitEditable != false else {
            finish("This field is read-only. Choose another text field, or discard."); return
        }
        var selectedTextSettable: DarwinBoolean = false
        if preferAccessibility, AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &selectedTextSettable) == .success,
           selectedTextSettable.boolValue,
           AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
            sequence.acknowledgeAll(); finish(nil); return
        }
        let valueCanChange = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable) == .success && valueSettable.boolValue
        guard explicitEditable == true || valueCanChange else {
            finish("This field does not expose editable access. Choose another text field, or discard."); return
        }
        let token = generation
        func sendNext() {
            guard self.generation == token, self.isInserting else { return }
            guard self.stillFocused(element, pid: pid) else {
                self.finish("Insertion paused because focus changed. Click the destination and use the shortcut for the remaining text."); return
            }
            guard let chunk = self.sequence.nextChunk() else { self.finish(nil); return }
            guard let source = CGEventSource(stateID: .privateState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                self.finish("Direct typing could not start. Try again or discard."); return
            }
            chunk.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress!)
            }
            down.flags = []; up.flags = []
            down.postToPid(pid); up.postToPid(pid)
            self.sequence.acknowledgePosted(chunk.count)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.012) { sendNext() }
        }
        sendNext()
    }

    func cancel() { guard isInserting else { return }; finish("Insertion discarded. Some text may already be in the destination.") }
    private func finish(_ error: String?) {
        generation = UUID(); isInserting = false
        let remaining = sequence.remainingText
        let callback = completion; completion = nil; sequence = UnicodeInsertionSequence("")
        callback?(error == nil ? nil : remaining, error)
    }
}
