import Testing
import Combine
import CoreGraphics
import Foundation
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - WebAdScope (UIKit-level lazy loading + viewability container)
//
// The scope is the non-SwiftUI entry point (Flutter plugin, UIKit hosts): the
// host supplies window-space geometry and the scope drives the SAME
// LazyLoadingManager / ViewabilityTracker the SwiftUI modifier uses. Driven
// here with synthetic geometry and injected clocks (no key window in the
// test host, so the tracker's effective viewport is the raw bounds).

private let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)

/// A 100pt-tall ad whose top edge sits `distance` points below the viewport.
private func adBelow(_ distance: CGFloat) -> CGRect {
    CGRect(x: 0, y: viewport.maxY + distance, width: 320, height: 100)
}

@MainActor
private func makeScope(config: LazyLoadingConfig = LazyLoadingConfig()) -> (WebAdScope, advance: (TimeInterval) -> Void) {
    let scope = WebAdScope(config: config, remoteStore: RemoteLazyLoadStore(defaults: UserDefaults(suiteName: "WebAdScopeTests.empty")!), templateHost: nil)
    var managerTime = Date(timeIntervalSinceReferenceDate: 0)
    var trackerTime: TimeInterval = 1000
    scope.manager.now = { managerTime }
    scope.tracker.clock = { trackerTime }
    let advance: (TimeInterval) -> Void = { dt in
        managerTime = managerTime.addingTimeInterval(dt)
        trackerTime += dt
    }
    return (scope, advance)
}

@MainActor
@Suite("WebAdScope — lazy loading driven by external geometry")
struct WebAdScopeLazyLoadTests {

    @Test("Host geometry drives notLoaded → fetched → displayed")
    func geometryDrivesStates() {
        let (scope, advance) = makeScope()
        var states: [AdLoadState] = []
        let sub = scope.loadStates(for: "ad").sink { states.append($0) }
        defer { sub.cancel() }

        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateAdFrame("ad", frame: adBelow(1000)) // beyond the 800pt fetch zone
        #expect(scope.loadState(for: "ad") == .notLoaded)
        #expect(states.isEmpty)

        advance(0.1)
        scope.updateAdFrame("ad", frame: adBelow(500))  // inside fetch, outside display (200)
        #expect(scope.loadState(for: "ad") == .fetched)

        advance(0.1)
        scope.updateAdFrame("ad", frame: adBelow(100))  // inside display zone
        #expect(scope.loadState(for: "ad") == .displayed)
        #expect(states == [.fetched, .displayed])
    }

    @Test("loadStates replays the current state to a late subscriber, without duplicates")
    func loadStatesReplays() {
        let (scope, advance) = makeScope()
        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateAdFrame("ad", frame: adBelow(500))
        advance(0.1)
        #expect(scope.loadState(for: "ad") == .fetched)

        var states: [AdLoadState] = []
        let sub = scope.loadStates(for: "ad").sink { states.append($0) }
        defer { sub.cancel() }
        #expect(states == [.fetched])

        // Another ad transitioning re-publishes the whole dictionary; the
        // scope's stream must not re-emit this ad's unchanged state.
        scope.updateAdFrame("other", frame: adBelow(100))
        advance(0.1)
        scope.updateAdFrame("other", frame: adBelow(50))
        #expect(states == [.fetched])
    }

    @Test("unregister forgets the ad: no further transitions, state back to notLoaded")
    func unregisterStopsTransitions() {
        let (scope, advance) = makeScope()
        var states: [AdLoadState] = []
        let sub = scope.loadStates(for: "ad").sink { states.append($0) }
        defer { sub.cancel() }

        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateAdFrame("ad", frame: adBelow(500))
        #expect(states == [.fetched])

        scope.unregister("ad")
        #expect(scope.loadState(for: "ad") == .notLoaded)

        // Geometry that would have displayed the ad now does nothing.
        advance(0.1)
        scope.updateViewport(viewport.offsetBy(dx: 0, dy: 1))
        #expect(scope.loadState(for: "ad") == .notLoaded)
        #expect(states == [.fetched])
    }

