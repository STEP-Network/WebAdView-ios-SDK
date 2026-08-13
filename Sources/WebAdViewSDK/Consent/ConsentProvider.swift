import Foundation

/// Abstraction over the app's consent management platform (CMP).
///
/// The SDK supports two modes:
/// - **SDK-owned Didomi** (`DidomiConsentProvider`, the default): the SDK
///   initializes Didomi and shows its notice — today's standard integration.
/// - **App-owned CMP** (`TCFConsentProvider`): the app already runs its own
///   TCF-certified CMP (Didomi, Cookiebot, OneTrust, Usercentrics, …); the
///   SDK only reads the user's answer from the IAB TCF standard location.
///
/// Ads are held back until `isConsentDetermined` is true — the fail-closed
/// consent gate is the same in both modes.
public protocol ConsentProvider: AnyObject {
    /// Has the user answered a consent notice (any answer, accept or
    /// decline)? Ads never load while this is false.
    var isConsentDetermined: Bool { get }

    /// Begin observing the CMP. Call `onChange` when the CMP becomes ready
    /// and on every subsequent consent change (any thread — the SDK
    /// re-dispatches to the main queue). Called once from
    /// `WebAdViewSDK.initialize(config:)`.
    func start(onChange: @escaping () -> Void)

    /// JavaScript injected at document start into every ad webview, handing
    /// the native consent state to the page (so GPT/Yield Manager can read
    /// it in-page). Return an empty string to inject nothing.
    func javaScriptForWebView() -> String

    /// Present the CMP's preferences UI. Providers for app-owned CMPs may
    /// implement this as a logged no-op (the app opens its own CMP UI).
    func showPreferences()
}
