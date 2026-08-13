import Foundation
import Didomi

/// The default `ConsentProvider`: the SDK owns Didomi end to end —
/// initialization, the consent notice (via `DidomiWrapper`), change events,
/// and the native→web consent handoff. Behavior is identical to the SDK's
/// original built-in Didomi integration.
public final class DidomiConsentProvider: ConsentProvider {

    private let apiKey: String
    private let disableRemoteConfig: Bool

    public init(apiKey: String, disableRemoteConfig: Bool = false) {
        self.apiKey = apiKey
        self.disableRemoteConfig = disableRemoteConfig
    }

    public var isConsentDetermined: Bool {
        Didomi.shared.isReady() && !Didomi.shared.isUserStatusPartial()
    }

    public func start(onChange: @escaping () -> Void) {
        let parameters = DidomiInitializeParameters(
            apiKey: apiKey,
            disableDidomiRemoteConfig: disableRemoteConfig
        )
        Didomi.shared.initialize(parameters)

        Didomi.shared.onReady {
            debugPrint("[SN] [NATIVE] Didomi SDK is ready")
            // Readiness can flip the consent gate (stored consent from a
            // previous launch becomes readable) — treat it as a change.
            onChange()

            let didomiEventListener = EventListener()
            didomiEventListener.onConsentChanged = { _ in
                debugPrint("[SN] [NATIVE] Consent event received")
                onChange()
            }
            Didomi.shared.addEventListener(listener: didomiEventListener)
        }
    }

    public func javaScriptForWebView() -> String {
        Didomi.shared.getJavaScriptForWebView()
    }

    public func showPreferences() {
        Didomi.shared.showPreferences()
    }
}

/// `ConsentProvider` for apps that run **their own Didomi** (initialized by
/// the app, not the SDK). Didomi must come through the same Swift Package
/// the SDK uses — SPM then links one shared Didomi, so this provider can ask
/// it directly whether the user has actually answered the notice. That makes
/// the gate stricter than the generic `TCFConsentProvider`: a TC string that
/// some CMP configurations publish BEFORE the user answers does not open it.
///
/// The consent hand-off to the ad page uses the same `__tcfapi` stub as
/// `TCFConsentProvider` (own-CMP ad templates contain no consent code).
/// Fail-closed: if the app never initializes Didomi, ads never load.
public final class AppDidomiConsentProvider: ConsentProvider {

    private let tcf: TCFConsentProvider

    /// - Parameter defaults: injectable for tests; Didomi writes the TCF keys
    ///   to `UserDefaults.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.tcf = TCFConsentProvider(defaults: defaults)
    }

    public var isConsentDetermined: Bool {
        // Didomi's own "has the user answered?" — the reliable signal the
        // TCF standard location cannot provide.
        Didomi.shared.isReady() && !Didomi.shared.isUserStatusPartial()
    }

    public func start(onChange: @escaping () -> Void) {
        // TCF-key observation keeps the page hand-off snapshot fresh…
        tcf.start(onChange: onChange)
        // …and Didomi's own events flip the gate (readiness + every change).
        // Deliberately NOT calling Didomi.shared.initialize — the app owns it.
        Didomi.shared.onReady {
            debugPrint("[SN] [NATIVE] App-owned Didomi is ready")
            onChange()
            let listener = EventListener()
            listener.onConsentChanged = { _ in
                debugPrint("[SN] [NATIVE] App-owned Didomi consent event received")
                onChange()
            }
            Didomi.shared.addEventListener(listener: listener)
        }
    }

    public func javaScriptForWebView() -> String {
        tcf.javaScriptForWebView()
    }

    public func showPreferences() {
        Didomi.shared.showPreferences()
    }
}
