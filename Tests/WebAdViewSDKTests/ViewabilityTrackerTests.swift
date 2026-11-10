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
        tracker.markRendered("ad")
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
        tracker.markRendered("ad")
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
        tracker.markRendered("ad")
        tracker.register("ad", mode: .video) // must be ignored
        let sub = tracker.updates(for: "ad").sink { received.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 1.0))
        #expect(received.last?.mode == .display)
    }

    @Test("resetImpression re-arms a latched verdict; the next render latches again")
    func resetImpressionRearms() {
        let (tracker, advance) = makeTracker()
        var latches = 0
        tracker.register("ad", mode: .display)
        tracker.markRendered("ad")
        let sub = tracker.updates(for: "ad").sink { if $0.becameViewable { latches += 1 } }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(1.1)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect(latches == 1)

        tracker.resetImpression("ad")
        advance(1.5)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 302, width: 100, height: 100))
        #expect(latches == 1) // parked until the new creative renders
        tracker.markRendered("ad")
        advance(1.1)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 303, width: 100, height: 100))
        #expect(latches == 2)
    }

    @Test("No dwell and no verdict before the creative renders (found 2026-09-11)")
    func nothingBeforeRender() {
        // Regression: the slot latched a "viewable" against the EMPTY box
        // while the page was still loading, so onViewabilityChange fired
        // before any creative existed (and again after the load).
        let (tracker, advance) = makeTracker()
        var updates = 0
        var latches = 0
        tracker.register("ad", mode: .display)   // deliberately NOT rendered yet
        let sub = tracker.updates(for: "ad").sink { updates += 1; if $0.becameViewable { latches += 1 } }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(1.5)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect(updates == 0)
        #expect(latches == 0)

        tracker.markRendered("ad")             // adSize arrived: counting starts now
        advance(0.5)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 302, width: 100, height: 100))
        #expect(latches == 0)                  // the 1.5 s before render do not count
        advance(0.6)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 303, width: 100, height: 100))
        #expect(latches == 1)
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

        // A creative rendered and latched (a previous page in this controller).
        tracker.markRendered("div-gpt-ad-mobile_1")
        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("div-gpt-ad-mobile_1", frame: CGRect(x: 0, y: 300, width: 100, height: 100))
        advance(1.1)
        tracker.updateContentFrame("div-gpt-ad-mobile_1", frame: CGRect(x: 0, y: 301, width: 100, height: 100))
        #expect(lastUpdate?.isViewable == true)

        // Consent arrives → the SAME controller loads the template: the old
        // verdict must not carry over, and nothing counts until the new
        // creative renders.
        controller.loadAdContent()
        lastUpdate = nil
        advance(1.5)
        tracker.updateContentFrame("div-gpt-ad-mobile_1", frame: CGRect(x: 0, y: 302, width: 100, height: 100))
        #expect(lastUpdate == nil) // parked: no updates while the page loads
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
        tracker.markRendered("ad")
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
        tracker.markRendered("ad")
        let sub = tracker.clipUpdates(for: "ad").sink { clips.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 750, width: 100, height: 100)) // half visible
        let afterFirst = clips.count
        #expect(afterFirst >= 1)
        #expect(clips.last?.sliceFrame.height == 50)

        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 751, width: 100, height: 100)) // 1pt → suppressed
        #expect(clips.count == afterFirst)

        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 780, width: 100, height: 100)) // 30pt → pending (cadence)
        #expect(clips.count == afterFirst)
        tracker.flushTrailingForTesting()
        #expect(clips.count == afterFirst + 1)
        #expect(clips.last?.sliceFrame.height == 20)
    }

    @Test("Clip cadence: ≤1 emit per 100ms per ad while moving, regime changes immediate, trailing flush lands the final slice")
    func clipCadence() {
        let (tracker, advance) = makeTracker()
        var clips: [ViewportClipCalculator.Clip] = []
        var scheduled = 0
        tracker.scheduleTrailing = { _, _ in scheduled += 1; return AnyCancellable {} }
        tracker.register("ad", mode: .display)
        let sub = tracker.clipUpdates(for: "ad").sink { clips.append($0) }
        defer { sub.cancel() }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 750, width: 100, height: 100)) // partial: immediate
        #expect(clips.count == 1)
        advance(0.016)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 740, width: 100, height: 100)) // pending
        advance(0.016)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 730, width: 100, height: 100)) // latest wins
        #expect(clips.count == 1)
        #expect(scheduled == 1)
        tracker.flushTrailingForTesting()
        #expect(clips.count == 2)
        #expect(clips.last?.sliceFrame.height == 70)
        advance(0.016)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 600, width: 100, height: 100)) // partial → full: immediate
        #expect(clips.count == 3)
        #expect(clips.last?.isFullyVisible == true)
        advance(0.1)
        tracker.updateContentFrame("ad", frame: CGRect(x: 0, y: 760, width: 100, height: 100)) // full → partial: immediate
        #expect(clips.count == 4)
    }

    @Test("Host stream: first update + transitions immediate, ratio changes coalesced to 67ms, idle = silent")
    func hostEmitPolicy() {
        let (tracker, advance) = makeTracker()
        var host: [ViewabilityUpdate] = []
        var raw = 0
        tracker.scheduleTrailing = { _, _ in AnyCancellable {} }
        tracker.register("ad", mode: .display)
        tracker.markRendered("ad")
        let subs = [
            tracker.hostUpdates(for: "ad").sink { host.append($0) },
            tracker.updates(for: "ad").sink { _ in raw += 1 },
        ]
        defer { subs.forEach { $0.cancel() } }

        tracker.updateScrollViewBounds(bounds)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.60))
        #expect(host.count == 1) // first
        advance(0.016)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.62))
        #expect(host.count == 1) // < 5 %: not significant
        advance(0.016)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.70))
        #expect(host.count == 1) // ≥ 5 % but within 67 ms: pending
        advance(0.016)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.40))
        #expect(host.count == 2) // visible → false: immediate
        #expect(host.last?.isVisible == false)
        #expect(raw > host.count)
        tracker.flushTrailingForTesting()
        #expect(host.count == 2) // the pending 0.70 was superseded
        advance(0.1)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.80))
        #expect(host.count == 3) // transition back
        advance(0.016)
        tracker.updateContentFrame("ad", frame: adFrame(visibleFraction: 0.90))
        #expect(host.count == 3) // pending
        tracker.flushTrailingForTesting()
        #expect(host.count == 4)
        let lastRatio = host.last?.ratio ?? 0
        #expect(abs(lastRatio - 0.90) < 0.001)
    }

    @Test("updateGeometry batch: one evaluation for all ads, none when nothing moved")
    func batchGeometry() {
        let (tracker, _) = makeTracker()
        var updates = 0
        for id in ["a", "b", "c"] {
            tracker.register(id, mode: .display)
            tracker.markRendered(id)
        }
        let subs = ["a", "b", "c"].map { tracker.updates(for: $0).sink { _ in updates += 1 } }
        defer { subs.forEach { $0.cancel() } }
        let frames = ["a": adFrame(visibleFraction: 0.6), "b": adFrame(visibleFraction: 0.7), "c": adFrame(visibleFraction: 0.8)]
        tracker.updateGeometry(viewport: bounds, contentFrames: frames)
        #expect(updates == 3) // one pass → one update per ad (not 3 × 3)
        tracker.updateGeometry(viewport: bounds, contentFrames: frames)
        #expect(updates == 3) // nothing moved
    }

    @Test("App resigning active resets counting engines (via real notification)")
    func appResignResetsCounting() {
        let (tracker, advance) = makeTracker()
        var lastUpdate: ViewabilityUpdate?
        tracker.register("ad", mode: .display)
        tracker.markRendered("ad")
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
