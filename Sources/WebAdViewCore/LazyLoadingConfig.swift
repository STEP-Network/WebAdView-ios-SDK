import Foundation
import CoreGraphics

/// Tuning values for the scroll-based lazy-loading system.
/// Distances are in points from the scroll viewport's edges.
public struct LazyLoadingConfig: Equatable {
    /// Distance at which an ad starts fetching content. Default 800pt.
    public var fetchThreshold: CGFloat
    /// Distance at which an ad is displayed (render trigger fires). Default 200pt.
    public var displayThreshold: CGFloat
    /// Distance beyond which an ad may be unloaded. Default 1600pt
    /// (hysteresis vs. the display threshold prevents flickering).
    public var unloadThreshold: CGFloat
    /// Whether ads are unloaded when far out of view. Default false (UX over memory).
    public var unloadingEnabled: Bool

    public init(
        fetchThreshold: CGFloat = 800,
        displayThreshold: CGFloat = 200,
        unloadThreshold: CGFloat = 1600,
        unloadingEnabled: Bool = false
    ) {
        self.fetchThreshold = fetchThreshold
        self.displayThreshold = displayThreshold
        self.unloadThreshold = unloadThreshold
        self.unloadingEnabled = unloadingEnabled
    }
}
