import Testing
import CoreGraphics
import Foundation
@testable import WebAdViewCore

// MARK: - LazyLoadingManager state-machine tests
//
// Fixtures (bounds/adBelowViewport/makeManager) are shared with
// RemoteLazyLoadConfigTests — see LazyLoadTestSupport.swift.

@Suite("LazyLoadingManager — fetch/display transitions")
struct FetchDisplayTests {

    @Test("Ad far away stays notLoaded")
    func farAwayStaysNotLoaded() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(900)) // outside 800pt fetch zone
        #expect(manager.adStates["ad"] == nil) // never transitioned
    }

    @Test("Ad within 800pt fetch zone becomes fetched")
    func fetchAt800() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(700))
        #expect(manager.adStates["ad"] == .fetched)
    }

    @Test("Fetched ad within 200pt display zone becomes displayed")
    func displayAt200() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(700))
        #expect(manager.adStates["ad"] == .fetched)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(150))
        #expect(manager.adStates["ad"] == .displayed)
    }

    @Test("Ad skips display when only in fetch zone")
    func fetchZoneOnlyDoesNotDisplay() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(500))
        #expect(manager.adStates["ad"] == .fetched)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(400)) // still outside 200pt
        #expect(manager.adStates["ad"] == .fetched)
    }
}

@Suite("LazyLoadingManager — unloading")
struct UnloadingTests {

    @Test("unloadingEnabled=false never unloads, no matter how far or long")
    func disabledNeverUnloads() {
        let (manager, advance) = makeManager(unloadingEnabled: false)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(100))
        #expect(manager.adStates["ad"] == .displayed)
        // Move it very far away and let a long time pass
        for _ in 0..<10 {
            advance(1.0)
            manager.updateAdFrame("ad", frame: adBelowViewport(5000 + CGFloat.random(in: 0...1)))
        }
        #expect(manager.adStates["ad"] == .displayed)
    }

    @Test("Displayed ad outside 1600pt unloads only after the 2s stability delay")
    func stabilityDelayGatesUnload() {
        let (manager, advance) = makeManager(unloadingEnabled: true)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(100))
        #expect(manager.adStates["ad"] == .displayed)

        // Move outside the unload zone — becomes a candidate, not yet unloaded
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000))
        #expect(manager.adStates["ad"] == .displayed)

        // 1 second later: still within the stability window
        advance(1.0)
        manager.updateAdFrame("ad", frame: adBelowViewport(2001))
        #expect(manager.adStates["ad"] == .displayed)

        // Past the 2s window: unloads
        advance(1.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2002))
        #expect(manager.adStates["ad"] == .unloaded)
    }

    @Test("Returning to the safe zone clears the unload candidate")
    func returningClearsCandidate() {
        let (manager, advance) = makeManager(unloadingEnabled: true)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(100))
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000)) // candidate
        advance(1.0)
        manager.updateAdFrame("ad", frame: adBelowViewport(1000)) // back inside unload zone
        // Out again — the 2s window must restart
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000))
        advance(1.5)
        manager.updateAdFrame("ad", frame: adBelowViewport(2001))
        #expect(manager.adStates["ad"] == .displayed) // only 1.5s since re-candidacy
    }

    @Test("Unloaded ad re-entering the fetch zone resets to notLoaded")
    func reentryResetsToNotLoaded() {
        let (manager, advance) = makeManager(unloadingEnabled: true)
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(100))
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000))
        advance(2.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2001))
        #expect(manager.adStates["ad"] == .unloaded)

        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(500)) // back within fetch zone
        #expect(manager.adStates["ad"] == .notLoaded)
    }
}

@Suite("LazyLoadingManager — throttle and publisher")
struct ThrottlePublisherTests {

    @Test("Updates within 67ms are throttled (no immediate second check)")
    func throttleSkipsRapidSecondCheck() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(900)) // far: no state
        #expect(manager.adStates["ad"] == nil)

        // 10ms later the ad moves into the display zone. The immediate path is
        // throttled; the trailing timer is wall-clock and hasn't fired.
        advance(0.010)
        manager.updateAdFrame("ad", frame: adBelowViewport(150))
        #expect(manager.adStates["ad"] == nil)

        // After the throttle interval, the next update processes immediately.
        advance(0.070)
        manager.updateAdFrame("ad", frame: adBelowViewport(151))
        #expect(manager.adStates["ad"] == .fetched)
    }

    @Test("adStatesPublisher emits per-ad transitions")
    func publisherEmits() {
        let (manager, advance) = makeManager()
        var received: [AdLoadState] = []
        let cancellable = manager.adStatesPublisher(for: "ad").sink { received.append($0) }
        defer { cancellable.cancel() }

        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(700))
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(100))
        #expect(received.contains(.fetched))
        #expect(received.last == .displayed)
    }

    @Test("LazyLoadingConfig seeds the manager")
    func configInit() {
        let manager = LazyLoadingManager(config: LazyLoadingConfig(
            fetchThreshold: 1000, displayThreshold: 300, unloadThreshold: 2000, unloadingEnabled: true
        ))
        #expect(manager.fetchThreshold == 1000)
        #expect(manager.displayThreshold == 300)
        #expect(manager.unloadThreshold == 2000)
        #expect(manager.unloadingEnabled)
    }
}
