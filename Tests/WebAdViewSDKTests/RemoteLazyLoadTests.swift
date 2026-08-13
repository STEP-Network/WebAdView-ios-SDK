import Testing
import CoreGraphics
import Foundation
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - Remote lazy-load read-back (controller seam + per-host cache)
//
// Exercises WebAdViewController.handleRemoteLazyLoadPayload directly — the
// seam behind the didFinish poll loop (evaluateJavaScript needs a live page).
// Payloads are what JSON.stringify(window.stepnetwork.lazyLoad) would return;
// they cross from third-party page JS into native, so malformed input must be
// rejected without touching the manager.

@MainActor
private func makeController(store: RemoteLazyLoadStore) -> (WebAdViewController, LazyLoadingManager) {
    let controller = WebAdViewController(
        baseURL: "https://example.invalid/ad-template.html",
        adUnitId: "div-gpt-ad-mobile_1",
        debugSettings: DebugSettings()
    )
    controller.remoteLazyLoadStore = store
    let manager = LazyLoadingManager()
    controller.setupLazyLoadingObserver(manager: manager)
    return (controller, manager)
}

private func makeStore(_ suiteName: String) -> RemoteLazyLoadStore {
    let defaults = UserDefaults(suiteName: "RemoteLazyLoadTests.\(suiteName)")!
    defaults.removePersistentDomain(forName: "RemoteLazyLoadTests.\(suiteName)")
    return RemoteLazyLoadStore(defaults: defaults)
}

@MainActor
@Suite("Remote lazy-load payload handling")
struct RemoteLazyLoadPayloadTests {

    @Test("Valid payload applies to the observed manager")
    func validPayloadApplies() {
        let (controller, manager) = makeController(store: makeStore(#function))
        let handled = controller.handleRemoteLazyLoadPayload(#"{"fetch":150,"render":100}"#)
        #expect(handled)
        #expect(manager.remoteConfig == RemoteLazyLoadConfig(fetch: 150, render: 100))
    }

    @Test("Valid payload is cached under the template host")
    func validPayloadCaches() {
        let store = makeStore(#function)
        let (controller, _) = makeController(store: store)
        controller.handleRemoteLazyLoadPayload(#"{"fetch":150,"render":100}"#)
        // No page has loaded in tests, so the host comes from the controller's
        // template base URL ("example.invalid").
        #expect(store.load(forHost: "example.invalid") == RemoteLazyLoadConfig(fetch: 150, render: 100))
        #expect(store.load(forHost: "other.example") == nil)
    }

    @Test("Malformed payloads are rejected and no remote config is stored",
          arguments: [nil, "null", "[]", "not json", #"{"fetch":"x","render":100}"#,
                      #"{"fetch":100,"render":150}"#, #"{"fetch":9999999,"render":1}"#])
    func malformedPayloadIgnored(payload: String?) {
        let (controller, manager) = makeController(store: makeStore("malformed"))
        let handled = controller.handleRemoteLazyLoadPayload(payload)
        #expect(!handled)
        #expect(manager.remoteConfig == nil)
    }
}

@Suite("RemoteLazyLoadStore")
struct RemoteLazyLoadStoreTests {

    @Test("Round-trips a config per host")
    func roundTrip() {
        let store = makeStore(#function)
        store.save(RemoteLazyLoadConfig(fetch: 150, render: 100), forHost: "pub.example")
        #expect(store.load(forHost: "pub.example") == RemoteLazyLoadConfig(fetch: 150, render: 100))
        #expect(store.load(forHost: "other.example") == nil)
    }

    @Test("A cached config that fails validation is not returned")
    func invalidCachedConfigDropped() {
        let store = makeStore(#function)
        store.save(RemoteLazyLoadConfig(fetch: 100, render: 150), forHost: "pub.example")
        #expect(store.load(forHost: "pub.example") == nil)
    }
}
