import Foundation

@main
struct InsertionSafetyTests {
    static func main() {
        precondition(InsertionSafety.secure(subrole: "AXSecureTextField", secureEventInput: false))
        precondition(InsertionSafety.secure(subrole: nil, secureEventInput: true))
        precondition(!InsertionSafety.secure(subrole: nil, secureEventInput: false))
        precondition(InsertionSafety.textual(role: "AXTextArea"))
        precondition(!InsertionSafety.textual(role: "AXButton"))
        precondition(!InsertionSafety.textual(role: nil))

        let text = "abcdefghijklmnopqrs🦊 café £5."
        var sequence = UnicodeInsertionSequence(text)
        let first = sequence.nextChunk()!
        precondition(first.count == 19) // Do not split the emoji's surrogate pair.
        precondition(sequence.remainingText == text) // Not acknowledged, so nothing lost.
        sequence.acknowledgePosted(first.count)
        precondition(sequence.remainingText == "🦊 café £5.")
        let remaining = sequence.nextChunk()!
        precondition(String(decoding: remaining, as: UTF16.self) == "🦊 café £5.")
        sequence.acknowledgePosted(remaining.count)
        precondition(sequence.remainingText == nil && sequence.nextChunk() == nil)

        var cancelled = UnicodeInsertionSequence("Never put this synthetic sentence on the clipboard.")
        cancelled.acknowledgePosted(cancelled.nextChunk()!.count)
        precondition(cancelled.remainingText == "etic sentence on the clipboard.")
        var all = UnicodeInsertionSequence("café 🦊")
        all.acknowledgeAll()
        precondition(all.remainingText == nil)
        print("Secure/nontext target rejection and Unicode-safe remaining-text checks passed.")
    }
}
