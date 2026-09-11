import UIKit
import Combine
import QuartzCore
import WebAdViewCore

// MARK: - ViewabilityTracker
/// Per-ScrollView orchestrator for viewability measurement.
///
/// Owns one `ViewabilityEngine` per ad unit and feeds it the geometry that
/// already flows through the lazy-loading preference keys, plus two inputs the
/// change-driven flow cannot provide:
/// - a steady 10Hz ticker that accrues dwell time while the user holds still
///   (runs ONLY while at least one engine is counting — zero cost at rest), and
/// - app-lifecycle transitions (backgrounding resets all continuous timers,
///   per IAB/MRC: an ad in the app switcher is not human-viewable).
///
/// `LazyLoadingManager` is deliberately untouched: lazy loading is a load-
/// lifecycle concern; viewability is a per-ad continuous-time measurement.
final class ViewabilityTracker: ObservableObject {
    private var engines: [String: ViewabilityEngine] = [:]
    private var contentFrames: [String: CGRect] = [:]
    /// Ads whose creative has rendered (the page's `adSize` message). Until
    /// then the slot is empty or still loading, so no dwell accrues and no
    /// verdict can latch — an empty box is not a viewable ad. Cleared by
    /// `resetImpression` (every page load starts unrendered).
    private var rendered: Set<String> = []
    private var scrollViewBounds: CGRect = .zero
    private var isAppActive: Bool = true
    /// Whether the hosting screen is itself visible. A non-SwiftUI host (the
    /// Flutter plugin) flips this when its route is covered by another
    /// screen: ads underneath are not human-viewable, so dwell must not
    /// accrue. Combined with `isAppActive` on every evaluation.
    private var isHostVisible: Bool = true

    private var ticker: AnyCancellable?
    private let tickInterval: TimeInterval = 0.1 // 10Hz: ±100ms on a 1s threshold (OM SDK polls at ~200ms)

    private let updateSubject = PassthroughSubject<ViewabilityUpdate, Never>()
    private let jsSubject = PassthroughSubject<ViewabilityUpdate, Never>()
    /// Last update forwarded to the webview, per ad — drives the JS emit policy.
    private var lastSentToJS: [String: ViewabilityUpdate] = [:]
    /// JS emit policy: ratio-only changes are forwarded when |delta| >= this.
    private let jsRatioDelta: CGFloat = 0.05

    /// Module-6 viewport clipping: per-ad visible-slice geometry, emitted when
    /// it changes beyond ViewportClipCalculator's tolerance.
    private let clipSubject = PassthroughSubject<(adUnitId: String, clip: ViewportClipCalculator.Clip), Never>()
    private var lastClip: [String: ViewportClipCalculator.Clip] = [:]

    /// Last progress log per ad, to throttle tick logging to ~4 lines/s.
    private var lastLogTime: [String: TimeInterval] = [:]
    private let logInterval: TimeInterval = 0.25

    private var lifecycleObservers: [NSObjectProtocol] = []

    /// Injectable clock (monotonic). Tests replace this with synthetic time.
    var clock: () -> TimeInterval = { CACurrentMediaTime() }

