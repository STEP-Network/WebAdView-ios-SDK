import Foundation
import CoreGraphics

/// Per-publisher-domain lazy-load thresholds set remotely by STEP Network.
/// The ad template page exposes them (after the Yield Manager variable runs) as
/// `window.stepnetwork.lazyLoad = { "fetch": 150, "render": 100 }`.
///
/// UNITS: percentage points of the viewport height — 100 = one full viewport,
/// 150 = 1.5 viewports (confirmed by ad-ops 2026-07-23: all STEP lazy loading
/// runs in viewport percentages, never px). Natively that means a distance of
/// `scrollViewBounds.height * value / 100` before viewport entry. The SDK
/// reads the object back from the webview and feeds it into
/// `LazyLoadingManager` via `applyRemote(_:)`.
package struct RemoteLazyLoadConfig: Codable, Equatable {
    /// Viewport-height % before viewport entry at which the ad is requested.
    package var fetch: CGFloat
    /// Viewport-height % before viewport entry at which the fetched ad is
    /// displayed. Always ≤ `fetch` (we request before we display).
    package var render: CGFloat

    package init(fetch: CGFloat, render: CGFloat) {
        self.fetch = fetch
        self.render = render
    }

    /// Decodes the `JSON.stringify` output of the page global. Returns nil on
    /// anything that isn't an object with numeric `fetch`/`render` fields —
    /// the value originates from third-party ad-delivery JavaScript and is
    /// treated as untrusted input.
    package static func parse(jsonString: String) -> RemoteLazyLoadConfig? {
        guard let data = jsonString.data(using: .utf8),
              let config = try? JSONDecoder().decode(RemoteLazyLoadConfig.self, from: data) else {
            debugPrint("[SN] [LLM] Remote lazyLoad config rejected (not a {fetch, render} object): \(jsonString)")
            return nil
        }
        return config
    }

    /// Sanity bounds: both percentages finite and positive, capped at 1000%
    /// (10 viewports), and fetch must not be closer than render (we request
    /// before we display).
    package var isValid: Bool {
        fetch.isFinite && render.isFinite
            && fetch > 0 && render > 0
            && fetch <= 1000 && render <= 1000
            && fetch >= render
    }
}
