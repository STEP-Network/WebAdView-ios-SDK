import Foundation
import CoreGraphics

/// Computes the visible slice of an ad for the Module-6 "viewport resizing"
/// approach: the WKWebView is resized to exactly this slice so ad networks
/// (GPT ActiveView) measure viewability against the true visible viewport
/// instead of a webview the creative always fills.
public enum ViewportClipCalculator {

    /// The geometry a webview needs to display only the visible part of an ad
    /// without the creative appearing to move.
    public struct Clip: Equatable {
        /// The visible slice in AD-LOCAL coordinates. Doubles as the webview's
        /// frame within its (full-size, layout-stable) container.
        public let sliceFrame: CGRect
        /// Page scroll offset so the creative pixels belonging to the slice
        /// are the ones shown (equals sliceFrame.origin).
        public var contentOffset: CGPoint { sliceFrame.origin }
        /// True when the ad is fully within the viewport (no clipping needed).
        public let isFullyVisible: Bool
        /// True when nothing of the ad is visible.
        public let isFullyHidden: Bool

        public init(sliceFrame: CGRect, isFullyVisible: Bool, isFullyHidden: Bool) {
            self.sliceFrame = sliceFrame
            self.isFullyVisible = isFullyVisible
            self.isFullyHidden = isFullyHidden
        }
    }

    /// - Parameters:
    ///   - adFrame: the ad creative's frame in global coordinates.
    ///   - viewport: the effective viewport in the same coordinate space.
    /// - Returns: the clip in ad-local coordinates.
    public static func clip(adFrame: CGRect, viewport: CGRect) -> Clip {
        let ad = adFrame.standardized
        let vp = viewport.standardized

        guard ad.width > 0, ad.height > 0, !vp.isNull, !vp.isEmpty else {
            return Clip(sliceFrame: .zero, isFullyVisible: false, isFullyHidden: true)
        }

        let intersection = ad.intersection(vp)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return Clip(sliceFrame: .zero, isFullyVisible: false, isFullyHidden: true)
        }

        // Convert to ad-local coordinates.
        let slice = CGRect(
            x: intersection.minX - ad.minX,
            y: intersection.minY - ad.minY,
            width: intersection.width,
            height: intersection.height
        )
        let fullyVisible = slice == CGRect(origin: .zero, size: ad.size)
        return Clip(sliceFrame: slice, isFullyVisible: fullyVisible, isFullyHidden: false)
    }

    /// Whether two clips differ enough to be worth applying (avoids churning
    /// the webview frame on sub-point geometry noise).
    public static func differsSignificantly(_ a: Clip, _ b: Clip, tolerance: CGFloat = 2.0) -> Bool {
        if a.isFullyVisible != b.isFullyVisible || a.isFullyHidden != b.isFullyHidden { return true }
        let ra = a.sliceFrame, rb = b.sliceFrame
        return abs(ra.minX - rb.minX) > tolerance
            || abs(ra.minY - rb.minY) > tolerance
            || abs(ra.width - rb.width) > tolerance
            || abs(ra.height - rb.height) > tolerance
    }
}
