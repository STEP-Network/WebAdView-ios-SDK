import Testing
import Foundation
@testable import WebAdViewSDK

// MARK: - AppDidomiConsentProvider (app-owned Didomi)
//
// Didomi is never initialized in the test process, so Didomi.shared.isReady()
// is false — which is exactly the property under test: even when a TC string
// is already present (some CMP configurations publish one BEFORE the user
// answers the notice), the gate must stay closed until Didomi itself reports
// that the user has actually answered.

@Suite("AppDidomiConsentProvider")
struct AppDidomiConsentProviderTests {

    private func makeDefaults() -> UserDefaults {
        let suiteName = "app-didomi-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("A pre-answer TC string does NOT open the gate")
    func preAnswerTCStringDoesNotOpenTheGate() {
        let defaults = makeDefaults()
        defaults.set("CPzPreAnswerDefaultString", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let provider = AppDidomiConsentProvider(defaults: defaults)
        // The generic TCF provider would open here; the Didomi-aware one
        // waits for Didomi's real "user has answered" signal.
        #expect(provider.isConsentDetermined == false)
    }

    @Test("Page hand-off delegates to the __tcfapi stub with the stored string")
    func webViewJSDelegatesToTCFStub() {
        let defaults = makeDefaults()
        defaults.set("CPzXYZExample", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let js = AppDidomiConsentProvider(defaults: defaults).javaScriptForWebView()
        #expect(js.contains("window.__tcfapi"))
        #expect(js.contains("\"CPzXYZExample\""))
    }
}
