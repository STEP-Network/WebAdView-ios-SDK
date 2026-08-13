import SwiftUI
import WebKit
import WebAdViewCore

import Combine // NEW: Import Combine

// AdLoadState now lives in WebAdViewCore.

// NEW: Define environment key for the LazyLoadingManager
struct AdVisibilityManagerKey: EnvironmentKey {
    static let defaultValue: LazyLoadingManager? = nil // LazyLoadingManager will be defined in a separate file
}

extension EnvironmentValues {
    var adVisibilityManager: LazyLoadingManager? {
        get { self[AdVisibilityManagerKey.self] }
        set { self[AdVisibilityManagerKey.self] = newValue }
    }
}

// NEW: Define environment key for the ViewabilityTracker
struct ViewabilityTrackerKey: EnvironmentKey {
    static let defaultValue: ViewabilityTracker? = nil
}

extension EnvironmentValues {
    var viewabilityTracker: ViewabilityTracker? {
        get { self[ViewabilityTrackerKey.self] }
        set { self[ViewabilityTrackerKey.self] = newValue }
    }
}

// NEW: Helper for Publishers (needed for .onReceive with optional manager)
extension Publisher {
    static func empty() -> AnyPublisher<Output, Failure> {
        Empty().eraseToAnyPublisher()
    }
}

// MARK: - Preference Keys for Geometry Tracking (Moved here from previous LazyLoadAdModifier.swift)
struct AdFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { (_, new) in new }
    }
}

struct ScrollViewBoundsPreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Frame of the ad CREATIVE only (excludes the "annonce" label), used for
/// viewability measurement. Lazy loading keeps using AdFramePreferenceKey,
/// which wraps the whole VStack including the label.
struct AdContentFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { (_, new) in new }
    }
}

//MARK: WebAdView
public struct WebAdView: View {
    // The ad template URL is injected via WebAdViewSDK.initialize(config:).
    private var baseURL: String {
        guard let url = WebAdViewSDK.configuration?.adTemplateURL else {
            WebAdViewSDK.warnNotInitializedOnce()
            return ""
        }
        return url.absoluteString
    }
    let adUnitId: String
    @Environment(\.snDebugSettings) var debugSettings

    //MARK: Ad label properties
    var showAdLabel: Bool = false
    var adLabelText: String = "annonce"
    var adLabelFont: Font = .system(size: 10, weight: .bold)

    //MARK: Custom targeting properties
    private var customTargetingParams: [String: [String]] = [:]

    // Dynamic ad size state
    @State private var adSize: CGSize

    // Initial and constraint properties
    var initialWidth: CGFloat
    var initialHeight: CGFloat
    var minWidth: CGFloat?
    var maxWidth: CGFloat?
    var minHeight: CGFloat?
    var maxHeight: CGFloat?

    // NEW: Environment variable for lazy loading manager
    @Environment(\.adVisibilityManager) var adVisibilityManager
    // NEW: Internal state for ad loading, managed by the AdVisibilityManager
    @State private var loadState: AdLoadState = .notLoaded

    //MARK: Viewability properties
    @Environment(\.viewabilityTracker) var viewabilityTracker
    var onViewabilityChange: ((ViewabilityUpdate) -> Void)?
    var onActiveViewImpression: ((String) -> Void)?
    // Module-6: resize the webview's viewport to the visible slice so GPT
    // ActiveView measures honestly. ON by default (IAB/MRC-correct);
    // `.viewportResizing(false)` opts a single ad out.
    var viewportResizingEnabled: Bool = true

    /// Initializes a new instance of the WebAdView with the specified configuration.
    /// - Parameters:
    ///   - adUnitId: The unique identifier for the ad unit.
    ///   - showAdLabel: A boolean indicating whether to show an ad label. Defaults to `false`.
    ///   - adLabelText: The text for the ad label. Defaults to "annonce".
    ///   - adLabelFont: The font for the ad label. Defaults to `.system(size: 10, weight: .bold)`.
    ///   - initialWidth: The initial width of the ad view.
    ///   - initialHeight: The initial height of the ad view.
    ///   - minWidth: The minimum width constraint for the ad view.
    ///   - maxWidth: The maximum width constraint for the ad view.
    ///   - minHeight: The minimum height constraint for the ad view.
    ///   - maxHeight: The maximum height constraint for the ad view.
    public init(
        adUnitId: String,
        showAdLabel: Bool = false,
        adLabelText: String = "annonce",
        adLabelFont: Font = .system(size: 10, weight: .bold),
        initialWidth: CGFloat = 320,
        initialHeight: CGFloat = 320,
        minWidth: CGFloat? = nil,
        maxWidth: CGFloat? = nil,
        minHeight: CGFloat? = nil,
        maxHeight: CGFloat? = nil
    ) {
        self.adUnitId = adUnitId
        self.showAdLabel = showAdLabel
        self.adLabelText = adLabelText
        self.adLabelFont = adLabelFont
        self.initialWidth = initialWidth
        self.initialHeight = initialHeight
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.minHeight = minHeight
        self.maxHeight = maxHeight
        _adSize = State(initialValue: CGSize(width: initialWidth, height: initialHeight))
    }

    // MARK: - Ad Label Modifier
    public func showAdLabel(_ show: Bool = true, text: String = "annonce", font: Font = .system(size: 10, weight: .bold)) -> WebAdView {
        var copy = self
        copy.showAdLabel = show
        copy.adLabelText = text
        copy.adLabelFont = font
        return copy
    }

    // MARK: - Custom Targeting Modifiers
    /// Sets a single custom targeting parameter for Google Ad Manager
    /// - Parameters:
    ///   - key: The targeting key
    ///   - value: The targeting value (single string)
    public func customTargeting(_ key: String, _ value: String) -> WebAdView {
        var copy = self
        copy.customTargetingParams[key] = [value]
        return copy
    }

    /// Sets a custom targeting parameter with multiple values for Google Ad Manager
    /// - Parameters:
    ///   - key: The targeting key
    ///   - values: The targeting values (array of strings)
    public func customTargeting(_ key: String, _ values: [String]) -> WebAdView {
        var copy = self
        if values.isEmpty {
            debugPrint("[SN] [NATIVE] Custom Targeting: Empty array provided for key '\(key)'")
            return copy
        }
        copy.customTargetingParams[key] = values
        return copy
    }

