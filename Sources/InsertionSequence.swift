import Foundation

/// Tracks only the unsent portion in memory. Unicode events use at most twenty
/// UTF-16 units and never split a surrogate pair.
struct UnicodeInsertionSequence {
    private let text: String
    private let units: [UInt16]
    private(set) var consumed = 0
    init(_ text: String) { self.text = text; units = Array(text.utf16) }
    var remainingText: String? {
        consumed < units.count ? (text as NSString).substring(from: consumed) : nil
    }
    func nextChunk() -> [UInt16]? {
        guard consumed < units.count else { return nil }
        var end = min(units.count, consumed + 20)
        if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
        return Array(units[consumed..<end])
    }
    mutating func acknowledgePosted(_ count: Int) {
        precondition(count > 0 && consumed + count <= units.count)
        consumed += count
    }
    mutating func acknowledgeAll() { consumed = units.count }
}

enum InsertionSafety {
    static func secure(subrole: String?, secureEventInput: Bool) -> Bool {
        secureEventInput || subrole == "AXSecureTextField"
    }
    static func textual(role: String?) -> Bool {
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(role ?? "")
    }
}
