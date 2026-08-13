import Foundation
import WebAdViewCore

/// Persists the last remote lazy-load config per ad-template host so launches
/// after the first can start with STEP Network's per-domain thresholds before
/// any ad page has loaded (the values themselves only exist inside a loaded
/// page). Refreshed on every successful read-back.
struct RemoteLazyLoadStore {
    var defaults: UserDefaults = .standard

    private func key(forHost host: String) -> String {
        "sn.lazyLoad.\(host)"
    }

    func load(forHost host: String) -> RemoteLazyLoadConfig? {
        guard let data = defaults.data(forKey: key(forHost: host)),
              let config = try? JSONDecoder().decode(RemoteLazyLoadConfig.self, from: data),
              config.isValid else {
            return nil
        }
        return config
    }

    func save(_ config: RemoteLazyLoadConfig, forHost host: String) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        defaults.set(data, forKey: key(forHost: host))
    }
}