    // MARK: - Viewability Modifiers
    // Native measurement always uses the IAB/MRC display standard (≥50% for
    // 1s, geometry-based). There is deliberately no public video-mode knob:
    // creatives are chosen remotely at serve time, so an app developer cannot
    // know the media type — and Google's ActiveView applies the correct
    // per-creative standard (incl. 2s-while-playing for video) inside the
    // webview automatically. WebAdViewCore's `ViewabilityMode.video` remains
    // for a future playback-aware product.

    /// Registers a callback invoked on every viewability measurement update.
    /// Check `update.becameViewable` for the moment the impression latches.
    public func onViewabilityChange(_ handler: @escaping (ViewabilityUpdate) -> Void) -> WebAdView {
        var copy = self
        copy.onViewabilityChange = handler
        return copy
    }

    /// Invoked when GPT Active View declares this impression viewable (the
    /// `impressionViewable` GPT.js ad event), with the GPT slot element id.
    /// This is Google's own verdict — the signal GAM reporting is built on.
    /// - Note: reflects true on-screen exposure by default (viewport resizing
    ///   is on). If an ad opted out via `.viewportResizing(false)`, ActiveView
    ///   sees an ad filling its own webview (~100% visible) and fires shortly
    ///   after render regardless of the ad's real position. The native
    ///   `.onViewabilityChange` signal is authoritative either way.
    public func onActiveViewImpression(_ handler: @escaping (String) -> Void) -> WebAdView {
        var copy = self
        copy.onActiveViewImpression = handler
        return copy
    }

    /// Module-6: dynamically resizes the ad webview to the visible slice of
    /// the creative so in-page measurement (GPT ActiveView) sees the true
    /// viewport instead of an always-full one. Applied only after the
    /// creative has rendered; the SwiftUI layout keeps the full ad size, so
    /// nothing shifts visually. ON by default so every ad measures honestly
    /// per IAB/MRC — pass `false` to opt a single ad out (coordinate with
    /// STEP Network; its ActiveView numbers will read ~100% regardless of
    /// real visibility).
    public func viewportResizing(_ enabled: Bool = true) -> WebAdView {
        var copy = self
        copy.viewportResizingEnabled = enabled
        return copy
    }

    public var body: some View {
        VStack(spacing: 0) {
            if showAdLabel {
                Text(adLabelText)
                    .font(adLabelFont)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 5)
            }
            // Only render WebViewRepresentable if loadState indicates it should exist
            Group {
                if loadState != .notLoaded && loadState != .unloaded {
                    WebViewRepresentable(
                        adUnitId: adUnitId,
                        baseURL: baseURL,
                        customTargetingParams: customTargetingParams,
                        viewportResizingEnabled: viewportResizingEnabled,
                        onAdSizeChange: { size in
                            let clampedWidth = min(max(size.width, minWidth ?? size.width), maxWidth ?? size.width)
                            let clampedHeight = min(max(size.height, minHeight ?? size.height), maxHeight ?? size.height)
                            withAnimation(.easeInOut(duration: 0.2)) {
                                self.adSize = CGSize(width: clampedWidth, height: clampedHeight)
                            }
                        },
                        onActiveViewImpression: onActiveViewImpression
                    )
                    .environment(\.snDebugSettings, debugSettings)
                    .frame(
                        width: adSize.width,
                        height: adSize.height
                    )
                } else {
                    // Placeholder when not loaded or unloaded
                    Color.clear
                        .frame(width: initialWidth, height: initialHeight)
                }
            }
            // Report the CREATIVE's frame (label excluded) for viewability measurement
            .background(
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: AdContentFramePreferenceKey.self,
                        value: [adUnitId: geometry.frame(in: .global)]
                    )
                }
            )
        }
        .id(adUnitId) // Use adUnitId as stable ID for individual ad units
        // Register this ad unit with the viewability tracker
        .onAppear {
            viewabilityTracker?.register(adUnitId, mode: .display)
        }
        // Forward viewability updates to the consumer's callback
        .onReceive(viewabilityTracker?.updates(for: adUnitId) ?? .empty()) { update in
            onViewabilityChange?(update)
        }
        // Observe adUnitId's state from the manager via onReceive
        .onReceive(adVisibilityManager?.adStatesPublisher(for: adUnitId) ?? .empty()) { newState in
            debugPrint("[SN] [LLM] WebAdView \(adUnitId): Received new state from manager: \(newState.rawValue)")
            self.loadState = newState // Update internal state based on manager
        }
        .background(
            // Report own frame up to the manager using a GeometryReader and PreferenceKey
            GeometryReader { geometry in
                Color.clear.preference(
                    key: AdFramePreferenceKey.self,
                    value: [adUnitId: geometry.frame(in: .global)]
                )
            }
        )
    }

}

// MARK: - Internal UIViewControllerRepresentable
private struct WebViewRepresentable: UIViewControllerRepresentable {
    let adUnitId: String
    let baseURL: String
    let customTargetingParams: [String: [String]]
    var viewportResizingEnabled: Bool = false
    var onAdSizeChange: ((CGSize) -> Void)?
    var onActiveViewImpression: ((String) -> Void)?
    @Environment(\.snDebugSettings) var debugSettings
    @Environment(\.adVisibilityManager) private var adVisibilityManager
    @Environment(\.viewabilityTracker) private var viewabilityTracker

