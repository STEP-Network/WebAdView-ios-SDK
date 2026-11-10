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
    /// Rate-limited stream for out-of-process hosts (the Flutter plugin, UIKit
    /// hosts via `WebAdScope.viewabilityUpdates`). Boolean transitions and
    /// `becameViewable` pass immediately; ratio/dwell-only changes are sent at
    /// most every `hostInterval` with a trailing coalesced send (≤ 15/s per ad).
    private let hostSubject = PassthroughSubject<ViewabilityUpdate, Never>()
    private var lastSentToHost: [String: ViewabilityUpdate] = [:]
    private var lastHostSendTime: [String: TimeInterval] = [:]
    private var pendingHost: [String: ViewabilityUpdate] = [:]
    private var hostTrailing: AnyCancellable?
    let hostInterval: TimeInterval = 0.067
    let hostRatioDelta: CGFloat = 0.05
    let hostDwellDelta: TimeInterval = 0.1
    /// Last update forwarded to the webview, per ad — drives the JS emit policy.
    private var lastSentToJS: [String: ViewabilityUpdate] = [:]
    /// JS emit policy: ratio-only changes are forwarded when |delta| >= this.
    private let jsRatioDelta: CGFloat = 0.05

    /// Module-6 viewport clipping: per-ad visible-slice geometry, emitted when
    /// it changes beyond ViewportClipCalculator's tolerance.
    private let clipSubject = PassthroughSubject<(adUnitId: String, clip: ViewportClipCalculator.Clip), Never>()
    private var lastClip: [String: ViewportClipCalculator.Clip] = [:]
    /// Clip cadence: while geometry keeps changing, applies are coalesced to at
    /// most one per `clipInterval` per ad (trailing edge), so a partially
    /// visible ad costs ≤ 10 webview resizes/s instead of one per frame.
    /// Regime transitions (full / partial / hidden) always apply immediately,
    /// and the exact final slice lands within `clipInterval` of the geometry
    /// settling. Bound: the page viewport lags true geometry by ≤ 100 ms.
    private var lastClipEmitTime: [String: TimeInterval] = [:]
    private var pendingClips: [String: ViewportClipCalculator.Clip] = [:]
    private var clipTrailing: AnyCancellable?
    let clipInterval: TimeInterval = 0.1

    /// Injectable one-shot scheduler for the trailing sends (tests drive it
    /// by hand). Default: a main-queue timer.
    var scheduleTrailing: (TimeInterval, @escaping () -> Void) -> AnyCancellable = { delay, action in
        Timer.publish(every: delay, on: .main, in: .common)
            .autoconnect()
            .first()
            .sink { _ in action() }
    }

    /// The key window, cached: `effectiveViewport()` runs once per geometry
    /// batch and must not walk the scene graph every time.
    private weak var cachedKeyWindow: UIWindow?

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
        hostTrailing?.cancel()
        clipTrailing?.cancel()
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
        lastSentToHost.removeValue(forKey: adUnitId)
        lastHostSendTime.removeValue(forKey: adUnitId)
        pendingHost.removeValue(forKey: adUnitId)
        lastClip.removeValue(forKey: adUnitId)
        lastClipEmitTime.removeValue(forKey: adUnitId)
        pendingClips.removeValue(forKey: adUnitId)
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
        lastSentToHost.removeValue(forKey: adUnitId)
        lastClip.removeValue(forKey: adUnitId) // fresh webview gets an immediate clip
        lastClipEmitTime.removeValue(forKey: adUnitId)
        pendingClips.removeValue(forKey: adUnitId)
        debugPrint("[SN] [VIEWABILITY] \(adUnitId): new impression — verdict re-armed, waiting for the creative to render")
        evaluate()
    }

    /// The host stopped reporting geometry for an ad whose webview stays
    /// alive (retained for re-attachment): drop its frame so nothing is
    /// measured until frames return, and reset any in-progress continuous
    /// timer — the latched verdict and the rendered flag survive, as the
    /// impression does.
    func detach(_ adUnitId: String) {
        guard let engine = engines[adUnitId], contentFrames.removeValue(forKey: adUnitId) != nil else { return }
        let viewport = effectiveViewport()
        let now = clock()
        let update = engine.ingest(adFrame: .zero, viewport: viewport, isAppActive: isAppActive && isHostVisible, at: now)
        updateSubject.send(update)
        forwardToJSIfNeeded(update)
        forwardToHostIfNeeded(update, now: now) // "not visible" reaches a still-subscribed host
        lastSentToHost.removeValue(forKey: adUnitId) // the next host gets a first update
        pendingHost.removeValue(forKey: adUnitId)
        pendingClips.removeValue(forKey: adUnitId)
        debugPrint("[SN] [VIEWABILITY] \(adUnitId): host detached — measurement paused (verdict kept)")
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

    /// Batch form: several creative frames (the SwiftUI preference flow
    /// delivers all of them at once) — ONE evaluation for the whole batch
    /// instead of one per ad.
    func updateContentFrames(_ frames: [String: CGRect]) {
        var changed = false
        for (adUnitId, frame) in frames where contentFrames[adUnitId] != frame {
            contentFrames[adUnitId] = frame
            changed = true
        }
        if changed { evaluate() }
    }

    /// Batch form for out-of-process hosts (the Flutter plugin sends the
    /// viewport and every ad's creative frame once per rendered frame): one
    /// evaluation per batch, nothing if nothing moved.
    func updateGeometry(viewport: CGRect, contentFrames frames: [String: CGRect]) {
        var changed = false
        if scrollViewBounds != viewport {
            scrollViewBounds = viewport
            changed = true
        }
        for (adUnitId, frame) in frames where contentFrames[adUnitId] != frame {
            contentFrames[adUnitId] = frame
            changed = true
        }
        if changed { evaluate() }
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

    /// Rate-limited stream for out-of-process hosts (see `hostSubject`).
    func hostUpdates(for adUnitId: String) -> AnyPublisher<ViewabilityUpdate, Never> {
        hostSubject
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
        PerfCounters.increment(.evaluations)
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
            forwardToHostIfNeeded(update, now: now)
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
        if cachedKeyWindow == nil || cachedKeyWindow?.isKeyWindow == false {
            cachedKeyWindow = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .flatMap({ $0.windows })
                .first(where: { $0.isKeyWindow })
        }
        if let window = cachedKeyWindow {
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
        let previous = lastClip[adUnitId]
        if let previous, !ViewportClipCalculator.differsSignificantly(previous, clip) {
            pendingClips.removeValue(forKey: adUnitId)
            return
        }
        let regimeChanged = previous == nil
            || previous!.isFullyVisible != clip.isFullyVisible
            || previous!.isFullyHidden != clip.isFullyHidden
        let now = clock()
        if regimeChanged || now - (lastClipEmitTime[adUnitId] ?? -.infinity) >= clipInterval {
            emitClip(adUnitId: adUnitId, clip: clip, at: now)
        } else {
            pendingClips[adUnitId] = clip // latest wins; flushed by the trailing timer
            scheduleClipTrailingIfNeeded()
        }
    }

    private func emitClip(adUnitId: String, clip: ViewportClipCalculator.Clip, at now: TimeInterval) {
        lastClip[adUnitId] = clip
        lastClipEmitTime[adUnitId] = now
        pendingClips.removeValue(forKey: adUnitId)
        clipSubject.send((adUnitId: adUnitId, clip: clip))
    }

    private func scheduleClipTrailingIfNeeded() {
        guard clipTrailing == nil else { return }
        clipTrailing = scheduleTrailing(clipInterval) { [weak self] in
            guard let self else { return }
            self.clipTrailing = nil
            let now = self.clock()
            for (adUnitId, clip) in self.pendingClips {
                self.emitClip(adUnitId: adUnitId, clip: clip, at: now)
            }
        }
    }

    /// Tests: run the trailing clip/host flush now instead of waiting.
    func flushTrailingForTesting() {
        let now = clock()
        clipTrailing?.cancel(); clipTrailing = nil
        for (adUnitId, clip) in pendingClips { emitClip(adUnitId: adUnitId, clip: clip, at: now) }
        hostTrailing?.cancel(); hostTrailing = nil
        for (adUnitId, update) in pendingHost { sendToHost(update, adUnitId: adUnitId, at: now) }
    }

    // MARK: Host emit policy (Flutter / UIKit hosts)
    private func forwardToHostIfNeeded(_ update: ViewabilityUpdate, now: TimeInterval) {
        let id = update.adUnitId
        let last = lastSentToHost[id]
        let urgent = last == nil
            || last!.isVisible != update.isVisible
            || last!.isViewable != update.isViewable
            || last!.isAppActive != update.isAppActive
            || update.becameViewable
        if urgent {
            sendToHost(update, adUnitId: id, at: now)
            return
        }
        let significant = abs(last!.ratio - update.ratio) >= hostRatioDelta
            || abs(last!.dwell - update.dwell) >= hostDwellDelta
        guard significant else { return }
        if now - (lastHostSendTime[id] ?? -.infinity) >= hostInterval {
            sendToHost(update, adUnitId: id, at: now)
        } else {
            pendingHost[id] = update
            scheduleHostTrailingIfNeeded()
        }
    }

    private func sendToHost(_ update: ViewabilityUpdate, adUnitId: String, at now: TimeInterval) {
        lastSentToHost[adUnitId] = update
        lastHostSendTime[adUnitId] = now
        pendingHost.removeValue(forKey: adUnitId)
        hostSubject.send(update)
    }

    private func scheduleHostTrailingIfNeeded() {
        guard hostTrailing == nil else { return }
        hostTrailing = scheduleTrailing(hostInterval) { [weak self] in
            guard let self else { return }
            self.hostTrailing = nil
            let now = self.clock()
            for (adUnitId, update) in self.pendingHost {
                self.sendToHost(update, adUnitId: adUnitId, at: now)
            }
        }
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
