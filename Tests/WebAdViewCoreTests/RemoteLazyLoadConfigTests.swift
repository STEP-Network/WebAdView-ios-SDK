import Testing
import CoreGraphics
import Foundation
@testable import WebAdViewCore

// MARK: - Remote lazy-load config (window.stepnetwork.lazyLoad)
//
// The payload originates from third-party ad-delivery JavaScript, so parsing
// and validation must reject everything that isn't a sane {fetch, render}
// object. applyRemote overrides whatever thresholds were set (STEP always
// wins) and re-runs visibility with the new zones.
//
// Fixtures (bounds/adBelowViewport/makeManager) are shared with
// LazyLoadingManagerTests — see LazyLoadTestSupport.swift.

@Suite("RemoteLazyLoadConfig — parsing")
struct RemoteLazyLoadParsingTests {

    @Test("Valid JSON object parses")
    func validJSON() {
        let config = RemoteLazyLoadConfig.parse(jsonString: #"{"fetch":150,"render":100}"#)
        #expect(config == RemoteLazyLoadConfig(fetch: 150, render: 100))
    }

    @Test("Garbage, empty, wrong-shape and missing-key payloads are rejected",
          arguments: ["not json", "", "null", "[]", #""fetch""#,
                      #"{"fetch":150}"#, #"{"render":100}"#, #"{"fetch":"x","render":100}"#])
    func rejectedPayloads(payload: String) {
        #expect(RemoteLazyLoadConfig.parse(jsonString: payload) == nil)
    }
}

@Suite("RemoteLazyLoadConfig — validation")
struct RemoteLazyLoadValidationTests {

    @Test("Sane percentages are valid; fetch may equal render")
    func validRanges() {
        #expect(RemoteLazyLoadConfig(fetch: 150, render: 100).isValid)
        #expect(RemoteLazyLoadConfig(fetch: 100, render: 100).isValid)
        #expect(RemoteLazyLoadConfig(fetch: 1000, render: 1).isValid)
    }

    @Test("Render beyond fetch, non-positive, oversized and non-finite values are invalid")
    func invalidRanges() {
        #expect(!RemoteLazyLoadConfig(fetch: 100, render: 150).isValid) // render > fetch
        #expect(!RemoteLazyLoadConfig(fetch: 0, render: 0).isValid)
        #expect(!RemoteLazyLoadConfig(fetch: 150, render: -1).isValid)
        #expect(!RemoteLazyLoadConfig(fetch: 1001, render: 100).isValid)
        #expect(!RemoteLazyLoadConfig(fetch: .infinity, render: 100).isValid)
        #expect(!RemoteLazyLoadConfig(fetch: .nan, render: 100).isValid)
    }
}

// Viewport is 800pt tall (see `bounds`), so remote percentages convert as:
// fetch 150% → 1200pt, render 100% → 800pt.
@Suite("LazyLoadingManager — applyRemote")
struct ApplyRemoteTests {

    @Test("Valid config is stored; point thresholds stay untouched")
    func appliesConfig() {
        let (manager, _) = makeManager()
        let applied = manager.applyRemote(RemoteLazyLoadConfig(fetch: 150, render: 100))
        #expect(applied)
        #expect(manager.remoteConfig == RemoteLazyLoadConfig(fetch: 150, render: 100))
        #expect(manager.fetchThreshold == 800)
        #expect(manager.unloadThreshold == 1600)
    }

    @Test("Percentages convert against the viewport height: fetch 150% = 1200pt")
    func percentOfViewportFetch() {
        let (manager, advance) = makeManager()
        manager.applyRemote(RemoteLazyLoadConfig(fetch: 150, render: 100))
        advance(0.1)
        manager.updateAdFrame("far", frame: adBelowViewport(1300)) // outside 1200pt
        #expect(manager.adStates["far"] == nil)
        advance(0.1)
        manager.updateAdFrame("near", frame: adBelowViewport(1100)) // inside 1200pt
        #expect(manager.adStates["near"] == .fetched)
    }

    @Test("Fetched ad displays within render % of the viewport: 100% = 800pt")
    func percentOfViewportRender() {
        let (manager, advance) = makeManager()
        manager.applyRemote(RemoteLazyLoadConfig(fetch: 150, render: 100))
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(1100))
        #expect(manager.adStates["ad"] == .fetched) // inside fetch, outside render
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(700)) // inside 800pt render zone
        #expect(manager.adStates["ad"] == .displayed)
    }

    @Test("Remote overrides developer-set point thresholds (STEP always wins)")
    func overridesExplicitThresholds() {
        let (manager, advance) = makeManager()
        manager.fetchThreshold = 100 // developer set a tight custom threshold
        manager.applyRemote(RemoteLazyLoadConfig(fetch: 150, render: 100))
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(1100)) // far outside 100pt, inside 150% (1200pt)
        #expect(manager.adStates["ad"] == .fetched)
    }

    @Test("Unload zone extends to the fetch distance when remote fetch reaches past it")
    func unloadZoneCoversFetchZone() {
        let (manager, advance) = makeManager(unloadingEnabled: true)
        manager.applyRemote(RemoteLazyLoadConfig(fetch: 300, render: 100)) // fetch 2400pt > unload 1600pt
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000))
        #expect(manager.adStates["ad"] == .fetched)
        // 2000pt is outside the 1600pt unload threshold, but inside the 2400pt
        // fetch distance — the ad must NOT become an unload candidate there.
        advance(2.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2001))
        advance(2.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(2000))
        #expect(manager.adStates["ad"] == .fetched)
    }

    @Test("Invalid config is ignored")
    func rejectsInvalid() {
        let (manager, _) = makeManager()
        let applied = manager.applyRemote(RemoteLazyLoadConfig(fetch: 100, render: 150))
        #expect(!applied)
        #expect(manager.remoteConfig == nil)
    }

    @Test("applyRemote re-checks visibility without a new frame or bounds update")
    func rechecksVisibility() {
        let (manager, advance) = makeManager()
        advance(0.1)
        manager.updateAdFrame("ad", frame: adBelowViewport(900)) // outside default 800pt fetch zone
        #expect(manager.adStates["ad"] == nil)
        advance(0.1)
        manager.applyRemote(RemoteLazyLoadConfig(fetch: 150, render: 100)) // zone widens to 1200pt
        #expect(manager.adStates["ad"] == .fetched) // no scroll needed
    }
}
