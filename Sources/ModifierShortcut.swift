// Fire once when a modifier-only Command–Option chord is fully released.
// Ordinary shortcuts such as Command–Option–V must never start recording.
struct ModifierShortcut {
    private var candidate = false
    private var blocked = false
    private var engaged = false

    mutating func keyDown() {
        if engaged { blocked = true; candidate = false }
    }

    mutating func flagsChanged(command: Bool, option: Bool, other: Bool) -> Bool {
        engaged = command || option
        if other { blocked = true; candidate = false }
        if command && option && !blocked { candidate = true }
        if !command && !option {
            let fire = candidate && !blocked && !other
            candidate = false
            blocked = false
            return fire
        }
        return false
    }
}
