import Testing
import CoreGraphics
@testable import WebAdViewCore

// MARK: - ViewabilityEngine unit tests
//
// All tests drive ViewabilityEngine.ingest with synthetic timestamps —
// no clocks, no timers, no WebKit/SwiftUI — per IAB/MRC rules:
// >= 50% of pixels for >= 1s (display) / >= 2s (video), CONTINUOUS.

/// A 100x100 ad and a 400x800 viewport, with helpers to position the ad
/// so an exact fraction of its area is inside the viewport.
private let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)

/// Returns a 100x100 ad frame with `fraction` of its area inside `viewport`
/// (slid off the bottom edge).
private func adFrame(visibleFraction: CGFloat) -> CGRect {
    // Fully inside at y=700 (bottom-aligned); each pt further down hides 1%.
    let hiddenPoints = (1 - visibleFraction) * 100
    return CGRect(x: 0, y: 700 + hiddenPoints, width: 100, height: 100)
}

@Suite("ViewabilityEngine — intersection ratio")
struct IntersectionRatioTests {

    @Test("Partially off-screen ratios: half below bottom = 0.5, fully outside = 0, fully inside = 1")
    func intersectionRatioPartialOffscreen() {
        #expect(ViewabilityEngine.intersectionRatio(of: adFrame(visibleFraction: 0.5), in: viewport) == 0.5)
        #expect(ViewabilityEngine.intersectionRatio(of: CGRect(x: 0, y: 900, width: 100, height: 100), in: viewport) == 0.0)
        #expect(ViewabilityEngine.intersectionRatio(of: CGRect(x: 100, y: 300, width: 100, height: 100), in: viewport) == 1.0)
    }

    @Test("Zero-area ad frame and null/empty viewport are safe (ratio 0, no crash)")
    func zeroAreaFrameAndNullViewportAreSafe() {
        #expect(ViewabilityEngine.intersectionRatio(of: .zero, in: viewport) == 0)
        #expect(ViewabilityEngine.intersectionRatio(of: CGRect(x: 0, y: 0, width: 100, height: 0), in: viewport) == 0)
        #expect(ViewabilityEngine.intersectionRatio(of: adFrame(visibleFraction: 1.0), in: .null) == 0)
        #expect(ViewabilityEngine.intersectionRatio(of: adFrame(visibleFraction: 1.0), in: .zero) == 0)

        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let update = engine.ingest(adFrame: .zero, viewport: .null, isAppActive: true, at: 0)
        #expect(update.ratio == 0)
        #expect(engine.state == .idle)
    }
}

@Suite("ViewabilityEngine — 50% pixel threshold")
struct RatioThresholdTests {

    @Test("Exactly 50% visible counts (threshold is inclusive)")
    func ratioExactly50PercentCounts() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let update = engine.ingest(adFrame: adFrame(visibleFraction: 0.5), viewport: viewport, isAppActive: true, at: 0)
        #expect(update.ratio == 0.5)
        #expect(update.isVisible)
        #expect(engine.state == .counting(since: 0))
    }

    @Test("49% visible does not count")
    func ratioBelow50DoesNotCount() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let update = engine.ingest(adFrame: adFrame(visibleFraction: 0.49), viewport: viewport, isAppActive: true, at: 0)
        #expect(abs(update.ratio - 0.49) < 0.0001)
        #expect(!update.isVisible)
        #expect(engine.state == .idle)
    }
}

@Suite("ViewabilityEngine — display threshold (1s continuous)")
struct DisplayThresholdTests {

    @Test("Viewable after 1 continuous second at >= 50%")
    func displayViewableAfterOneSecond() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let frame = adFrame(visibleFraction: 0.8)

        var update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 0)
        #expect(!update.isViewable)
        update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 0.5)
        #expect(!update.isViewable)
        #expect(abs(update.dwell - 0.5) < 0.0001)
        update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 1.0)
        #expect(update.isViewable)
        #expect(update.becameViewable)
        #expect(engine.state == .viewable)
    }

    @Test("Not viewable at 900ms")
    func displayNotViewableAt900ms() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let frame = adFrame(visibleFraction: 0.8)

        for t in stride(from: 0.0, through: 0.9, by: 0.1) {
            let update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: t)
            #expect(!update.isViewable)
        }
        #expect(engine.state == .counting(since: 0))
    }
}

@Suite("ViewabilityEngine — continuity requirement")
struct ContinuityTests {

