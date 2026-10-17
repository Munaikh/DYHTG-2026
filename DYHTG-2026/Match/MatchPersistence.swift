import AlgorithmArenaCore
import Foundation

struct MatchPersistence {
    let url: URL

    static let standard = MatchPersistence(
        url: URL.applicationSupportDirectory.appending(path: "ActiveMatch.json")
    )

    func load() -> ReconnectState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? ContractJSON.decoder().decode(ReconnectState.self, from: data)
    }

    func save(_ state: ReconnectState) {
        guard let data = try? ContractJSON.encoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}
