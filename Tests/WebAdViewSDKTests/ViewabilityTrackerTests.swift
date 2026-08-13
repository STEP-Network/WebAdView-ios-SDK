import Testing
import Combine
import CoreGraphics
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - ViewabilityTracker tests
//
// Driven with the injected clock and synthetic geometry. In the test host
// there is no key window, so effectiveViewport() degrades to the raw
// scrollViewBounds (by design) — geometry below assumes exactly that.
// @MainActor so main-queue notification observers fire synchronously.

private let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)

/// A 100x100 ad with `fraction` of its area inside the viewport.
private func adFrame(visibleFraction: CGFloat) -> CGRect {
    CGRect(x: 0, y: 700 + (1 - visibleFraction) * 100, width: 100, height: 100)
}

@MainActor
private func makeTracker() -> (ViewabilityTracker, advance: (TimeInterval) -> Void) {
    let tracker = ViewabilityTracker()
    var now: TimeInterval = 1000
    tracker.clock = { now }
    return (tracker, { now += $0 })
}

@MainActor
@Suite("ViewabilityTracker — updates publisher")
struct TrackerUpdateTests {

    @Test("Geometry flow produces updates with the true intersection ratio")
    func updatesEmitWithRatio() {
        let (tracker, _) = makeTracker()
        var received: [ViewabilityUpdate] = []
        tracker.register("ad", mode: .display)
        let sub = tracker.updates(for: "ad").sink { received.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.75))

        #expect(!received.isEmpty)
        #expect(abs((received.last?.ratio ?? 0) - 0.75) < 0.0001)
        #expect(received.last?.isVisible == true)
    }

    @Test("Dwell accrues via the injected clock and latches at 1s (display)")
    func dwellAccrualAndLatch() {
        let (tracker, advance) = makeTracker()
        var latched = false
        tracker.register("ad", mode: .display)
        let sub = tracker.updates(for: "ad").sink { if $0.becameViewable { latched = true } }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        // Nudge the frame each step so evaluate() runs with advanced time
        // (all positions stay 100% visible).
        var y: CGFloat = 300
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: y, width: 100, height: 100))
        for _ in 0..<4 {
            advance(0.3)
            y += 3
            tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: y, width: 100, height: 100))
        }
        #expect(latched) // 1.2s continuous at 100%
    }

    @Test("First registration wins: conflicting mode is ignored")
    func modeConflictFirstWins() {
        let (tracker, _) = makeTracker()
        var received: [ViewabilityUpdate] = []
        tracker.register("ad", mode: .display)
        tracker.register("ad", mode: .video) // must be ignored
        let sub = tracker.updates(for: "ad").sink { received.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 1.0))
        #expect(received.last?.mode == .display)
    }

    @Test("resetImpression re-arms a latched verdict")
    func resetImpressionRearms() {
        let (tracker, advance) = makeTracker()
        var lastUpdate: ViewabilityUpdate?
        tracker.register("ad", mode: .display)
        let sub = tracker.updates(for: "ad").sink { lastUpdate = $0 }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(1.1)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect(lastUpdate?.isViewable == true)

        tracker.resetImpression("ad")
        #expect(lastUpdate?.isViewable == false)
    }

    @Test("Consent-holdback load re-arms the impression (loadAdContent)")
    func loadAdContentRearms() async throws {
        // Regression (found 2026-07-14, greenfield consent test): the re-arm
        // only ran at controller creation, so a verdict latched against the
        // EMPTY pre-consent container carried over to the real creative when
        // the consent-driven load reused the controller.
        let (tracker, advance) = makeTracker()
        var lastUpdate: ViewabilityUpdate?
        tracker.register("div-gpt-ad-mobile_1", mode: .display)
        let sub = tracker.updates(for: "div-gpt-ad-mobile_1").sink { lastUpdate = $0 }
        defer { sub.cancel() }

        let controller = WebAdViewController(
            baseURL: "https://example.invalid/ad-template.html",
            adUnitId: "div-gpt-ad-mobile_1",
            debugSettings: DebugSettings()
        )
        controller.setupViewabilityObserver(tracker: tracker)
        controller.loadViewIfNeeded() // creates the webview (loadAdContent guards on it)

        // Latch against the empty container (pre-consent state).
        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("div-gpt-ad-mobile_1", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(1.1)
        tracker.updateContentFrame("div-gpt-ad-mobile_1", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect(lastUpdate?.isViewable == true)

        // Consent arrives → the SAME controller loads the template.
        controller.loadAdContent()
        #expect(lastUpdate?.isViewable == false) // fresh impression
    }
}

@MainActor
@Suite("ViewabilityTracker — emit policies")
struct TrackerEmitPolicyTests {

    @Test("JS stream: boolean transitions always emit; sub-5% ratio drift doesn't")
    func jsEmitPolicy() {
        let (tracker, _) = makeTracker()
        var jsReceived: [ViewabilityUpdate] = []
        tracker.register("ad", mode: .display)
        let sub = tracker.jsUpdates(for: "ad").sink { jsReceived.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.80)) // first → emits
        let afterFirst = jsReceived.count
        #expect(afterFirst >= 1)

        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.82)) // Δ2% → no emit
        #expect(jsReceived.count == afterFirst)

        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.90)) // Δ8% → emits
        #expect(jsReceived.count == afterFirst + 1)

        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.30)) // visible flips → emits
        #expect(jsReceived.count == afterFirst + 2)
        #expect(jsReceived.last?.isVisible == false)
    }

    @Test("Clip stream: 2pt tolerance suppresses jitter, real movement emits")
    func clipEmitPolicy() {
        let (tracker, _) = makeTracker()
        var clips: [ViewportClipCalculator.Clip] = []
        tracker.register("ad", mode: .display)
        let sub = tracker.clipUpdates(for: "ad").sink { clips.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 750, width: 100, height: 100)) // half visible
        let afterFirst = clips.count
        #expect(afterFirst >= 1)
        #expect(clips.last?.sliceFrame.height == 50)

        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 751, width: 100, height: 100)) // 1pt → suppressed
        #expect(clips.count == afterFirst)

        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 780, width: 100, height: 100)) // 30pt → emits
        #expect(clips.count == afterFirst + 1)
        #expect(clips.last?.sliceFrame.height == 20)
    }

    @Test("App resigning active resets counting engines (via real notification)")
    func appResignResetsCounting() {
        let (tracker, advance) = makeTracker()
        var lastUpdate: ViewabilityUpdate?
        tracker.register("ad", mode: .display)
        let sub = tracker.updates(for: "ad").sink { lastUpdate = $0 }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(0.5)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect((lastUpdate?.dwell ?? 0) > 0.4) // counting

        NotificationCenter.default.post(name: UIApplication.willResignActiveNotification, object: nil)
        #expect(lastUpdate?.isAppActive == false)
        #expect(lastUpdate?.dwell == 0) // continuous timer reset

        NotificationCenter.default.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        #expect(lastUpdate?.isAppActive == true)
    }
}
