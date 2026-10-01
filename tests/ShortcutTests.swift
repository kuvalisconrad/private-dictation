@main
struct ShortcutTests {
    static func main() {
        var shortcut = ModifierShortcut()
        func flags(_ command: Bool, _ option: Bool, _ other: Bool = false) -> Bool {
            shortcut.flagsChanged(command: command, option: option, other: other)
        }
        // Ordinary typing before the chord must not disarm it.
        shortcut.keyDown()
        precondition(!flags(true, false))
        precondition(!flags(true, true))
        precondition(!flags(true, false))
        precondition(flags(false, false))
        precondition(!flags(false, false))
        // Reverse order and release order work too.
        precondition(!flags(false, true))
        precondition(!flags(true, true))
        precondition(!flags(false, true))
        precondition(flags(false, false))
        // Command–Option–V (and other ordinary shortcuts) never toggles.
        precondition(!flags(true, true))
        shortcut.keyDown()
        precondition(!flags(false, false))
        // Single modifiers and chords including Shift/Control never toggle.
        precondition(!flags(true, false))
        precondition(!flags(false, false))
        precondition(!flags(true, true, true))
        precondition(!flags(true, true))
        precondition(!flags(false, false))
        // Recover cleanly after a rejected chord.
        precondition(!flags(true, true))
        precondition(flags(false, false))
        print("Modifier shortcut checks passed.")
    }
}
