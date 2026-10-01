import Foundation

@main
struct PreferencesTests {
    static func main() {
        let suite = "PrivateDictationTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PreferencesStore(defaults: defaults)
        precondition(store.shortcut == .defaultShortcut && !store.insightsEnabled)
        var chord = ShortcutMatcher(.defaultShortcut)
        precondition(!chord.flagsChanged(.command))
        precondition(!chord.flagsChanged([.command, .option]))
        precondition(!chord.flagsChanged(.option))
        precondition(chord.flagsChanged([]))
        precondition(!chord.flagsChanged([]))
        precondition(!chord.flagsChanged([.command, .option]))
        chord.keyDown()
        precondition(!chord.flagsChanged([]))
        var custom = ShortcutMatcher(DictationShortcut(modifiers: [.control, .shift], keyCode: nil, keyName: nil))
        precondition(!custom.flagsChanged(.control))
        precondition(!custom.flagsChanged([.control, .shift]))
        precondition(custom.flagsChanged([]))
        precondition(!custom.flagsChanged([.control, .shift, .option]))
        precondition(!custom.flagsChanged([.control, .shift]))
        precondition(!custom.flagsChanged([]))
        precondition(DictationShortcut(modifiers: .command, keyCode: nil, keyName: nil).validationError != nil)
        precondition(DictationShortcut(modifiers: [], keyCode: 2, keyName: "D").validationError != nil)
        precondition(DictationShortcut(modifiers: .command, keyCode: 8, keyName: "C").validationError != nil)
        let keyed = DictationShortcut(modifiers: [.control, .option], keyCode: 2, keyName: "D")
        precondition(keyed.validationError == nil)
        store.setShortcut(keyed)
        precondition(PreferencesStore(defaults: defaults).shortcut == keyed)

        precondition(store.saveEntry(id: nil, phrase: "acme", replacement: "ACME") == nil)
        precondition(store.saveEntry(id: nil, phrase: "acme corp", replacement: "AcmeCorp") == nil)
        precondition(store.saveEntry(id: nil, phrase: "c++", replacement: "C++") == nil)
        precondition(store.saveEntry(id: nil, phrase: "cash", replacement: "$1\\literal") == nil)
        precondition(store.saveEntry(id: nil, phrase: "ACME", replacement: "duplicate") != nil)
        precondition(store.rules.apply(to: "ACME corp, acme! Macme acme's cash c++.") == "AcmeCorp, ACME! Macme acme's $1\\literal C++.")
        precondition(store.rules.apply(to: "acme   corp") == "AcmeCorp")
        let acmeID = store.dictionary.first(where: { $0.phrase == "acme" })!.id
        precondition(store.saveEntry(id: acmeID, phrase: "acme", replacement: "cash") == nil)
        // Apply once to the original transcript. Replacements are not processed again.
        precondition(store.rules.apply(to: "acme cash") == "cash $1\\literal")
        precondition(PreferencesStore(defaults: defaults).dictionary == store.dictionary)
        store.deleteEntry(acmeID)
        precondition(store.rules.apply(to: "acme") == "acme")

        store.recordInsertion(words: 10, audioSeconds: 3, processingSeconds: 1)
        precondition(defaults.data(forKey: "PrivateDictationAggregateInsights") == nil)
        store.setInsightsEnabled(true)
        store.recordInsertion(words: 10, audioSeconds: 3, processingSeconds: 1)
        precondition(store.insights.dictations == 1 && store.insights.words == 10)
        let numbers = try! JSONSerialization.jsonObject(with: defaults.data(forKey: "PrivateDictationAggregateInsights")!) as! [String: Any]
        precondition(Set(numbers.keys) == Set(["dictations", "words", "audioSeconds", "processingSeconds"]))
        precondition(PreferencesStore(defaults: defaults).insights.words == 10)
        store.setInsightsEnabled(false)
        precondition(defaults.data(forKey: "PrivateDictationAggregateInsights") == nil && store.insights.words == 0)
        print("Shortcut persistence, dictionary boundaries/literal replacements, and opt-in aggregate privacy checks passed.")
    }
}
