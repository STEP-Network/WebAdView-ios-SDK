import Testing
import Foundation
@testable import WebAdViewSDK

// MARK: - WebAdViewSDK.initialize (bootstrap)
//
// initialize(config:) owns process-wide state (the static configuration), so
// this suite is serialized and restores a clean slate around every test via
// the internal _resetForTesting hook. Stub providers keep isConsentDetermined
// false and never invoke onChange, so no consent notification leaks into
// suites running in parallel.

@MainActor
@Suite("WebAdViewSDK.initialize", .serialized)
struct SDKInitializeTests {

    private func makeConfig(provider: StubConsentProvider) -> WebAdViewSDKConfig {
        WebAdViewSDKConfig(
            consentProvider: provider,
            adTemplateURL: URL(string: "https://publisher.dk/template.html")!
        )
    }

    @Test("Sets the configuration and starts the consent provider")
    func initializeSetsConfigurationAndStartsProvider() {
        WebAdViewSDK._resetForTesting()
        defer { WebAdViewSDK._resetForTesting() }

        let provider = StubConsentProvider(determined: false)
        #expect(!WebAdViewSDK.isInitialized)

        WebAdViewSDK.initialize(config: makeConfig(provider: provider))

        #expect(WebAdViewSDK.isInitialized)
        #expect(WebAdViewSDK.configuration?.consentProvider === provider)
        #expect(provider.startCalled)
        #expect(provider.onChange != nil) // the SDK registered its listener
    }

    @Test("A second initialize call is ignored (first configuration wins)")
    func secondInitializeIsIgnored() {
        WebAdViewSDK._resetForTesting()
        defer { WebAdViewSDK._resetForTesting() }

        let first = StubConsentProvider(determined: false)
        let second = StubConsentProvider(determined: false)

        WebAdViewSDK.initialize(config: makeConfig(provider: first))
        WebAdViewSDK.initialize(config: makeConfig(provider: second))

        #expect(WebAdViewSDK.configuration?.consentProvider === first)
        #expect(!second.startCalled) // the ignored config's provider is never started
    }

    @Test("The provider's onChange posts the consent notification on main")
    func onChangePostsConsentNotification() async throws {
        WebAdViewSDK._resetForTesting()
        defer { WebAdViewSDK._resetForTesting() }

        let provider = StubConsentProvider(determined: false)
        WebAdViewSDK.initialize(config: makeConfig(provider: provider))

        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .webAdViewConsentChanged, object: nil, queue: .main
        ) { _ in received = true }
        defer { NotificationCenter.default.removeObserver(observer) }

        provider.onChange?() // the CMP reports a change
        // The SDK re-dispatches to the main queue — give it a turn.
        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(received)
    }
}
