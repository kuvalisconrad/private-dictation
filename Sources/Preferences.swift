import Foundation

struct ShortcutModifiers: OptionSet, Codable, Equatable {
    let rawValue: UInt
    static let command = Self(rawValue: 1)
    static let option = Self(rawValue: 2)
    static let control = Self(rawValue: 4)
    static let shift = Self(rawValue: 8)
    static let function = Self(rawValue: 16)
    static let supported: Self = [.command, .option, .control, .shift]
    var glyphs: String {
        let labels: [(ShortcutModifiers, String)] = [(.command, "⌘"), (.option, "⌥"), (.control, "⌃"), (.shift, "⇧")]
        return labels.compactMap { contains($0.0) ? $0.1 : nil }.joined(separator: " ")
    }
}

struct DictationShortcut: Codable, Equatable {
    var modifiers: ShortcutModifiers
    var keyCode: UInt16?
    var keyName: String?
    static let defaultShortcut = Self(modifiers: [.command, .option], keyCode: nil, keyName: nil)
    var display: String { modifiers.glyphs + (keyCode != nil ? " " + (keyName ?? "Key \(keyCode!)") : "") }
    var validationError: String? {
        guard modifiers.subtracting(.supported).isEmpty else { return "Function keys as modifiers are not supported." }
        if keyCode == nil {
            return modifiers.rawValue.nonzeroBitCount >= 2 ? nil : "Use at least two modifiers for a modifier-only shortcut."
        }
        guard !modifiers.intersection([.command, .option, .control]).isEmpty else {
            return "Include Command, Option, or Control with the key."
        }
        if [53, 48].contains(Int(keyCode!)) { return "Escape and Tab are reserved. Choose another key." }
        if modifiers == .command, [0, 6, 7, 8, 9, 12, 13, 31, 35, 45, 46, 1].contains(Int(keyCode!)) {
            return "Choose a shortcut other than a standard Command editing or app command."
        }
        return nil
    }
}

/// Matches modifier-only chords after full release and rejects intervening keys.
struct ShortcutMatcher {
    let definition: DictationShortcut
    private var candidate = false
    private var blocked = false
    private var engaged = false

    init(_ definition: DictationShortcut) { self.definition = definition }
    mutating func keyDown() {
        if engaged { blocked = true; candidate = false }
    }
    mutating func flagsChanged(_ modifiers: ShortcutModifiers) -> Bool {
        guard definition.keyCode == nil else { return false }
        engaged = !modifiers.isEmpty
        if !modifiers.subtracting(definition.modifiers).isEmpty { blocked = true; candidate = false }
        if modifiers == definition.modifiers && !blocked { candidate = true }
        if modifiers.isEmpty {
            let fire = candidate && !blocked
            candidate = false; blocked = false
            return fire
        }
        return false
    }
}

struct CorrectionEntry: Codable, Equatable {
    var id = UUID()
    var phrase: String
    var replacement: String
}

struct CorrectionRules {
    private let entries: [CorrectionEntry]
    private let regex: NSRegularExpression?
    init(_ entries: [CorrectionEntry]) {
        self.entries = entries.sorted {
            if $0.phrase.count == $1.phrase.count { return $0.id.uuidString < $1.id.uuidString }
            return $0.phrase.count > $1.phrase.count
        }
        let alternatives = self.entries.enumerated().map { index, entry in
            let literal = entry.phrase.split(whereSeparator: { $0.isWhitespace })
                .map { NSRegularExpression.escapedPattern(for: String($0)) }.joined(separator: "\\s+")
            return "(?<e\(index)>\(literal))"
        }
        let boundary = "[\\p{L}\\p{M}\\p{N}_'’]"
        regex = alternatives.isEmpty ? nil : try? NSRegularExpression(
            pattern: "(?<!\(boundary))(?:" + alternatives.joined(separator: "|") + ")(?!\(boundary))",
            options: [.caseInsensitive])
    }

    func apply(to text: String) -> String {
        guard let regex = regex else { return text }
        let string = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length)).reversed() {
            for (index, entry) in entries.enumerated() where match.range(withName: "e\(index)").location != NSNotFound {
                string.replaceCharacters(in: match.range, with: entry.replacement); break
            }
        }
        return string as String
    }
}