    func makeUIViewController(context: Context) -> WebAdViewController {
        let controller = WebAdViewController(
            baseURL: baseURL,
            adUnitId: adUnitId,
            debugSettings: debugSettings,
            customTargetingParams: customTargetingParams
        )
        controller.onAdSizeChange = onAdSizeChange
        controller.onActiveViewImpression = onActiveViewImpression
        let id = ObjectIdentifier(controller).hashValue
        debugPrint("[SN] [LLM] WebAdView.makeUIViewController: Created controller [\(id)] with adUnitId: \(adUnitId)")

        // Set up lazy loading state observation
        if let manager = adVisibilityManager {
            controller.setupLazyLoadingObserver(manager: manager)
        }

        // New webview = new impression: subscribe FIRST, then re-arm — the
        // subjects don't replay, so subscribing after resetImpression would
        // drop the first post-reset snapshot.
        if let tracker = viewabilityTracker {
            controller.setupViewabilityObserver(tracker: tracker)
            // Module-6: drive the webview's viewport from the visible slice
            if viewportResizingEnabled {
                controller.viewportResizingEnabled = true
                controller.setupViewportClipObserver(tracker: tracker)
            }
            tracker.resetImpression(adUnitId)
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: WebAdViewController, context: Context) {
        // No-op for static URL
    }

    static func dismantleUIViewController(_ uiViewController: WebAdViewController, coordinator: ()) {
        let id = ObjectIdentifier(uiViewController).hashValue
        debugPrint("[SN] [LLM] WebAdView.dismantleUIViewController: Dismantling controller [\(id)]")
        uiViewController.unloadWebView()
    }
}

// Move extension View and LazyLoadAdInternalModifier to file scope
public extension View {
    /// Applies lazy loading behavior to a ScrollView's content with default thresholds.
    /// - Parameters:
    ///   - enabled: Whether to enable lazy loading behavior. When true, uses default thresholds.
    ///   - unloadingEnabled: Whether ads should be unloaded when out of view. Defaults to false for better UX.
    func lazyLoadAd(_ enabled: Bool = true, unloadingEnabled: Bool = false) -> some View {
        Group {
            if enabled {
                self.modifier(LazyLoadAdInternalModifier(fetchThreshold: 800, displayThreshold: 200, unloadThreshold: 1600, unloadingEnabled: unloadingEnabled))
            } else {
                self
            }
        }
    }
    
    /// Applies lazy loading behavior to a ScrollView's content, managing the lifecycle of contained WebAdViews.
    /// - Parameters:
    ///   - fetchThreshold: Distance from the screen edge (in points) when an ad should start fetching content.
    ///   - displayThreshold: Distance from the screen edge (in points) when an ad should fully display.
    ///   - unloadThreshold: Distance from the screen edge (in points) when an ad should unload (deallocate) to save resources.
    ///   - unloadingEnabled: Whether ads should be unloaded when out of view. Defaults to false for better UX.
    func lazyLoadAd(fetchThreshold: CGFloat, displayThreshold: CGFloat, unloadThreshold: CGFloat, unloadingEnabled: Bool = false) -> some View {
        self.modifier(LazyLoadAdInternalModifier(fetchThreshold: fetchThreshold, displayThreshold: displayThreshold, unloadThreshold: unloadThreshold, unloadingEnabled: unloadingEnabled))
    }
}

private struct LazyLoadAdInternalModifier: ViewModifier {
    @StateObject private var manager: LazyLoadingManager // Manager instance for this ScrollView
    @StateObject private var viewabilityTracker = ViewabilityTracker() // Viewability measurement for this ScrollView

    let fetchThreshold: CGFloat
    let displayThreshold: CGFloat
    let unloadThreshold: CGFloat
    let unloadingEnabled: Bool

    init(fetchThreshold: CGFloat, displayThreshold: CGFloat, unloadThreshold: CGFloat, unloadingEnabled: Bool = false) {
        self.fetchThreshold = fetchThreshold
        self.displayThreshold = displayThreshold
        self.unloadThreshold = unloadThreshold
        self.unloadingEnabled = unloadingEnabled
        _manager = StateObject(wrappedValue: LazyLoadingManager())
    }

    func body(content: Content) -> some View {
        content
            // Capture ScrollView bounds using a GeometryReader as an overlay
            .overlay(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: ScrollViewBoundsPreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            )
            // Observe preferences and update manager
            .onPreferenceChange(ScrollViewBoundsPreferenceKey.self) { bounds in
                manager.updateScrollViewBounds(bounds)
                viewabilityTracker.updateScrollViewBounds(bounds)
            }
            .onPreferenceChange(AdFramePreferenceKey.self) { frames in
                // Iterate through reported frames and update manager
                for (adId, frame) in frames {
                    manager.updateAdFrame(adId, frame: frame)
                }
            }
            // Feed the creative-only frames to the viewability tracker
            .onPreferenceChange(AdContentFramePreferenceKey.self) { frames in
                for (adId, frame) in frames {
                    viewabilityTracker.updateContentFrame(adId, frame: frame)
                }
            }
            // Inject the manager into the environment for WebAdViews
            .environment(\.adVisibilityManager, manager)
            // Inject the viewability tracker into the environment for WebAdViews
            .environment(\.viewabilityTracker, viewabilityTracker)
            .onAppear { 
                manager.fetchThreshold = fetchThreshold
                manager.displayThreshold = displayThreshold
                manager.unloadThreshold = unloadThreshold
                manager.unloadingEnabled = unloadingEnabled
                // STEP Network's remote per-domain thresholds override the
                // values above (cached from a previous read-back; fresh values
                // are applied live once a page reports them).
                if let host = WebAdViewSDK.configuration?.adTemplateURL.host,
                   let cached = RemoteLazyLoadStore().load(forHost: host) {
                    manager.applyRemote(cached)
                }
                // Force initial check in case ads are immediately visible
                manager.updateScrollViewBounds(manager.scrollViewBounds)
                manager.adUnitFrames.forEach { manager.updateAdFrame($0.key, frame: $0.value) }
            }
    }
}

//MARK: WebAdViewController
class WebAdViewController: UIViewController, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    
    //MARK: Callback for ad size changes
    var onAdSizeChange: ((CGSize) -> Void)?
    //MARK: Callback when GPT Active View declares the impression viewable
    var onActiveViewImpression: ((String) -> Void)?
    private let baseURL: String
    private let adUnitId: String
    private var debugSettings: DebugSettings
    private let customTargetingParams: [String: [String]]
    var webView: WKWebView!
    private(set) var hasLoadedContent = false
    private var initialURL: URL?
    
