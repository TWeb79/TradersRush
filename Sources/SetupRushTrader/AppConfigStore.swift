import Foundation

// Settings-only snapshot — excludes runtime/session data (candles, positions, orders,
// budget, connection status). Field names mirror the @State vars they back in ContentView.
struct AppConfig: Codable, Equatable {
    var mcpConfig: MCPConfig = MCPConfig()
    var mcpEnabled: Bool = false

    var showFootprint: Bool = false
    var footprintMode: FootprintDisplayMode = .bidAsk
    var extendedView: Bool = false

    var confirmationEnabled: Bool = true
    var swipeTradeEnabled: Bool = false

    var ticketQty: Int = 1
    var bracket: BracketSettings = BracketSettings()
}

enum AppConfigStore {
    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return dir.appendingPathComponent("TradersRush", isDirectory: true).appendingPathComponent("config.json")
    }

    // nil on first launch or any read/decode failure — caller falls back to defaults.
    static func load() -> AppConfig? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    // ⚠️ authToken is written to this file in plaintext. Per the project spec's own SEC-02,
    // real credentials belong in Keychain only — this is a local prototype/dev convenience
    // (explicitly requested), not a production-safe path for real server credentials.
    static func save(_ config: AppConfig) {
        guard let url = fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(config)
            try data.write(to: url, options: .atomic)
        } catch {
            print("AppConfigStore.save failed: \(error)")
        }
    }
}