struct AggregateInsights: Codable {
    var dictations = 0
    var words = 0
    var audioSeconds = 0.0
    var processingSeconds = 0.0
}

final class PreferencesStore {
    private let defaults: UserDefaults
    private(set) var shortcut: DictationShortcut
    private(set) var dictionary: [CorrectionEntry]
    private(set) var insightsEnabled: Bool
    private(set) var insights: AggregateInsights
    private(set) var rules: CorrectionRules

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        shortcut = defaults.data(forKey: "PrivateDictationShortcut")
            .flatMap { try? JSONDecoder().decode(DictationShortcut.self, from: $0) }
            .flatMap { $0.validationError == nil ? $0 : nil } ?? .defaultShortcut
        dictionary = defaults.data(forKey: "PrivateDictationDictionary")
            .flatMap { try? JSONDecoder().decode([CorrectionEntry].self, from: $0) } ?? []
        dictionary = Array(dictionary.filter { !$0.phrase.isEmpty && !$0.replacement.isEmpty }.prefix(200))
        rules = CorrectionRules(dictionary)
        insightsEnabled = defaults.bool(forKey: "PrivateDictationInsightsEnabled")
        insights = insightsEnabled ? defaults.data(forKey: "PrivateDictationAggregateInsights")
            .flatMap { try? JSONDecoder().decode(AggregateInsights.self, from: $0) } ?? AggregateInsights() : AggregateInsights()
    }

    func setShortcut(_ shortcut: DictationShortcut) {
        guard shortcut.validationError == nil else { return }
        self.shortcut = shortcut
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: "PrivateDictationShortcut")
    }

    func saveEntry(id: UUID?, phrase: String, replacement: String) -> String? {
        let phrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = replacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !phrase.isEmpty, !replacement.isEmpty else { return "Enter both the heard phrase and the spelling you want." }
        guard phrase.count <= 200, replacement.count <= 500 else { return "Keep the phrase under 200 characters and replacement under 500." }
        guard !phrase.contains("\n"), !replacement.contains("\n") else { return "Use one line per dictionary entry." }
        let key = phrase.lowercased(with: Locale(identifier: "en_US_POSIX"))
        guard !dictionary.contains(where: { $0.id != id && $0.phrase.lowercased(with: Locale(identifier: "en_US_POSIX")) == key }) else {
            return "That phrase already has an entry. Select it to edit."
        }
        if let id = id, let index = dictionary.firstIndex(where: { $0.id == id }) {
            dictionary[index] = CorrectionEntry(id: id, phrase: phrase, replacement: replacement)
        } else {
            guard dictionary.count < 200 else { return "The dictionary supports up to 200 entries." }
            dictionary.append(CorrectionEntry(phrase: phrase, replacement: replacement))
        }
        persistDictionary(); return nil
    }

    func deleteEntry(_ id: UUID) { dictionary.removeAll { $0.id == id }; persistDictionary() }
    private func persistDictionary() {
        rules = CorrectionRules(dictionary)
        defaults.set(try? JSONEncoder().encode(dictionary), forKey: "PrivateDictationDictionary")
    }
    var vocabularyContext: String {
        String(dictionary.map(\.replacement).joined(separator: ", ").prefix(1900))
    }

    func setInsightsEnabled(_ enabled: Bool) {
        insightsEnabled = enabled; defaults.set(enabled, forKey: "PrivateDictationInsightsEnabled")
        if !enabled { resetInsights() }
    }
    func resetInsights() {
        insights = AggregateInsights(); defaults.removeObject(forKey: "PrivateDictationAggregateInsights")
    }
    func recordInsertion(words: Int, audioSeconds: Double, processingSeconds: Double) {
        guard insightsEnabled else { return }
        insights.dictations += 1; insights.words += max(0, words)
        insights.audioSeconds += max(0, audioSeconds.isFinite ? audioSeconds : 0)
        insights.processingSeconds += max(0, processingSeconds.isFinite ? processingSeconds : 0)
        defaults.set(try? JSONEncoder().encode(insights), forKey: "PrivateDictationAggregateInsights")
    }
}
