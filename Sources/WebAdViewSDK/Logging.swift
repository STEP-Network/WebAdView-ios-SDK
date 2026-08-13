import Foundation
import WebAdViewCore

/// Module-internal shim so `debugPrint(...)` call sites in this module keep
/// working unchanged and funnel into SNLog (shadowing Swift's stdlib
/// debugPrint, which would otherwise print unconditionally).
func debugPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    guard SNLog.isEnabled else { return }
    print(items.map { "\($0)" }.joined(separator: separator), terminator: terminator)
}
