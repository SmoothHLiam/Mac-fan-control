import Foundation
import FanCore

enum ConfigStore {
    private static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("MacFanControl", isDirectory: true).appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        return config
    }

    static func save(_ config: AppConfig) {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            try enc.encode(config).write(to: url, options: .atomic)
        } catch {
            NSLog("Saving config failed: \(error)")
        }
    }
}