    @Test("Dipping below 50% resets the continuous timer")
    func dipBelow50ResetsContinuousTimer() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let visible = adFrame(visibleFraction: 0.8)
        let dipped = adFrame(visibleFraction: 0.4)

        // 0.6s at 80%
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 0)
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 0.6)
        // Brief dip to 40% resets
        let dipUpdate = engine.ingest(adFrame: dipped, viewport: viewport, isAppActive: true, at: 0.7)
        #expect(engine.state == .idle)
        #expect(dipUpdate.dwell == 0)

        // Back to 80% — full 1.0s required again from re-entry (t=0.8)
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 0.8)
        var update = engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 1.4) // only 0.6s again
        #expect(!update.isViewable)
        update = engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 1.8) // 1.0s after re-entry
        #expect(update.isViewable)
        #expect(update.becameViewable)
    }

    @Test("Backgrounding resets dwell; full duration required after reactivation")
    func backgroundingResetsDwell() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let frame = adFrame(visibleFraction: 1.0)

        // Counting for 0.8s...
        engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 0)
        engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 0.8)
        // ...then the app resigns active: timer resets even though pixels unchanged
        let backgrounded = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: false, at: 0.9)
        #expect(engine.state == .idle)
        #expect(backgrounded.dwell == 0)
        #expect(!backgrounded.isVisible)

        // Active again at t=2.0: needs a fresh full second
        engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 2.0)
        var update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 2.9)
        #expect(!update.isViewable)
        update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 3.0)
        #expect(update.isViewable)
    }
}

@Suite("ViewabilityEngine — video mode (2s continuous)")
struct VideoModeTests {

    @Test("Video requires 2 continuous seconds")
    func videoRequiresTwoSeconds() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .video)
        let frame = adFrame(visibleFraction: 1.0)

        engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 0)
        var update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 1.9)
        #expect(!update.isViewable)
        update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: 2.0)
        #expect(update.isViewable)
        #expect(update.becameViewable)
    }

    @Test("Dipping below 50% resets the video timer too")
    func videoDipResetsContinuousTimer() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .video)
        let visible = adFrame(visibleFraction: 1.0)
        let dipped = adFrame(visibleFraction: 0.4)

        // 1.9s of the 2s requirement, then a dip
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 0)
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 1.9)
        let dipUpdate = engine.ingest(adFrame: dipped, viewport: viewport, isAppActive: true, at: 2.0)
        #expect(engine.state == .idle)
        #expect(dipUpdate.dwell == 0)

        // Back above 50% — the full 2s is required again from re-entry (t=2.1).
        // The passing sample sits at 2.1s so binary Double subtraction can't
        // land a hair under the threshold (4.1 - 2.1 < 2.0 in Double).
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 2.1)
        var update = engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 4.0) // 1.9s again
        #expect(!update.isViewable)
        update = engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 4.2) // 2.1s after re-entry
        #expect(update.isViewable)
        #expect(update.becameViewable)
    }
}

@Suite("ViewabilityEngine — verdict latching")
struct LatchingTests {

    @Test("Verdict stays latched after visibility is lost; reset() re-arms")
    func verdictLatchesUntilReset() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let visible = adFrame(visibleFraction: 1.0)
        let gone = CGRect(x: 0, y: 2000, width: 100, height: 100)

        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 0)
        engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 1.0)
        #expect(engine.state == .viewable)

        // Scrolled fully away — the counted impression stays counted
        let offscreen = engine.ingest(adFrame: gone, viewport: viewport, isAppActive: true, at: 2.0)
        #expect(offscreen.isViewable)
        #expect(offscreen.ratio == 0)

        // New impression re-arms
        engine.reset()
        #expect(engine.state == .idle)
        let fresh = engine.ingest(adFrame: visible, viewport: viewport, isAppActive: true, at: 3.0)
        #expect(!fresh.isViewable)
        #expect(engine.state == .counting(since: 3.0))
    }

    @Test("becameViewable fires on exactly one update")
    func becameViewableFiresExactlyOnce() {
        let engine = ViewabilityEngine(adUnitId: "ad", mode: .display)
        let frame = adFrame(visibleFraction: 1.0)

        var latchCount = 0
        for t in stride(from: 0.0, through: 3.0, by: 0.1) {
            let update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: true, at: t)
            if update.becameViewable { latchCount += 1 }
        }
        #expect(latchCount == 1)
        #expect(engine.state == .viewable)
    }
}
