import Foundation

private final class FakeOutputs: AudioOutputAccess {
    var routes: [AudioOutputControl]?
    var values: [AudioOutputControl: Float32] = [:]
    var failedWrite: AudioOutputControl?
    func controls() -> [AudioOutputControl]? { routes }
    func read(_ control: AudioOutputControl) -> Float32? { values[control] }
    func write(_ value: Float32, to control: AudioOutputControl) -> Bool {
        guard control != failedWrite else { return false }
        values[control] = value; return true
    }
}

@main struct OutputMuteTests {
    static func main() {
        let headphones = AudioOutputControl(device: 1, element: 0, kind: .mute)
        let speakers = AudioOutputControl(device: 2, element: 0, kind: .mute)
        let left = AudioOutputControl(device: 3, element: 1, kind: .volume)
        let right = AudioOutputControl(device: 3, element: 2, kind: .volume)
        let audio = FakeOutputs()
        audio.routes = [headphones]; audio.values[headphones] = 0
        let session = OutputMuteSession(access: audio)
        precondition(session.reassert() && audio.values[headphones] == 1)
        // A profile reset must be silenced again without replacing the snapshot.
        audio.values[headphones] = 0
        precondition(session.reassert() && audio.values[headphones] == 1)
        // Routing switches retain each output's own prior state.
        audio.routes = [speakers]; audio.values[speakers] = 1
        precondition(session.reassert())
        precondition(session.restore())
        precondition(audio.values[headphones] == 0 && audio.values[speakers] == 1)

        audio.routes = [left, right]; audio.values[left] = 0.25; audio.values[right] = 0.75
        precondition(session.reassert() && audio.values[left] == 0 && audio.values[right] == 0)
        precondition(session.reassert()) // repeated checks don't replace originals
        precondition(session.restore())
        precondition(audio.values[left] == 0.25 && audio.values[right] == 0.75)

        // A later manual adjustment is not overwritten during restoration.
        precondition(session.reassert())
        audio.values[right] = 0.5
        precondition(session.restore() && audio.values[right] == 0.5 && audio.values[left] == 0.25)

        // Partial failures still unwind the controls already muted.
        audio.failedWrite = right
        precondition(!session.reassert() && audio.values[left] == 0)
        precondition(session.restore() && audio.values[left] == 0.25 && audio.values[right] == 0.5)
        audio.routes = nil
        precondition(!session.reassert())
        precondition(session.restore())
        print("Output mute: routing/profile changes, previous mute, volume fallback and failure restoration passed.")
    }
}