    // NEW: Lazy loading state observation
    private var lazyLoadingCancellable: AnyCancellable?
    // NEW: Viewability updates forwarded into the webview
    private var viewabilityCancellable: AnyCancellable?
    // Weak: the tracker is owned by the ScrollView (@StateObject). Held so a
    // consent-holdback load can re-arm the impression (see loadAdContent).
    private weak var viewabilityTrackerRef: ViewabilityTracker?
    // Weak: the manager is owned by the ScrollView (@StateObject). Held so the
    // remote lazy-load config read back from the page can be applied to it.
    private weak var lazyLoadingManagerRef: LazyLoadingManager?
    // Remote lazy-load read-back (window.stepnetwork.lazyLoad)
    var remoteLazyLoadStore = RemoteLazyLoadStore()
    private var remoteConfigPollAttempts = 0
    // Consent snapshot delivered to the loaded page (reload trigger compares
    // against it) + one-shot render re-trigger after a consent-driven reload.
    private var loadedConsentJS: String?
    private var pendingRenderAfterReload = false
    // Consent observer token (block-based; must be removed explicitly)
    private var consentObserver: NSObjectProtocol?
    // Module-6: viewport resizing (honest ActiveView measurement)
    var viewportResizingEnabled = false
    private var viewportClipCancellable: AnyCancellable?
    private var hasRenderedAd = false
    private var pendingClip: ViewportClipCalculator.Clip?
    // Clip-log throttle state (logging only — never affects applied clips)
    private var lastLoggedClipRegime: String?

