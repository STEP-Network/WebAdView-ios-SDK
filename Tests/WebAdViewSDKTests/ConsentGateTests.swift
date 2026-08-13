import Testing
import Foundation
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - Consent gate (fail-closed ad loading)
//
// Ads must never load before a ConsentProvider reports a determined answer —
// the revenue/compliance-critical gate in WebAdViewController.checkConsentAndLoad.
// A stub provider is injected via the controller's consentProviderOverride
// seam so the global WebAdViewSDK.configuration is never touched (it is
// process-wide state shared with concurrently running suites).

final class StubConsentProvider: ConsentProvider {
    var isConsentDetermined: Bool
    /// What the "CMP" currently hands to ad pages — mutable so tests can
    /// simulate the user changing their answer after ads have loaded.
    var consentJS: String = ""
    private(set) var startCalled = false
    private(set) var onChange: (() -> Void)?

    init(determined: Bool) {
        self.isConsentDetermined = determined
    }

    func start(onChange: @escaping () -> Void) {
        startCalled = true
        self.onChange = onChange
    }

    func javaScriptForWebView() -> String { consentJS }
    func showPreferences() {}
}

@MainActor
private func scriptSources(_ controller: WebAdViewController) -> [String] {
    controller.webView.configuration.userContentController.userScripts.map(\.source)
}

@MainActor
private func makeController(
    consent: StubConsentProvider,
    baseURL: String = "https://example.invalid/ad-template.html"
) -> WebAdViewController {
    let controller = WebAdViewController(
        baseURL: baseURL,
        adUnitId: "div-gpt-ad-mobile_1",
        debugSettings: DebugSettings()
    )
    controller.consentProviderOverride = consent
    return controller
}

@MainActor
@Suite("Consent gate — fail-closed loading")
struct ConsentGateTests {

    @Test("Undetermined consent holds the ad back (fail-closed)")
    func undeterminedHoldsBack() {
        let controller = makeController(consent: StubConsentProvider(determined: false))
        controller.loadViewIfNeeded() // viewDidLoad → checkConsentAndLoad
        #expect(!controller.hasLoadedContent)
    }

    @Test("Consent already determined at view load loads immediately")
    func determinedLoadsImmediately() {
        let controller = makeController(consent: StubConsentProvider(determined: true))
        controller.loadViewIfNeeded()
        #expect(controller.hasLoadedContent)
    }

    @Test("Held-back ad loads when the consent notification arrives")
    func consentChangeTriggersLoad() {
        let stub = StubConsentProvider(determined: false)
        let controller = makeController(consent: stub)
        controller.loadViewIfNeeded()
        #expect(!controller.hasLoadedContent)

        // The user answers the notice: the provider flips and the SDK posts
        // the change notification (posted here directly — the posting glue in
        // initialize is covered by SDKInitializeTests).
        stub.isConsentDetermined = true
        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)

        #expect(controller.hasLoadedContent)
    }

    @Test("Notification without determined consent still holds the ad back")
    func notificationAloneDoesNotOpenTheGate() {
        let controller = makeController(consent: StubConsentProvider(determined: false))
        controller.loadViewIfNeeded()

        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)

        #expect(!controller.hasLoadedContent)
    }

    @Test("Consent change after load reloads the ad with the new consent")
    func consentChangeAfterLoadReloads() {
        let stub = StubConsentProvider(determined: true)
        stub.consentJS = "// consent v1"
        let controller = makeController(consent: stub)
        controller.loadViewIfNeeded()
        #expect(controller.hasLoadedContent)
        #expect(scriptSources(controller).contains("// consent v1"))

        // The user changes their answer: the CMP's hand-off script changes
        // and the change notification fires.
        stub.consentJS = "// consent v2"
        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)

        let sources = scriptSources(controller)
        #expect(controller.hasLoadedContent) // reloaded, not stuck unloaded
        #expect(sources.contains("// consent v2"))
        #expect(!sources.contains("// consent v1")) // the stale snapshot is gone
    }

    @Test("Provider notifications without a consent change do not reload")
    func unchangedConsentDoesNotReload() {
        let stub = StubConsentProvider(determined: true)
        stub.consentJS = "// consent v1"
        let controller = makeController(consent: stub)
        controller.loadViewIfNeeded()
        let countBefore = scriptSources(controller).count

        // Providers post this on readiness right after the initial load —
        // it must not tear the ad down or stack up duplicate scripts.
        NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)

        let sources = scriptSources(controller)
        #expect(sources.count == countBefore)
        #expect(sources.contains("// consent v1"))
    }

    @Test("Empty template URL fails loudly and allows a later retry")
    func emptyBaseURLFailsOpenForRetry() {
        // SDK never initialized → WebAdView passes an empty baseURL through.
        // loadAdContent must not get stuck: hasLoadedContent is reset so the
        // ad can retry once a valid consent/init state arrives.
        let controller = makeController(
            consent: StubConsentProvider(determined: true),
            baseURL: ""
        )
        controller.loadViewIfNeeded() // consent OK → loadAdContent runs → URL guard trips
        #expect(!controller.hasLoadedContent)
    }
}
