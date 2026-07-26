import Foundation

enum APIKey {
    enum Error: Swift.Error {
        case fileNotFound, empty
    }

    static func load() throws -> String {
        let name = Bundle.main.object(forInfoDictionaryKey: "APIKeyFileName") as? String
            ?? (ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
                ? "APIKey_live" : "APIKey_dev")
        return try loadKey(named: name)
    }

    static func loadThunderforestKey() throws -> String {
        let name = ProcessInfo.processInfo.environment["CYCLESTREETS_ENV"] == "live"
            ? "ThunderforestAPIKey_live" : "ThunderforestAPIKey_dev"
        return try loadKey(named: name)
    }

    private static func loadKey(named name: String) throws -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt") else {
            throw Error.fileNotFound
        }
        let key = (try String(contentsOf: url, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Error.empty }
        return key
    }
}
