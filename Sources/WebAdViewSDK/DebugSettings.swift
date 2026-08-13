import Foundation
import Combine
import SwiftUI

/// Global, persistent debug flag for the SDK. Gates all SDK logging, the
/// in-webview debug panel, and the Yield Manager debug query param.
public class DebugSettings: ObservableObject {
    /// The SDK-wide instance. Views read it via the `\.snDebugSettings`
    /// environment key, which defaults to this — consumers don't have to
    /// inject anything.
    public static let shared = DebugSettings()

    @Published public var isDebugEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isDebugEnabled, forKey: "isDebugEnabled")
        }
    }

    public init() {
        self.isDebugEnabled = UserDefaults.standard.bool(forKey: "isDebugEnabled")
    }
}

struct SNDebugSettingsKey: EnvironmentKey {
    static let defaultValue: DebugSettings = .shared
}

public extension EnvironmentValues {
    /// The debug settings used by WebAdViews. Defaults to `DebugSettings.shared`;
    /// override only if your app needs an isolated instance.
    var snDebugSettings: DebugSettings {
        get { self[SNDebugSettingsKey.self] }
        set { self[SNDebugSettingsKey.self] = newValue }
    }
}
