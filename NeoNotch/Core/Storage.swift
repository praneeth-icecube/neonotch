import Foundation

/// Small JSON files in `~/Library/Application Support/NeoNotch`, for the
/// things that outgrow `UserDefaults`: notes, bookmarks, focus history and the
/// clipboard. Writes are atomic, so a crash mid-save never leaves half a file.
enum Storage {
    /// Self-tests point this at a throwaway folder before any model loads,
    /// so a test can never overwrite your notes or bookmarks.
    static var overrideDirectory: URL?

    static var directory: URL { overrideDirectory ?? standardDirectory }

    private static let standardDirectory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NeoNotch", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func load<Value: Decodable>(_ type: Value.Type, from name: String) -> Value? {
        guard let data = try? Data(contentsOf: url(for: name)) else { return nil }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            Trace.log("storage", "could not read \(name): \(error)")
            return nil
        }
    }

    static func save<Value: Encodable>(_ value: Value, to name: String) {
        do {
            let data = try encoder.encode(value)
            try data.write(to: url(for: name), options: .atomic)
        } catch {
            Trace.log("storage", "could not write \(name): \(error)")
        }
    }

    /// A subfolder, created on first use.
    static func folder(_ name: String) -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