    @Test("A cached remote config for the template host is applied at creation")
    func remoteCacheApplied() {
        let suite = "WebAdScopeTests.remote"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = RemoteLazyLoadStore(defaults: defaults)
        store.save(RemoteLazyLoadConfig(fetch: 150, render: 100), forHost: "pub.example")

        let scope = WebAdScope(config: LazyLoadingConfig(), remoteStore: store, templateHost: "pub.example")
        #expect(scope.manager.remoteConfig == RemoteLazyLoadConfig(fetch: 150, render: 100))

        let otherHost = WebAdScope(config: LazyLoadingConfig(), remoteStore: store, templateHost: "other.example")
        #expect(otherHost.manager.remoteConfig == nil)
    }
}

@MainActor
@Suite("WebAdScope — viewability driven by external geometry")
struct WebAdScopeViewabilityTests {

    /// Fully visible 100x100 creative, nudged by `step` so evaluate() runs.
    private func creative(step: CGFloat) -> CGRect {
        CGRect(x: 0, y: 300 + step, width: 100, height: 100)
    }

    @Test("Creative geometry latches a viewable impression after 1s continuous")
    func latchesAfterOneSecond() {
        let (scope, advance) = makeScope()
        var latched = false
        let sub = scope.viewabilityUpdates(for: "ad").sink { if $0.becameViewable { latched = true } }
        defer { sub.cancel() }

        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateCreativeFrame("ad", frame: creative(step: 0))
        advance(0.6)
        scope.updateCreativeFrame("ad", frame: creative(step: 1))
        #expect(!latched)
        advance(0.6)
        scope.updateCreativeFrame("ad", frame: creative(step: 2))
        #expect(latched)
    }

    @Test("setHostVisible(false) resets the continuous timer like backgrounding")
    func hostHiddenResetsTimer() {
        let (scope, advance) = makeScope()
        var last: ViewabilityUpdate?
        let sub = scope.viewabilityUpdates(for: "ad").sink { last = $0 }
        defer { sub.cancel() }

        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateCreativeFrame("ad", frame: creative(step: 0))
        advance(0.7)
        scope.updateCreativeFrame("ad", frame: creative(step: 1))
        #expect(last?.isVisible == true)
        #expect(last?.isViewable == false)

        // Another screen covers the host: not human-viewable → timer reset.
        scope.setHostVisible(false)
        #expect(last?.isVisible == false)
        #expect(last?.isAppActive == false)

        // Back on top: the 1s must start over, so 0.7s + 0.6s does not latch…
        scope.setHostVisible(true)
        advance(0.6)
        scope.updateCreativeFrame("ad", frame: creative(step: 2))
        #expect(last?.isViewable == false)

        // …but a further 0.5s (1.1s continuous since re-showing) does.
        advance(0.5)
        scope.updateCreativeFrame("ad", frame: creative(step: 3))
        #expect(last?.isViewable == true)
    }

    @Test("unregister stops viewability updates for the ad")
    func unregisterStopsUpdates() {
        let (scope, advance) = makeScope()
        var count = 0
        let sub = scope.viewabilityUpdates(for: "ad").sink { _ in count += 1 }
        defer { sub.cancel() }

        scope.register("ad")
        scope.tracker.markRendered("ad") // creative rendered — measurement may count
        scope.updateViewport(viewport)
        scope.updateCreativeFrame("ad", frame: creative(step: 0))
        #expect(count > 0)
        let before = count

        scope.unregister("ad")
        advance(0.5)
        scope.updateCreativeFrame("ad", frame: creative(step: 1))
        scope.updateViewport(viewport.offsetBy(dx: 0, dy: 1))
        #expect(count == before)
    }
}
