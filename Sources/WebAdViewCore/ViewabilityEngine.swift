import Foundation
import CoreGraphics

// MARK: - ViewabilityMode
/// IAB/MRC viewability thresholds.
/// An ad counts as viewable when >= 50% of its pixels are on screen for a
/// continuous minimum duration: 1s for display ads, 2s for video ads.
/// The IAB/MRC threshold profile an impression is measured against.
/// Every ad the SDK measures today uses `.display` (≥50% for 1s). `.video`
/// (≥50% for 2s) is RESERVED: the engine supports it, but no public API
/// selects it — creative type is decided remotely at serve time, and
/// Google's ActiveView applies the correct per-creative standard in-page.
/// Consumers only ever observe this via `ViewabilityUpdate.mode`.
public enum ViewabilityMode: String, CaseIterable {
    case display
    case video

    /// Fraction of the ad's pixels that must be within the viewport (IAB/MRC: 50%).
    public var requiredRatio: CGFloat { 0.5 }

    /// Continuous time-in-view required for a viewable impression.
    public var requiredDuration: TimeInterval { self == .video ? 2.0 : 1.0 }
}

// MARK: - ViewabilityUpdate
/// Snapshot of an ad's viewability state, produced on every measurement pass.
public struct ViewabilityUpdate: Equatable {
    public let adUnitId: String
    /// Fraction of the ad's pixels currently within the viewport (0.0-1.0).
    public let ratio: CGFloat
    /// True when ratio >= the mode's required ratio AND the app is active.
    public let isVisible: Bool
    /// Continuous time-in-view (seconds). Resets when visibility is lost.
    public let dwell: TimeInterval
    public let mode: ViewabilityMode
    /// Latched verdict: once a viewable impression is counted it stays true
    /// until `reset()` (new impression).
    public let isViewable: Bool
    /// True on exactly one update: the sample that latched the verdict.
    public let becameViewable: Bool
    public let isAppActive: Bool
    public let timestamp: TimeInterval
}

// MARK: - ViewabilityEngine
/// Pure per-ad viewability state machine (IAB/MRC rules).
///
/// Deliberately free of WebKit/SwiftUI/UIKit/Combine so it is unit-testable
/// with synthetic timestamps and survives extraction into an SPM core target.
/// The caller supplies all inputs — geometry, app-active flag, and the clock —
/// via `ingest(adFrame:viewport:isAppActive:at:)`.
public final class ViewabilityEngine {

    /// Verdict state machine:
    /// idle -> counting     when ratio >= 50% and the app is active
    /// counting -> idle     on any dip below 50% or app backgrounding (continuous timer RESETS)
    /// counting -> viewable when continuous dwell >= the mode's duration (latched)
    /// viewable -> idle     only via reset() (new impression)
    public enum State: Equatable {
        case idle
        case counting(since: TimeInterval)
        case viewable
    }

    public let adUnitId: String
    public let mode: ViewabilityMode
    public private(set) var state: State = .idle

    /// Start of the current continuous in-view period. Kept even after the
    /// verdict latches so post-latch updates can still report a live dwell.
    private var countingSince: TimeInterval?

    public init(adUnitId: String, mode: ViewabilityMode) {
        self.adUnitId = adUnitId
        self.mode = mode
    }

    /// The engine's only input. Feed it a measurement sample; it returns the
    /// resulting viewability snapshot.
    @discardableResult
    public func ingest(adFrame: CGRect, viewport: CGRect, isAppActive: Bool, at time: TimeInterval) -> ViewabilityUpdate {
        let ratio = Self.intersectionRatio(of: adFrame, in: viewport)
        let isVisible = isAppActive && ratio >= mode.requiredRatio
        var becameViewable = false

        switch state {
        case .idle:
            if isVisible {
                state = .counting(since: time)
                countingSince = time
            }
        case .counting(let since):
            if !isVisible {
                // Continuity requirement: any dip below 50% (or backgrounding)
                // resets the timer entirely.
                state = .idle
                countingSince = nil
            } else if time - since >= mode.requiredDuration {
                state = .viewable
                becameViewable = true
            }
        case .viewable:
            // Verdict is latched; keep countingSince in sync purely for
            // accurate post-latch dwell reporting.
            if isVisible {
                if countingSince == nil { countingSince = time }
            } else {
                countingSince = nil
            }
        }

        let dwell: TimeInterval
        switch state {
        case .idle:
            dwell = 0
        case .counting(let since):
            dwell = time - since
        case .viewable:
            dwell = countingSince.map { time - $0 } ?? 0
        }

        return ViewabilityUpdate(
            adUnitId: adUnitId,
            ratio: ratio,
            isVisible: isVisible,
            dwell: dwell,
            mode: mode,
            isViewable: state == .viewable,
            becameViewable: becameViewable,
            isAppActive: isAppActive,
            timestamp: time
        )
    }

    /// Re-arms the engine for a new impression (e.g. the webview was recreated).
    public func reset() {
        state = .idle
        countingSince = nil
    }

    /// Fraction of `adFrame`'s area that lies within `viewport` (0.0-1.0).
    /// Safe for zero-area frames and null/empty viewports.
    public static func intersectionRatio(of adFrame: CGRect, in viewport: CGRect) -> CGFloat {
        let ad = adFrame.standardized
        let vp = viewport.standardized
        let adArea = ad.width * ad.height
        guard adArea > 0, !vp.isNull, !vp.isEmpty else { return 0 }
        let intersection = ad.intersection(vp)
        guard !intersection.isNull else { return 0 }
        let ratio = (intersection.width * intersection.height) / adArea
        return min(max(ratio, 0), 1)
    }
}
