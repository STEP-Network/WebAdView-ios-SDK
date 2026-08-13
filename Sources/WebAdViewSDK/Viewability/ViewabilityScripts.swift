import Foundation
import WebAdViewCore

// MARK: - ViewabilityPayload
/// The JSON message pushed into the webview on viewability changes.
/// Built with JSONEncoder — never string interpolation — so ad unit ids or
/// future string fields can never break out of the JS call.
struct ViewabilityPayload: Codable {
    var type: String = "viewability"
    let adUnitId: String
    /// Fraction of the ad's pixels on screen, rounded to 2 decimals (0.0-1.0).
    let ratio: Double
    let visible: Bool
    let dwellMs: Int
    let thresholdMs: Int
    let mode: String
    let viewable: Bool
    let appActive: Bool
    /// Wall-clock milliseconds since epoch (Date.now()-compatible).
    let ts: Double

    init(update: ViewabilityUpdate) {
        adUnitId = update.adUnitId
        ratio = (Double(update.ratio) * 100).rounded() / 100
        visible = update.isVisible
        dwellMs = Int(update.dwell * 1000)
        thresholdMs = Int(update.mode.requiredDuration * 1000)
        mode = update.mode.rawValue
        viewable = update.isViewable
        appActive = update.isAppActive
        ts = Date().timeIntervalSince1970 * 1000
    }

    func jsonString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - ViewabilityScripts
/// JS injected into every ad webview so the page can consume the NATIVE
/// viewability signal instead of self-reporting against its own DOM viewport
/// (which is always 100% — each ad fills its own webview).
///
/// Page-side API:
///   window.stepnetwork.viewability          — latest snapshot (pull)
///   window.stepnetwork.onViewability(cb)    — subscribe (push)
///   window 'snviewability' CustomEvent      — event-based (detail = snapshot)
///
/// Note: GPT ActiveView inside the webview still self-measures its own DOM
/// viewport; this bridge is the authoritative signal for STEP Network's own
/// measurement. Deliberately no global IntersectionObserver patch — undefined
/// interactions with GPT internals.
enum ViewabilityScripts {
    static let bridgeShim = """
    window.stepnetwork = window.stepnetwork || {};
    (function () {
        if (window.stepnetwork._onViewability) { return; }
        var listeners = [];
        window.stepnetwork.viewability = {
            ratio: 0, visible: false, viewable: false,
            dwellMs: 0, thresholdMs: 0, mode: 'display', appActive: true
        };
        window.stepnetwork.onViewability = function (cb) {
            if (typeof cb === 'function') { listeners.push(cb); }
        };
        window.stepnetwork._onViewability = function (p) {
            window.stepnetwork.viewability = p;
            try {
                window.dispatchEvent(new CustomEvent('snviewability', { detail: p }));
            } catch (e) {}
            for (var i = 0; i < listeners.length; i++) {
                try { listeners[i](p); } catch (e) {}
            }
        };
    })();
    """
}
