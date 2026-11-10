import UIKit
import WebAdViewCore

/// UIKit-level equivalent of the `WebAdView` SwiftUI view's webview part: a
/// plain `UIView` hosting one ad's webview, wired to a `WebAdScope`.
///
/// The host (Flutter platform view, UIKit cell) keeps this view at the FULL
/// ad frame it reports to the scope; the webview inside is resized to the
/// visible slice by the SDK (viewport resizing) so GPT ActiveView measures
/// honestly. Create it only once the scope reports `.fetched` for the ad
/// unit — never load ads into a view that is nowhere near the viewport.
///
/// Consent gating, template loading, bridge messages, remote thresholds and
/// external-URL handling are the unchanged `WebAdViewController` behaviour.
public final class WebAdHostView: UIView {

    public let adUnitId: String
    public private(set) weak var scope: WebAdScope?
    let controller: WebAdViewController

    /// The rendered creative's size (from the page's `adSize` message),
    /// unclamped — the host applies its own min/max constraints.
    public var onAdSizeChange: ((CGSize) -> Void)? {
        didSet { controller.onAdSizeChange = onAdSizeChange }
    }

    /// GPT Active View's `impressionViewable` verdict, with the slot id.
    public var onActiveViewImpression: ((String) -> Void)? {
        didSet { controller.onActiveViewImpression = onActiveViewImpression }
    }

    /// The last creative size the page reported, if any — a host that
    /// re-attaches a retained view sizes itself from this immediately.
    public var lastAdSize: CGSize? { controller.lastAdSize }

    /// - Parameters:
    ///   - adUnitId: the ad unit, registered with `scope` by the host.
    ///   - scope: the scroll container's scope (held weakly).
    ///   - customTargeting: GAM key/values (JSON-encoded into the page).
    ///   - viewportResizing: honest ActiveView measurement (default on).
    public convenience init(
        adUnitId: String,
        scope: WebAdScope,
        customTargeting: [String: [String]] = [:],
        viewportResizing: Bool = true,
        debugSettings: DebugSettings = .shared
    ) {
        self.init(
            adUnitId: adUnitId,
            scope: scope,
            customTargeting: customTargeting,
            viewportResizing: viewportResizing,
            debugSettings: debugSettings,
            consentProviderOverride: nil
        )
    }

    /// Internal seam: tests inject a consent provider instead of touching the
    /// process-wide `WebAdViewSDK.configuration`.
    init(
        adUnitId: String,
        scope: WebAdScope,
        customTargeting: [String: [String]],
        viewportResizing: Bool,
        debugSettings: DebugSettings,
        consentProviderOverride: ConsentProvider?
    ) {
        self.adUnitId = adUnitId
        self.scope = scope

        // Same source as the SwiftUI view: the template URL injected via
        // WebAdViewSDK.initialize(config:); a missing init warns loudly.
        let baseURL: String
        if let url = WebAdViewSDK.configuration?.adTemplateURL {
            baseURL = url.absoluteString
        } else {
            WebAdViewSDK.warnNotInitializedOnce()
            baseURL = ""
        }

        controller = WebAdViewController.make(
            adUnitId: adUnitId,
            baseURL: baseURL,
            customTargeting: customTargeting,
            viewportResizing: viewportResizing,
            debugSettings: debugSettings,
            manager: scope.manager,
            tracker: scope.tracker,
            onAdSizeChange: nil,
            onActiveViewImpression: nil
        )
        controller.consentProviderOverride = consentProviderOverride
        super.init(frame: .zero)

        // Loading the controller's view runs viewDidLoad → consent gate →
        // (if determined) template load — the same moment SwiftUI embeds it.
        let contentView = controller.view!
        contentView.frame = bounds
        contentView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("[SN] [NATIVE] WebAdHostView does not support init(coder:)")
    }

    /// Tears the webview down (the UIKit equivalent of SwiftUI dismantling
    /// the representable). Call when the host destroys this view.
    public func unload() {
        controller.unloadWebView()
    }
}