    init(baseURL: String, adUnitId: String, debugSettings: DebugSettings, customTargetingParams: [String: [String]] = [:]) {
        self.baseURL = baseURL
        self.adUnitId = adUnitId
        self.debugSettings = debugSettings
        self.customTargetingParams = customTargetingParams
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("[SN] [NATIVE] init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupWebView()
        checkConsentAndLoad()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Module-6: once clipping has started, autoresizing is off — re-apply
        // the latest clip so a container resize (e.g. creative size change)
        // can't leave the webview at a stale frame.
        if viewportResizingEnabled, hasRenderedAd, let clip = pendingClip {
            applyViewportClip(clip)
        }
    }
    
    // MARK: Setup Lazy Loading Observer
    func setupLazyLoadingObserver(manager: LazyLoadingManager) {
        lazyLoadingManagerRef = manager
        lazyLoadingCancellable = manager.adStatesPublisher(for: adUnitId)
            .sink { [weak self] newState in
                guard let self = self else { return }
                debugPrint("[SN] [LLM] WebAdViewController[\(ObjectIdentifier(self).hashValue)]: Received state change to \(newState.rawValue) for \(self.adUnitId)")
                
                // Trigger ad rendering when state becomes .displayed
                if newState == .displayed && self.hasLoadedContent {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.triggerAdRendering()
                    }
                }
            }
        
        // Check if the ad is already in displayed state and trigger immediately
        if let currentState = manager.adStates[adUnitId], currentState == .displayed && hasLoadedContent {
            debugPrint("[SN] [LLM] WebAdViewController[\(ObjectIdentifier(self).hashValue)]: Ad already in displayed state, triggering immediately")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.triggerAdRendering()
            }
        }
    }

    // MARK: Setup Viewability Observer
    /// Subscribes to the tracker's rate-limited JS stream and forwards each
    /// update into the page via window.stepnetwork._onViewability.
    func setupViewabilityObserver(tracker: ViewabilityTracker) {
        viewabilityTrackerRef = tracker
        viewabilityCancellable = tracker.jsUpdates(for: adUnitId)
            .sink { [weak self] update in
                self?.sendViewability(update)
            }
    }

    // MARK: Module-6 — Viewport Resizing (honest ActiveView)
    /// Subscribes to the tracker's clip stream. Applied clips resize the
    /// webview to the creative's visible slice so in-page measurement sees
    /// the true viewport.
    func setupViewportClipObserver(tracker: ViewabilityTracker) {
        viewportClipCancellable = tracker.clipUpdates(for: adUnitId)
            .sink { [weak self] clip in
                self?.applyViewportClip(clip)
            }
    }

    func applyViewportClip(_ clip: ViewportClipCalculator.Clip) {
        guard viewportResizingEnabled else { return }
        // Always remember the latest clip, even before the webview exists —
        // for an ad that loads below the fold and never moves, the ONLY clip
        // emission happens before view load, and it must survive until the
        // first adSize applies it.
        pendingClip = clip
        // Never clip before the creative has rendered: GPT must not request
        // ads into a 1pt viewport, and the initial layout must settle first.
        guard let webView = webView, hasRenderedAd else { return }

        let targetFrame: CGRect
        let targetOffset: CGPoint
        if clip.isFullyVisible {
            targetFrame = view.bounds
            targetOffset = .zero
        } else if clip.isFullyHidden {
            // Keep a 1pt sliver alive (a zero frame can suspend media/JS).
            targetFrame = CGRect(x: 0, y: 0, width: view.bounds.width, height: 1)
            targetOffset = .zero
        } else {
            // Slice in ad-local coords == frame within the container. The page
            // content is shifted by the same origin so the creative's pixels
            // don't visually move (programmatic contentOffset works with user
            // scrolling disabled).
            let slice = clip.sliceFrame
            targetFrame = CGRect(
                x: slice.minX,
                y: slice.minY,
                width: max(slice.width, 1),
                height: max(slice.height, 1)
            )
            targetOffset = clip.contentOffset
        }

        // Idempotence: viewDidLayoutSubviews re-applies the latest clip after
        // every layout pass — including the pass this very method triggers by
        // resizing the webview. When the webview already matches, don't
        // re-set or re-log (previously every clip printed twice).
        if webView.frame.isNearlyEqual(to: targetFrame),
           webView.scrollView.contentOffset.isNearlyEqual(to: targetOffset) {
            return
        }

        // The container (self.view) keeps the full ad frame — SwiftUI layout
        // stays stable; only the webview inside it is resized/positioned.
        webView.autoresizingMask = []
        webView.frame = targetFrame
        webView.scrollView.contentOffset = targetOffset
        logClipStepIfMeaningful(clip, appliedFrame: targetFrame, appliedOffset: targetOffset)
    }

    /// Debug narrative for clipping without the point-by-point noise: one
    /// line per regime TRANSITION (full / partial / sliver) only. The
    /// intermediate sizes add nothing the GPT visibility lines don't prove,
    /// and the clip itself is applied at full fidelity regardless — this
    /// throttles ONLY the log line.
    private func logClipStepIfMeaningful(_ clip: ViewportClipCalculator.Clip,
                                         appliedFrame: CGRect,
                                         appliedOffset: CGPoint) {
        let regime = clip.isFullyVisible ? "full" : clip.isFullyHidden ? "sliver" : "partial"
        guard regime != lastLoggedClipRegime else { return }
        lastLoggedClipRegime = regime
        debugPrint("[SN] [CLIP] \(adUnitId): webview viewport -> \(Int(appliedFrame.width))x\(Int(appliedFrame.height)) (offset y: \(Int(appliedOffset.y)), \(regime))")
    }

    private func sendViewability(_ update: ViewabilityUpdate) {
        guard hasLoadedContent, let webView = webView else { return }
        guard let json = ViewabilityPayload(update: update).jsonString() else {
            debugPrint("[SN] [VIEWABILITY] WebAdViewController: Failed to encode viewability payload for \(adUnitId)")
            return
        }
        // json is JSONEncoder output — safe to splice as a JS object literal.
        let js = "window.stepnetwork && window.stepnetwork._onViewability && window.stepnetwork._onViewability(\(json));"
        webView.evaluateJavaScript(js) { _, error in
            if let error = error {
                debugPrint("[SN] [VIEWABILITY] WebAdViewController: Error sending viewability to JS:", error)
            }
        }
    }

    //MARK: Consent holdback
    // Test seam: WebAdViewSDK.configuration is process-wide shared state, so
    // tests inject a provider here instead of mutating the global. Production
    // paths leave it nil.
    var consentProviderOverride: ConsentProvider?

    private var effectiveConsentProvider: ConsentProvider? {
        consentProviderOverride ?? WebAdViewSDK.configuration?.consentProvider
    }

    private var isConsentDetermined: Bool {
        effectiveConsentProvider?.isConsentDetermined == true
    }

    private func checkConsentAndLoad() {
        // First check if consent is already determined (fail-closed: no
        // configuration → no load; the not-initialized warning fires later)
        if isConsentDetermined && !self.hasLoadedContent {
            self.loadAdContent()
            debugPrint("[SN] [NATIVE] WebAdViewController: Consent already given, loading WebAdViews")
        }

        // Listen for consent events (the provider reports readiness and every
        // change through this notification). Block-based observers return a
        // token that MUST be stored and removed explicitly —
        // removeObserver(self) does not remove them, which previously leaked
        // one observer per controller.
        consentObserver = NotificationCenter.default.addObserver(
            forName: .webAdViewConsentChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isConsentDetermined else { return }
            if !self.hasLoadedContent {
                self.loadAdContent()
                debugPrint("[SN] [NATIVE] WebAdViewController: Consent changed")
            } else if let currentJS = self.effectiveConsentProvider?.javaScriptForWebView(),
                      currentJS != self.loadedConsentJS {
                // The user changed their answer AFTER this ad loaded. The page
                // got its consent as a one-time snapshot at load, so in-page
                // requests/refreshes would keep running under the old answer —
                // reload so the new consent applies immediately. Providers also
                // fire this notification on readiness right after the initial
                // load; the snapshot comparison keeps those from reloading.
                debugPrint("[SN] [NATIVE] WebAdViewController: Consent changed after load — reloading \(self.adUnitId) with the new consent")
                self.reloadAdContent()
            }
        }
    }

    /// Tears the loaded ad page down and loads it again with the CURRENT
    /// consent state. All user scripts are removed first: the old consent
    /// snapshot must not survive (nor accumulate) across reloads.
    private func reloadAdContent() {
        guard hasLoadedContent, let webView = webView else { return }
        webView.stopLoading()
        webView.configuration.userContentController.removeAllUserScripts()
        hasLoadedContent = false
        // The old creative is gone: clipping must wait for the new one
        // (never load ads into a collapsed viewport), and an already-displayed
        // ad gets no new lazy-load transition — re-trigger rendering once the
        // fresh page has finished loading.
        hasRenderedAd = false
        if lazyLoadingManagerRef?.adStates[adUnitId] == .displayed {
            pendingRenderAfterReload = true
        }
        loadAdContent()
    }

    deinit {
        let id = ObjectIdentifier(self).hashValue
        debugPrint("[SN] [LLM] WebAdViewController[\(id)]: deinit called")
        // Remove the block-based consent observer via its token
        if let consentObserver = consentObserver {
            NotificationCenter.default.removeObserver(consentObserver)
        }
        // Cancel lazy loading subscription
        lazyLoadingCancellable?.cancel()
        // Cancel viewability subscription
        viewabilityCancellable?.cancel()
        // Cancel viewport clip subscription
        viewportClipCancellable?.cancel()
    }
    //MARK: Unload WebView
    func unloadWebView() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        let id = ObjectIdentifier(self).hashValue
        debugPrint("[SN] [LLM] WebAdViewController[\(id)]: Unloaded WebView")
    }
    //MARK: Setup WebView
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        // Add user content controller and register JS bridge handler
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "nativeBridge")
        config.userContentController = userContentController

        webView = WKWebView(frame: view.bounds, configuration: config)
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        // Disable scrolling in the webview so the ad is never scrollable inside the webview
        webView.scrollView.isScrollEnabled = false

        // Set delegates for click handling
        webView.uiDelegate = self
        webView.navigationDelegate = self

        view.addSubview(webView)
        debugPrint("[SN] [NATIVE] WebAdViewController: WebView setup")
    }

    // MARK: HTML WKScriptMessageHandler - JS Bridge
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handleBridgeMessage(message.body)
    }

    // Separate from the WKScriptMessageHandler entry point so bridge parsing
    // is unit-testable (WKScriptMessage cannot be constructed in tests).
    // Message bodies come from the ad webview — treat every field as untrusted.
    func handleBridgeMessage(_ body: Any) {
        if let dict = body as? [String: Any], let type = dict["type"] as? String {
            if type == "console" {
                let level = dict["level"] as? String ?? "log"
                let msg = dict["message"] as? String ?? ""
                debugPrint("[SN] [WebAdView] [HTML] [\(level.uppercased())] \(msg)")
            } else if type == "adSize" {
                if let width = dict["width"] as? CGFloat, let height = dict["height"] as? CGFloat {
                    debugPrint("[SN] [WebAdView] [HTML] [adSize] width: \(width), height: \(height)")
                    onAdSizeChange?(CGSize(width: width, height: height))
                    // Module-6: the creative has rendered — viewport clipping
                    // may start (apply the most recent pending clip once the
                    // container has adopted the new size).
                    if !hasRenderedAd {
                        hasRenderedAd = true
                        if viewportResizingEnabled, let pending = pendingClip {
                            DispatchQueue.main.async { [weak self] in
                                self?.applyViewportClip(pending)
                            }
                        }
                    }
                }
            } else if type == "impressionViewable" {
                let slotId = dict["slotId"] as? String ?? "unknown"
                debugPrint("[SN] [VIEWABILITY] [ACTIVEVIEW] \(slotId): impressionViewable — Google counted a viewable impression")
                onActiveViewImpression?(slotId)
            } else if type == "slotVisibilityChanged" {
                // Debug-only diagnostic (the emitting script is injected only
                // in debug mode): GPT's self-reported visible percentage.
                let slotId = dict["slotId"] as? String ?? "unknown"
                if let percent = dict["visiblePercent"] as? Double {
                    debugPrint("[SN] [VIEWABILITY] [ACTIVEVIEW] \(slotId): GPT reports \(Int(percent))% visible")
                }
            } else {
                debugPrint("[SN] [WebAdView] [HTML] [Unknown type]", dict)
            }
        } else {
            debugPrint("[SN] [WebAdView] [HTML] ", body)
        }
    }

    // MARK: Native → Web Communication
    func sendJavaScript(_ js: String) {
        webView?.evaluateJavaScript(js) { result, error in
            if let error = error {
                debugPrint("[SN] [WebAdView] [NATIVE] Error:", error)
            } else {
                debugPrint("[SN] [WebAdView] [NATIVE] JS Result:", result ?? "nil")
            }
        }
    }

    // MARK: Trigger Ad Rendering with LL
    func triggerAdRendering() {
        guard let webView = webView else {
            debugPrint("[SN] [LLM] WebAdViewController[\(ObjectIdentifier(self).hashValue)]: Cannot trigger ad rendering - WebView is nil")
            return
        }
        
        let triggerAdJS = """
        if (typeof window.triggerManualAdEvent === 'function') {
            window.triggerManualAdEvent();
        } else {
            // Fallback to direct call if the function isn't ready yet
            window.ayManagerEnv = window.ayManagerEnv || { cmd: [] };
            window.ayManagerEnv.cmd.push(function() {
                if (window.ayManagerEnv && typeof ayManagerEnv.dispatchManualEvent === 'function') {
                    ayManagerEnv.dispatchManualEvent();
                    console.log('[LLM] Triggered manual ad render event (fallback) for unit: \(adUnitId)');
                } else {
                    console.log('[LLM] ayManagerEnv.dispatchManualEvent not available (fallback) for unit: \(adUnitId)');
                }
            });
        }
        """
        
        debugPrint("[SN] [LLM] WebAdViewController[\(ObjectIdentifier(self).hashValue)]: Triggering ad rendering for \(adUnitId)")
        webView.evaluateJavaScript(triggerAdJS) { result, error in
            if let error = error {
                debugPrint("[SN] [LLM] WebAdViewController: Error triggering ad rendering:", error)
            } else {
                debugPrint("[SN] [LLM] WebAdViewController: Successfully triggered ad rendering for \(self.adUnitId)")
            }
        }
    }

    // MARK: Generate Custom Targeting JavaScript
    // Keys/values are JSON-encoded by TargetingScriptBuilder — quotes,
    // newlines, or "</script>" in targeting values cannot break the script.
    private func generateCustomTargetingJS() -> String {
        TargetingScriptBuilder.script(for: customTargetingParams) ?? ""
    }

    //MARK: Load ad content
    func loadAdContent() {
        guard !hasLoadedContent else { return }
        guard let webView = webView else { return }
        hasLoadedContent = true

        // Template load = new impression. Without this, ads held back for
        // consent keep whatever verdict latched against the EMPTY container
        // (the controller is reused, so makeUIViewController's re-arm never
        // runs again for the consent-driven load).
        viewabilityTrackerRef?.resetImpression(adUnitId)

        // 1. Consent handoff (always) — the provider's native→web consent
        // script (Didomi's own, or the generic __tcfapi stub). The snapshot is
        // remembered so a later consent change can be detected and reloaded.
        let consentJS = effectiveConsentProvider?.javaScriptForWebView() ?? ""
        loadedConsentJS = consentJS
        if !consentJS.isEmpty {
            let userScript = WKUserScript(source: consentJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(userScript)
        }

        // 1b. Viewability bridge shim (always) — exposes the NATIVE viewability
        // signal to the page (window.stepnetwork.viewability / onViewability /
        // 'snviewability' events)
        let viewabilityShimScript = WKUserScript(source: ViewabilityScripts.bridgeShim, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(viewabilityShimScript)

        // 2. Debug panel (debug only)
        let debuggingPanel = """
            (function() {
                // Create debug info panel
                var debugInfo = document.createElement('div');
                debugInfo.id = 'debugInfo';
                debugInfo.className = 'debug-info';

                // Ad unit info
                var adUnitDiv = document.createElement('div');
                adUnitDiv.id = 'adUnitInfo';
                adUnitDiv.textContent = 'Ad unit: ' + (window.stepnetwork && window.stepnetwork.adUnitId ? window.stepnetwork.adUnitId : '(not set)');
                debugInfo.appendChild(adUnitDiv);

                // Recheck adUnitId every 100ms, up to 5 times
                (function() {
                    var attempts = 0;
                    var maxAttempts = 5;
                    var interval = setInterval(function() {
                        attempts++;
                        var adUnitId = (window.stepnetwork && window.stepnetwork.adUnitId) ? window.stepnetwork.adUnitId : null;
                        if (adUnitId) {
                            adUnitDiv.textContent = 'Ad unit: ' + adUnitId;
                            clearInterval(interval);
                        } else if (attempts >= maxAttempts) {
                            adUnitDiv.textContent = 'Ad unit: unknown';
                            clearInterval(interval);
                        }
                    }, 100);
                })();
                
                // Ad size info
                var adSizeDiv = document.createElement('div');
                adSizeDiv.id = 'adSizeInfo';
                adSizeDiv.textContent = 'Size: (not sent)';
                debugInfo.appendChild(adSizeDiv);

                // Create Google Publisher Console button container
                var googleButton = document.createElement('div');
                googleButton.id = 'GoogleButton';

                // Create the button itself
                var button = document.createElement('a');
                button.href = '#';
                button.id = 'bookmarklet-button';
                button.textContent = 'Console';

                // Add click handler to open the publisher console
                button.addEventListener('click', function(event) {
                    event.preventDefault();
                    if (window.googletag && typeof googletag.openConsole === 'function') {
                        googletag.openConsole();
                    } else {
                        alert('Google Publisher Console is not available.');
                    }
                });

                // Assemble the elements
                googleButton.appendChild(button);
                debugInfo.appendChild(googleButton);

                // Add the debug panel to the body
                document.body.appendChild(debugInfo);

                // Patch sendAdSizeToNative to update the debug panel
                var origSendAdSizeToNative = window.sendAdSizeToNative;
                window.sendAdSizeToNative = function(width, height) {
                    if (adSizeDiv) {
                        adSizeDiv.textContent = 'Size: ' + width + ' x ' + height;
                    }
                    if (typeof origSendAdSizeToNative === 'function') {
                        origSendAdSizeToNative(width, height);
                    }
                };
            })();

            (function() {
                var methods = ['log', 'info', 'warn', 'error', 'debug'];
                methods.forEach(function(level) {
                    var original = console[level];
                    console[level] = function() {
                        var args = Array.prototype.slice.call(arguments);
                        // Remove %c and its style argument
                        if (typeof args[0] === 'string' && args[0].includes('%c')) {
                            args[0] = args[0].replace(/%c/g, '').trim();
                            args.splice(1, 1); // Remove the style string
                        }
                        // Pretty-print objects/arrays, join with newlines for readability
                        var message = args.map(function(arg) {
                            if (typeof arg === 'object' && arg !== null) {
                                try { return JSON.stringify(arg, null, 2); } catch (e) { return '[Object]'; }
                            }
                            return String(arg);
                        }).join(' - ');
                        window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nativeBridge.postMessage({
                            type: 'console',
                            level: level,
                            message: message
                        });
                        if (original) original.apply(console, arguments);
                    };
                });
            })();

            window.googletag = window.googletag || {};
            googletag.cmd = googletag.cmd || [];
            
            googletag.cmd.push(function () {
                // Set page-level targeting
                googletag.pubads().setTargeting('yb_target', 'alwayson-standard');
            });
        """
        if debugSettings.isDebugEnabled {
            let debuggingPanelScript = WKUserScript(source: debuggingPanel, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(debuggingPanelScript)

            // Module-6 verification probe: log the SETTLED DOM viewport after
            // resizes stop (150ms debounce), so viewport resizing is
            // observable in the console without a line per scroll step.
            let viewportProbe = """
            (function () {
                var snClipProbeTimer;
                window.addEventListener('resize', function () {
                    clearTimeout(snClipProbeTimer);
                    snClipProbeTimer = setTimeout(function () {
                        console.log('[CLIP] DOM viewport now ' + window.innerWidth + 'x' + window.innerHeight);
                    }, 150);
                });
            })();
            """
            let viewportProbeScript = WKUserScript(source: viewportProbe, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(viewportProbeScript)

            // Module-6 diagnostic: GPT Active View's own visibility percentage
            // (slotVisibilityChanged, throttled by GPT to ~200ms). Lets the
            // console show Google's measured % next to the native ratio.
            // Debug-only — never injected in production builds.
            let slotVisibilityListener = """
            (function () {
                window.googletag = window.googletag || {};
                googletag.cmd = googletag.cmd || [];
                googletag.cmd.push(function () {
                    var lastPercent = -1;
                    googletag.pubads().addEventListener('slotVisibilityChanged', function (event) {
                        if (event.inViewPercentage === lastPercent) { return; }
                        lastPercent = event.inViewPercentage;
                        try {
                            window.webkit.messageHandlers.nativeBridge.postMessage({
                                type: 'slotVisibilityChanged',
                                slotId: event.slot.getSlotElementId(),
                                visiblePercent: event.inViewPercentage,
                                ts: Date.now()
                            });
                        } catch (e) {}
                    });
                });
            })();
            """
            let slotVisibilityScript = WKUserScript(source: slotVisibilityListener, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(slotVisibilityScript)
        }

        // 2c. GPT Active View impression listener (always) — bridges Google's
        // own viewable-impression verdict (impressionViewable ad event) to
        // native (§2.3 in bridge-contract.md). Static source, no interpolation.
        let impressionViewableListener = """
        (function () {
            window.googletag = window.googletag || {};
            googletag.cmd = googletag.cmd || [];
            googletag.cmd.push(function () {
                googletag.pubads().addEventListener('impressionViewable', function (event) {
                    try {
                        window.webkit.messageHandlers.nativeBridge.postMessage({
                            type: 'impressionViewable',
                            slotId: event.slot.getSlotElementId(),
                            ts: Date.now()
                        });
                    } catch (e) {}
                });
            });
        })();
        """
        let impressionViewableScript = WKUserScript(source: impressionViewableListener, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(impressionViewableScript)

        // 3. AdUnit ID injection (always)
        let adUnitIdJS = """
        window.stepnetwork = window.stepnetwork || {}; window.stepnetwork.adUnitId = '\(self.adUnitId)';
        console.log('Injected adUnitId to JS, value: ' + window.stepnetwork.adUnitId);
        """
        let adUnitIdScript = WKUserScript(source: adUnitIdJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        webView.configuration.userContentController.addUserScript(adUnitIdScript)
        debugPrint("[SN] [NATIVE] Injected adUnitId to JS (window.stepnetwork.adUnitId): \(self.adUnitId)")

        // 4. Custom targeting (always, if present)
        let customTargetingJS = generateCustomTargetingJS()
        if !customTargetingJS.isEmpty {
            let customTargetingScript = WKUserScript(source: customTargetingJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(customTargetingScript)
            debugPrint("[SN] [NATIVE] Injected custom targeting with \(customTargetingParams.count) parameters")
        }

        // 5. URL loading (always)
        let urlString = Self.assembleTemplateURLString(
            baseURL: baseURL,
            debugEnabled: debugSettings.isDebugEnabled,
            randomValue: UUID().uuidString
        )

        // Create the URL from the added Query parameters. An empty baseURL
        // (SDK never initialized) must fail LOUDLY, not load a blank page.
        guard !baseURL.isEmpty, let url = URL(string: urlString), url.scheme != nil else {
            print("[SN] [ERROR] WebAdViewController: no valid ad template URL — ad '\(adUnitId)' will not load. Did you call WebAdViewSDK.initialize(config:)?")
            hasLoadedContent = false // allow a retry if consent/init arrives later
            return
        }

        initialURL = url  // Track the initial URL for domain comparison
        let request = URLRequest(url: url)
        webView.navigationDelegate = self // Ensure delegate is set
        webView.load(request)
        let id = ObjectIdentifier(self).hashValue
        debugPrint("[SN] [NATIVE] WebAdViewController[\(id)]: Loading URL \(url)")
    }

    /// Assembles the final template URL string from the configured base URL.
    /// `didomi-disable-notice=true` is guaranteed: the in-page Didomi notice
    /// must always stay suppressed (consent is collected natively and
    /// injected), also when the app supplies a custom `adTemplateURL`.
    static func assembleTemplateURLString(baseURL: String, debugEnabled: Bool, randomValue: String) -> String {
        var urlString = baseURL
        func append(_ parameter: String) {
            urlString += urlString.contains("?") ? "&\(parameter)" : "?\(parameter)"
        }
        if !urlString.contains("didomi-disable-notice") {
            append("didomi-disable-notice=true")
        }
        // Yield Manager debug panel in the template page
        if debugEnabled {
            append("aym_debug=true")
        }
        // Cache-buster
        append("rnd=\(randomValue)")
        return urlString
    }

    //MARK: WKUIDelegate - Handle target="_blank" clicks
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        
        // Handle popup windows by opening externally
        if let url = navigationAction.request.url {
            handleExternalURL(url)
            debugPrint("[SN] [NATIVE] External URL handler: Popup window opened externally.")
        }
    
        return nil
    }
    
    //MARK: WKNavigationDelegate - Handle navigation decisions
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let shouldHandleExternally = shouldHandleExternally(navigationAction: navigationAction, initialURL: initialURL)
        if shouldHandleExternally {
            handleExternalURL(navigationAction.request.url)
            decisionHandler(.cancel)
        } else {
            decisionHandler(.allow)
        }
    }
    
    //MARK: WKNavigationDelegate - Read back remote lazy-load config
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        remoteConfigPollAttempts = 0
        pollRemoteLazyLoadConfig()
        // Consent-driven reload of an already-displayed ad: the lazy-load
        // state machine fires no new transition, so re-trigger rendering
        // exactly once for the fresh page.
        if pendingRenderAfterReload {
            pendingRenderAfterReload = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.triggerAdRendering()
            }
        }
    }

    /// The Yield Manager script sets `window.stepnetwork.lazyLoad` some time
    /// AFTER page load, so poll: 10 tries, 500ms apart. A constant script —
    /// nothing is interpolated into the page.
    private func pollRemoteLazyLoadConfig() {
        let script = """
        (function () {
            var c = window.stepnetwork && window.stepnetwork.lazyLoad;
            return c ? JSON.stringify(c) : null;
        })()
        """
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard let self = self else { return }
            if self.handleRemoteLazyLoadPayload(result as? String) {
                return
            }
            self.remoteConfigPollAttempts += 1
            if self.remoteConfigPollAttempts < 10 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self, self.webView != nil else { return }
                    self.pollRemoteLazyLoadConfig()
                }
            } else {
                debugPrint("[SN] [LLM] No remote lazyLoad config on page (window.stepnetwork.lazyLoad); keeping current thresholds")
            }
        }
    }

    /// Applies and caches a `JSON.stringify(window.stepnetwork.lazyLoad)`
    /// payload. Returns whether the payload was a valid config. Separated from
    /// the poll loop so tests can exercise it directly (like handleBridgeMessage).
    @discardableResult
    func handleRemoteLazyLoadPayload(_ jsonString: String?) -> Bool {
        guard let jsonString = jsonString,
              let config = RemoteLazyLoadConfig.parse(jsonString: jsonString),
              config.isValid else {
            return false
        }
        if let host = initialURL?.host ?? URL(string: baseURL)?.host {
            remoteLazyLoadStore.save(config, forHost: host)
        }
        lazyLoadingManagerRef?.applyRemote(config)
        return true
    }

    //MARK: External URL Handler - Based on working model
    private func shouldHandleExternally(navigationAction: WKNavigationAction, initialURL: URL?) -> Bool {
        guard let targetURL = navigationAction.request.url else {
            debugPrint("[SN] [NATIVE] External URL handler: No target URL found")
            return false
        }
        
        // Always handle non-HTTP/HTTPS schemes externally
        if let scheme = targetURL.scheme, !["http", "https"].contains(scheme.lowercased()) {
            return true
        }
        
        // Handle popup windows externally (target="_blank")
        if navigationAction.targetFrame == nil {
            debugPrint("[SN] [NATIVE] External URL handler: Popup window detected")
            return true
        }
        
        // Handle different domain navigation externally (only for main frame)
        if let initialURL = initialURL,
           let initialDomain = initialURL.host,
           let targetDomain = targetURL.host,
           initialDomain != targetDomain,
           navigationAction.targetFrame?.isMainFrame == true {
            debugPrint("[SN] [NATIVE] External URL handler: External domain detected: \(initialDomain) -> \(targetDomain)")
            return true
        }
        
        return false
    }
    
    private func handleExternalURL(_ url: URL?) {
        guard let url = url else { return }

        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { success in
            }
        }
    }
}

// Sub-point comparisons for the clip idempotence guard: layout passes can
// nudge values by fractions of a point without anything meaningful changing.
private extension CGRect {
    func isNearlyEqual(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) < tolerance
            && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance
            && abs(height - other.height) < tolerance
    }
}

private extension CGPoint {
    func isNearlyEqual(to other: CGPoint, tolerance: CGFloat = 0.5) -> Bool {
        abs(x - other.x) < tolerance && abs(y - other.y) < tolerance
    }
}
