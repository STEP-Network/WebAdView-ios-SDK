import Foundation
import QuartzCore
import WebAdViewCore

/// Debug-only performance counters, flushed once per second as a single
/// `[SN] [PERF]` line while the debug flag is on. Counting is a few integer
/// adds per event; nothing is formatted or logged while the flag is off, and
/// the flush timer stops itself after a few idle seconds. Intended for
/// publishers investigating scroll performance (`WebAdViewSdk.setDebugEnabled`).
public enum PerfCounters {
    public enum Key {
        /// Viewability evaluations (ideally one per rendered frame).
        case evaluations
        /// Webview frame changes applied by viewport resizing.
        case webviewResizes
        /// `_onViewability` JavaScript calls into ad pages.
        case jsViewabilitySends
        /// Geometry batches received from an out-of-process host (Flutter).
        case geometryBatchesIn
        /// Viewability updates sent to an out-of-process host (Flutter).
        case hostViewabilityOut
    }

    private static var counts: [Key: Int] = [:]
    private static var webViewsCreated = 0
    private static var webViewCreationMs: Double = 0
    private static var geometryHandlerMicros: Double = 0
    private static var geometryHandlerMaxMicros: Double = 0
    private static var timer: Timer?
    private static var idleTicks = 0

    public static func increment(_ key: Key, by amount: Int = 1) {
        counts[key, default: 0] += amount
        armIfNeeded()
    }

    public static func recordWebViewCreation(milliseconds: Double) {
        webViewsCreated += 1
        webViewCreationMs += milliseconds
        armIfNeeded()
    }

    /// Time spent inside the host's geometry handler (µs), for the batch count.
    public static func recordGeometryHandler(micros: Double) {
        counts[.geometryBatchesIn, default: 0] += 1
        geometryHandlerMicros += micros
        geometryHandlerMaxMicros = max(geometryHandlerMaxMicros, micros)
        armIfNeeded()
    }

    private static func armIfNeeded() {
        guard timer == nil, SNLog.isEnabled else { return }
        idleTicks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in flush() }
    }

    private static func flush() {
        let total = counts.values.reduce(0, +) + webViewsCreated
        guard total > 0 else {
            idleTicks += 1
            if idleTicks >= 5 { timer?.invalidate(); timer = nil }
            return
        }
        idleTicks = 0
        if SNLog.isEnabled {
            let batches = counts[.geometryBatchesIn, default: 0]
            var parts: [String] = []
            parts.append("evaluate/s=\(counts[.evaluations, default: 0])")
            parts.append("resizes/s=\(counts[.webviewResizes, default: 0])")
            parts.append("js/s=\(counts[.jsViewabilitySends, default: 0])")
            if batches > 0 {
                parts.append("geometryIn/s=\(batches) (avg \(Int(geometryHandlerMicros / Double(batches)))µs, max \(Int(geometryHandlerMaxMicros))µs)")
            }
            parts.append("viewabilityOut/s=\(counts[.hostViewabilityOut, default: 0])")
            if webViewsCreated > 0 {
                parts.append("webviewsCreated=\(webViewsCreated) (avg \(Int(webViewCreationMs / Double(webViewsCreated))) ms)")
            }
            debugPrint("[SN] [PERF] " + parts.joined(separator: " "))
        }
        counts.removeAll(keepingCapacity: true)
        webViewsCreated = 0
        webViewCreationMs = 0
        geometryHandlerMicros = 0
        geometryHandlerMaxMicros = 0
    }
}
