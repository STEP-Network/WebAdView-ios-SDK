import Foundation
// Didomi's binary framework interface imports these system modules; importing
// them here puts them in the module graph of every consumer, so apps linking
// WebAdViewSDK don't hit "missing required modules: JavaScriptCore,
// SystemConfiguration" under Xcode's explicit-modules build.
@_implementationOnly import JavaScriptCore
@_implementationOnly import SystemConfiguration
import Didomi
import WebAdViewCore

// MARK: - Notification
public extension Notification.Name {
    /// Posted on the main queue whenever the user's consent status changes.
    /// WebAdViews observe this to (re)load ad content.
    static let webAdViewConsentChanged = Notification.Name("sn.webadview.consentChanged")
}

// MARK: - WebAdViewSDKConfig
/// App-level configuration for the WebAdView SDK. All previously hardcoded
/// values (Didomi API key, ad template URL) are injected here.
public struct WebAdViewSDKConfig {
    /// The consent source gating every ad load (see `ConsentProvider`).
    public let consentProvider: ConsentProvider
    /// The ad template page loaded into every ad webview — your own template,
    /// hosted on your domain, built to the bridge contract
    /// (`Documentation/bridge-contract.md`). Provided during STEP Network
    /// onboarding, like the Didomi key.
    public var adTemplateURL: URL

    /// Standard integration: the SDK owns Didomi (initialization, notice,
    /// consent handoff). `didomiAPIKey` is a secret — inject it, don't
    /// commit it.
    public init(
        didomiAPIKey: String,
        adTemplateURL: URL,
        didomiDisableRemoteConfig: Bool = false
    ) {
        self.consentProvider = DidomiConsentProvider(
            apiKey: didomiAPIKey,
            disableRemoteConfig: didomiDisableRemoteConfig
        )
        self.adTemplateURL = adTemplateURL
    }

    /// Bring-your-own-CMP integration: the app already runs a consent
    /// platform and supplies a provider for it (typically
    /// `TCFConsentProvider()` for any TCF-certified CMP). The SDK shows no
    /// consent UI in this mode. See GUIDE.md "Bringing your own CMP".
    public init(
        consentProvider: ConsentProvider,
        adTemplateURL: URL
    ) {
        self.consentProvider = consentProvider
        self.adTemplateURL = adTemplateURL
    }
}

// MARK: - WebAdViewSDK
/// SDK entry point. Call `initialize(config:)` once at app launch (e.g. in
/// `application(_:didFinishLaunchingWithOptions:)`) before any WebAdView is
/// created.
public enum WebAdViewSDK {

    public private(set) static var configuration: WebAdViewSDKConfig?

    public static var isInitialized: Bool { configuration != nil }

    private static var didWarnNotInitialized = false

    /// Integrator-error diagnostic: prints UNCONDITIONALLY (not debug-gated),
    /// once, when SDK APIs are used before `initialize(config:)`. Without
    /// this, missing initialization degrades to silently blank ad slots.
    static func warnNotInitializedOnce() {
        guard configuration == nil, !didWarnNotInitialized else { return }
        didWarnNotInitialized = true
        print("""
        [SN] [ERROR] WebAdViewSDK.initialize(config:) was never called — Didomi \
        is not set up and ads cannot load. Call WebAdViewSDK.initialize(config:) \
        at app launch (see GUIDE.md).
        """)
    }

    /// Initializes Didomi with the injected API key and installs the global
    /// consent-change listener that drives ad (re)loading.
    public static func initialize(config: WebAdViewSDKConfig) {
        guard configuration == nil else {
            debugPrint("[SN] [NATIVE] WebAdViewSDK.initialize called more than once — ignoring")
            return
        }
        configuration = config

        // The provider reports readiness and every consent change; held-back
        // WebAdViews observe this notification and re-check the gate.
        config.consentProvider.start {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .webAdViewConsentChanged, object: nil)
            }
        }
    }

    /// Presents the consent preferences UI so users can change their choices
    /// at any time. With the default Didomi provider a `DidomiWrapper` must
    /// be in the view hierarchy; with an app-owned CMP this is a logged
    /// no-op (open that CMP's UI from the app instead).
    public static func showConsentPreferences() {
        configuration?.consentProvider.showPreferences()
    }

    #if DEBUG
    /// TEST ONLY — clears the global configuration so the test suite can
    /// exercise `initialize(config:)` in isolation. Internal on purpose:
    /// consumers must never be able to de-initialize the SDK at runtime.
    static func _resetForTesting() {
        configuration = nil
        didWarnNotInitialized = false
    }
    #endif

    #if DEBUG
    /// TEST AUTOMATION ONLY — programmatically grants full consent via the
    /// official Didomi API, for automated simulator runs where a fresh
    /// install has wiped stored consent and no notice UI is available.
    /// Compiled out of release builds entirely. Consent must always come
    /// from the user in production flows. Deliberately Didomi-direct (not on
    /// `ConsentProvider`): it exists solely for the demo app's simulator
    /// automation, which always runs the Didomi provider.
    public static func acceptAllConsentForTesting() {
        Didomi.shared.onReady {
            _ = Didomi.shared.setUserAgreeToAll()
        }
    }
    #endif
}