    init() {
        // willResignActive (not didEnterBackground): an ad behind the app
        // switcher or a system alert is not viewable.
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAppActive(false)
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.setAppActive(true)
        })
    }

    deinit {
        ticker?.cancel()
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    // MARK: Registration
    /// First registration wins: an ad unit's mode is locked when it first
    /// registers; later registrations with a different mode are ignored
    /// (with a warning).
    func register(_ adUnitId: String, mode: ViewabilityMode) {
        if let existing = engines[adUnitId] {
            if existing.mode != mode {
                debugPrint("[SN] [VIEWABILITY] \(adUnitId): already registered as \(existing.mode.rawValue) — ignoring conflicting mode \(mode.rawValue) (first registration wins)")
            }
            return
        }
        engines[adUnitId] = ViewabilityEngine(adUnitId: adUnitId, mode: mode)
        debugPrint("[SN] [VIEWABILITY] Registered \(adUnitId) — mode: \(mode.rawValue), needs ≥50% for \(String(format: "%.1f", mode.requiredDuration))s continuous")
        evaluate()
    }

    /// Forgets an ad unit: its engine, geometry and emit-policy state. The
    /// ticker stops if no remaining engine is counting.
    func unregister(_ adUnitId: String) {
        guard engines.removeValue(forKey: adUnitId) != nil else { return }
        contentFrames.removeValue(forKey: adUnitId)
        rendered.remove(adUnitId)
        lastSentToJS.removeValue(forKey: adUnitId)
        lastClip.removeValue(forKey: adUnitId)
        lastLogTime.removeValue(forKey: adUnitId)
        debugPrint("[SN] [VIEWABILITY] Unregistered \(adUnitId)")
        if engines.isEmpty {
            stopTicker()
        } else {
            evaluate()
        }
    }

    /// Host-screen visibility (see `isHostVisible`). Going hidden resets every
    /// continuous timer exactly like app backgrounding does.
    func setHostVisible(_ visible: Bool) {
        guard isHostVisible != visible else { return }
        isHostVisible = visible
        debugPrint(visible
            ? "[SN] [VIEWABILITY] host screen visible — measurement resumed"
            : "[SN] [VIEWABILITY] host screen covered — all continuous in-view timers RESET")
        evaluate()
    }

    /// Re-arms the ad's engine for a new impression (webview recreated or the
    /// template (re)loaded). Measurement stays parked until `markRendered`.
    func resetImpression(_ adUnitId: String) {
        guard let engine = engines[adUnitId] else { return }
        engine.reset()
        rendered.remove(adUnitId)
        lastSentToJS.removeValue(forKey: adUnitId)
        lastClip.removeValue(forKey: adUnitId) // fresh webview gets an immediate clip
        debugPrint("[SN] [VIEWABILITY] \(adUnitId): new impression — verdict re-armed, waiting for the creative to render")
        evaluate()
    }

    /// The creative has rendered (the page reported its `adSize`): dwell may
    /// accrue from now on. Idempotent per impression.
    func markRendered(_ adUnitId: String) {
        guard engines[adUnitId] != nil, !rendered.contains(adUnitId) else { return }
        rendered.insert(adUnitId)
        debugPrint("[SN] [VIEWABILITY] \(adUnitId): creative rendered — measurement started")
        evaluate()
    }

    // MARK: Geometry input (fed from the lazy-load modifier's preference flow)
    func updateContentFrame(_ adUnitId: String, frame: CGRect) {
        guard contentFrames[adUnitId] != frame else { return }
        contentFrames[adUnitId] = frame
        evaluate()
    }

    func updateScrollViewBounds(_ bounds: CGRect) {
        guard scrollViewBounds != bounds else { return }
        scrollViewBounds = bounds
        evaluate()
    }

    // MARK: Publishers
    /// Every measurement update for an ad (drives `.onViewabilityChange`).
    func updates(for adUnitId: String) -> AnyPublisher<ViewabilityUpdate, Never> {
        updateSubject
            .filter { $0.adUnitId == adUnitId }
            .eraseToAnyPublisher()
    }

    /// Rate-limited stream for the webview bridge: boolean transitions always,
    /// ratio-only changes at >= 5% delta, nothing while idle.
    func jsUpdates(for adUnitId: String) -> AnyPublisher<ViewabilityUpdate, Never> {
        jsSubject
            .filter { $0.adUnitId == adUnitId }
            .eraseToAnyPublisher()
    }

    /// Module-6: the ad's visible slice (ad-local coords) whenever it changes
    /// meaningfully. Consumed by WebAdViewController when viewport resizing is
    /// enabled for the ad.
    func clipUpdates(for adUnitId: String) -> AnyPublisher<ViewportClipCalculator.Clip, Never> {
        clipSubject
            .filter { $0.adUnitId == adUnitId }
            .map { $0.clip }
            .eraseToAnyPublisher()
    }

    // MARK: App lifecycle
    private func setAppActive(_ active: Bool) {
        guard isAppActive != active else { return }
        isAppActive = active
        if !active {
            debugPrint("[SN] [VIEWABILITY] app resigned active — all continuous in-view timers RESET")
        } else {
            debugPrint("[SN] [VIEWABILITY] app became active — measurement resumed")
        }
        // One pass so every counting engine drops to idle (or resumes) immediately.
        evaluate()
    }

    // MARK: Evaluation
    private func evaluate() {
        guard !scrollViewBounds.isEmpty else { return }
        let viewport = effectiveViewport()
        let now = clock()
        var anyCounting = false
        // An ad is only human-viewable while the app is active AND its own
        // screen is on top; either condition resets continuous timers.
        let isActive = isAppActive && isHostVisible

        for (adUnitId, engine) in engines {
            guard let frame = contentFrames[adUnitId] else { continue }
            // Viewport clips flow regardless (the controller applies them once
            // the creative has rendered); measurement only for rendered ads.
            forwardClipIfNeeded(adUnitId: adUnitId, adFrame: frame, viewport: viewport)
            guard rendered.contains(adUnitId) else { continue }
            let previousState = engine.state
            let update = engine.ingest(adFrame: frame, viewport: viewport, isAppActive: isActive, at: now)
            if case .counting = engine.state { anyCounting = true }

            updateSubject.send(update)
            forwardToJSIfNeeded(update)
            log(update, previousState: previousState, now: now)
        }

        // Ticker runs only while dwell is actually accruing.
        if anyCounting && isActive {
            startTickerIfNeeded()
        } else {
            stopTicker()
        }
    }

    /// The rect an ad's pixels must fall within to count as on-screen:
    /// the ScrollView's visible bounds clipped to the key window's safe area
    /// (handles nav bars, notch, and home indicator). Limitation: arbitrary
    /// floating overlays drawn on top of the content are not detected.
    private func effectiveViewport() -> CGRect {
        var viewport = scrollViewBounds
        if let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .first(where: { $0.isKeyWindow }) {
            let windowVisible = window.bounds.inset(by: window.safeAreaInsets)
            viewport = viewport.intersection(windowVisible)
            if viewport.isNull { return .zero }
        }
        return viewport
    }

    // MARK: Ticker
    private func startTickerIfNeeded() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: tickInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.evaluate()
            }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    // MARK: Module-6 clip emit policy
    private func forwardClipIfNeeded(adUnitId: String, adFrame: CGRect, viewport: CGRect) {
        let clip = ViewportClipCalculator.clip(adFrame: adFrame, viewport: viewport)
        if let previous = lastClip[adUnitId],
           !ViewportClipCalculator.differsSignificantly(previous, clip) {
            return
        }
        lastClip[adUnitId] = clip
        clipSubject.send((adUnitId: adUnitId, clip: clip))
    }

    // MARK: JS emit policy
    private func forwardToJSIfNeeded(_ update: ViewabilityUpdate) {
        let last = lastSentToJS[update.adUnitId]
        let booleanTransition = last == nil
            || last!.isVisible != update.isVisible
            || last!.isViewable != update.isViewable
            || last!.isAppActive != update.isAppActive
        let ratioJump = last.map { abs($0.ratio - update.ratio) >= jsRatioDelta } ?? true

        if booleanTransition || update.becameViewable || ratioJump {
            lastSentToJS[update.adUnitId] = update
            jsSubject.send(update)
        }
    }

    // MARK: Logging
    private func log(_ update: ViewabilityUpdate, previousState: ViewabilityEngine.State, now: TimeInterval) {
        guard let engine = engines[update.adUnitId] else { return }
        let stateChanged = engine.state != previousState
        let percent = Int((update.ratio * 100).rounded())

        if stateChanged {
            switch engine.state {
            case .counting:
                debugPrint("[SN] [VIEWABILITY] \(update.adUnitId): \(percent)% visible — ≥50% reached, continuous timer STARTED (needs \(String(format: "%.1f", update.mode.requiredDuration))s, \(update.mode.rawValue))")
            case .idle:
                if !update.isAppActive {
                    debugPrint("[SN] [VIEWABILITY] \(update.adUnitId): app inactive — continuous timer RESET")
                } else {
                    debugPrint("[SN] [VIEWABILITY] \(update.adUnitId): dipped to \(percent)% (<50%) — continuous timer RESET")
                }
            case .viewable:
                debugPrint("[SN] [VIEWABILITY] \(update.adUnitId): \(percent)% visible | in-view \(String(format: "%.2f", update.dwell))s / \(String(format: "%.2f", update.mode.requiredDuration))s (\(update.mode.rawValue)) | ✅ VIEWABLE (latched)")
            }
            lastLogTime[update.adUnitId] = now
            return
        }

        // Progress lines while counting, throttled to ~4/s.
        if case .counting = engine.state {
            let last = lastLogTime[update.adUnitId] ?? .zero
            if now - last >= logInterval {
                lastLogTime[update.adUnitId] = now
                let verdict = update.isViewable ? "VIEWABLE" : "NOT VIEWABLE"
                debugPrint("[SN] [VIEWABILITY] \(update.adUnitId): \(percent)% visible | in-view \(String(format: "%.2f", update.dwell))s / \(String(format: "%.2f", update.mode.requiredDuration))s (\(update.mode.rawValue)) | \(verdict)")
            }
        }
    }
}
