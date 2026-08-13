import Testing
import Foundation
@testable import WebAdViewSDK

// MARK: - TCFConsentProvider (bring-your-own CMP)
//
// Every TCF-certified CMP writes the user's answer to the standardized
// IABTCF_* UserDefaults keys; the provider must gate ads on those keys and
// hand consent to the page as data, never as executable code.

@Suite("TCFConsentProvider")
struct TCFConsentProviderTests {

    /// Fresh isolated defaults per test.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "tcf-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func undeterminedWhenNoKeysExist() {
        let provider = TCFConsentProvider(defaults: makeDefaults())
        #expect(provider.isConsentDetermined == false)
    }

    @Test func determinedWhenTCStringPresent() {
        let defaults = makeDefaults()
        defaults.set("CPz1234consent", forKey: "IABTCF_TCString")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == true)
    }

    @Test func emptyTCStringIsNotAnAnswer() {
        let defaults = makeDefaults()
        defaults.set("", forKey: "IABTCF_TCString")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == false)
    }

    @Test func determinedWhenGDPRDoesNotApply() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: "IABTCF_gdprApplies")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == true)
    }

    @Test func gdprAppliesWithoutTCStringIsStillUndetermined() {
        let defaults = makeDefaults()
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let provider = TCFConsentProvider(defaults: defaults)
        #expect(provider.isConsentDetermined == false)
    }

    @Test func startFiresImmediatelyAndOnEveryKeyChange() {
        let defaults = makeDefaults()
        let provider = TCFConsentProvider(defaults: defaults)
        var fires = 0
        provider.start { fires += 1 }
        #expect(fires == 1)  // stored consent must open the gate at once

        defaults.set("CPzNewConsent", forKey: "IABTCF_TCString")
        #expect(fires == 2)  // KVO on the TC string

        defaults.set(0, forKey: "IABTCF_gdprApplies")
        #expect(fires == 3)  // KVO on gdprApplies
    }

    @Test func webViewJSDefinesTCFAPIWithTheStoredString() {
        let defaults = makeDefaults()
        defaults.set("CPzABCDtcstring", forKey: "IABTCF_TCString")
        defaults.set(1, forKey: "IABTCF_gdprApplies")
        let js = TCFConsentProvider(defaults: defaults).javaScriptForWebView()
        #expect(js.contains("window.__tcfapi"))
        #expect(js.contains("\"CPzABCDtcstring\""))
        #expect(js.contains("'tcloaded'"))
    }

    @Test func hostileTCStringStaysJSONEscapedData() {
        let defaults = makeDefaults()
        defaults.set(#"evil"quote\back"#, forKey: "IABTCF_TCString")
        let js = TCFConsentProvider(defaults: defaults).javaScriptForWebView()
        // The raw quote/backslash must not survive unescaped — JSONEncoder
        // turns them into string data inside the object literal.
        #expect(!js.contains(#"evil"quote"#))
        #expect(js.contains(#"evil\"quote\\back"#))
    }

    @Test @MainActor func modeTwoConfigCarriesTheProvider() {
        let provider = TCFConsentProvider(defaults: makeDefaults())
        let config = WebAdViewSDKConfig(
            consentProvider: provider,
            adTemplateURL: URL(string: "https://publisher.dk/template.html")!
        )
        #expect(config.consentProvider === provider)
        #expect(config.consentProvider.isConsentDetermined == false)
        // App-owned CMP: preferences is a safe no-op
        config.consentProvider.showPreferences()
    }
}
