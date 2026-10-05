import Foundation

@main
struct ModelInstallationTests {
    static func main() throws {
        let files = FileManager.default
        let directory = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: directory) }

        let pinned = try JSONSerialization.jsonObject(with: Data(contentsOf:
            URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
        let names = (pinned["files"] as! [[String: Any]]).map { $0["name"] as! String }
        precondition(!names.contains("tokenizer.json") && names.contains("vocab.json") && names.contains("merges.txt"))
        // Keep the real model's file names, with tiny synthetic fixture sizes.
        let entries = names.enumerated().map { ["name": $0.element, "size": $0.offset + 2] as [String: Any] }
        let manifest = try JSONSerialization.data(withJSONObject: ["files": entries])
        for (index, name) in names.enumerated() {
            try Data(repeating: 0, count: index + 2).write(to: directory.appendingPathComponent(name))
        }
        precondition(ModelInstallation.isComplete(at: directory, manifest: manifest))
        let vocabulary = directory.appendingPathComponent("vocab.json")
        try files.removeItem(at: vocabulary)
        precondition(!ModelInstallation.isComplete(at: directory, manifest: manifest))
        try Data([0]).write(to: vocabulary)
        precondition(!ModelInstallation.isComplete(at: directory, manifest: manifest))
        let unsafe = try JSONSerialization.data(withJSONObject: ["files": [["name": "../outside", "size": 1]]])
        precondition(!ModelInstallation.isComplete(at: directory, manifest: unsafe))
        let duplicate = try JSONSerialization.data(withJSONObject: ["files": [entries[0], entries[0]]])
        precondition(!ModelInstallation.isComplete(at: directory, manifest: duplicate))
        precondition(!ModelInstallation.isComplete(at: directory, manifest: Data("{}".utf8)))
        print("Pinned vocab/merges model recognition, missing/truncated files and unsafe inventory checks passed.")
    }
}
