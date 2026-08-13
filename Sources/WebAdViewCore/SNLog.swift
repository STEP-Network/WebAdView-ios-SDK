import Foundation

/// SDK-wide debug logger. Gated on the same persistent UserDefaults flag the
/// ladybug toggle writes ("isDebugEnabled"), so output can be enabled at
/// runtime without a rebuild.
public enum SNLog {
    public static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: "isDebugEnabled")
    }

    public static func log(_ items: Any..., separator: String = " ", terminator: String = "\n") {
        guard isEnabled else { return }
        print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
    }
}

/// Module-internal shim so existing `debugPrint(...)` call sites keep working
/// unchanged. (Each module defines one; they all funnel into SNLog.)
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    guard SNLog.isEnabled else { return }
    print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
}
