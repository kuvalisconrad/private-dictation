import Foundation

enum ModelInstallation {
    private struct Manifest: Decodable {
        struct File: Decodable {
            let name: String
            let size: Int64
        }
        let files: [File]
    }

    // Downloading verifies SHA-256. This cheap readiness check uses the actual
    // pinned file inventory, including tokenizers distributed as vocab/merges.
    static func isComplete(at directory: URL, manifest: Data) -> Bool {
        guard let inventory = try? JSONDecoder().decode(Manifest.self, from: manifest),
              !inventory.files.isEmpty,
              Set(inventory.files.map(\.name)).count == inventory.files.count else { return false }
        return inventory.files.allSatisfy { file in
            guard !file.name.isEmpty, file.name != ".", file.name != "..",
                  !file.name.contains("/"), !file.name.contains("\\"), file.size > 0,
                  let attributes = try? FileManager.default.attributesOfItem(
                    atPath: directory.appendingPathComponent(file.name).path),
                  attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = attributes[.size] as? NSNumber else { return false }
            return size.int64Value == file.size
        }
    }
}
