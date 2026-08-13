import CoreGraphics
import Foundation
@testable import WebAdViewCore

// MARK: - Shared lazy-loading test fixtures
//
// Used by LazyLoadingManagerTests and RemoteLazyLoadConfigTests. The manager
// is driven with synthetic frames/bounds and an injected clock. Every clock
// step ≥ 67ms so the throttle takes the immediate path (the trailing-edge
// Timer is wall-clock and never fires in these tests).

/// 400x800 viewport at the origin.
let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

/// A 100pt-tall ad whose top edge sits `distance` points below the viewport's
/// bottom edge (use negative distance to place it inside the viewport).
func adBelowViewport(_ distance: CGFloat) -> CGRect {
    CGRect(x: 0, y: bounds.maxY + distance, width: 320, height: 100)
}

func makeManager(unloadingEnabled: Bool = false) -> (LazyLoadingManager, (TimeInterval) -> Void) {
    let manager = LazyLoadingManager()
    manager.unloadingEnabled = unloadingEnabled
    var currentTime = Date(timeIntervalSinceReferenceDate: 0)
    manager.now = { currentTime }
    let advance: (TimeInterval) -> Void = { currentTime = currentTime.addingTimeInterval($0) }
    manager.updateScrollViewBounds(bounds)
    return (manager, advance)
}
