import Foundation
import CoreGraphics
import Combine

/// Per-ScrollView lazy-load state machine (notLoaded → fetched → displayed,
/// optional unload with 2s hysteresis; 67ms throttle). Implementation detail
/// behind the public `.lazyLoadAd()` modifier — `package` access on purpose:
/// the WebAdViewSDK target drives it, consumers never construct one.
package class LazyLoadingManager: ObservableObject {
    @Published package var adStates: [String: AdLoadState] = [:] // Stores current state for each adUnitId
    package var adUnitFrames: [String: CGRect] = [:] // Frames reported by WebAdViews
    package var scrollViewBounds: CGRect = .zero // Visible bounds of the ScrollView

    // Thresholds for lazy loading (can be configured via modifier)
    // This is a fixed value in iOS "points" (not pixels or % of screen).
    // On most devices, 800pt is roughly 1.0–1.2x the screen height. (Retina is around 1600pt.)
    package var fetchThreshold: CGFloat = 800
    package var displayThreshold: CGFloat = 200
    package var unloadThreshold: CGFloat = 1600 // Increased for hysteresis to prevent flickering
    package var unloadingEnabled: Bool = false // Controls whether ads should be unloaded when out of view

    /// STEP Network's remote per-domain values, in viewport-height % (100 = one
    /// viewport). When set, they take precedence over the point thresholds
    /// above for fetch/display (STEP always wins — product decision
    /// 2026-07-23); the distances are derived from the live viewport height in
    /// `checkAdVisibility`, so they track rotations/resizes automatically.
    package private(set) var remoteConfig: RemoteLazyLoadConfig?

    // Throttling mechanism instead of debouncing
    private var throttleTimer: AnyCancellable?
    private var lastUpdateTime: Date = Date.distantPast
    private let throttleInterval: TimeInterval = 0.067 // ~15fps (67ms)

    // Stability timer to prevent rapid unloading (Option B)
    private var unloadCandidates: [String: Date] = [:] // Track when ads became unload candidates
    private let unloadStabilityDelay: TimeInterval = 2.0 // 2 seconds delay before unloading

    /// Injectable clock — tests drive the throttle and the 2s unload-stability
    /// window with synthetic time.
    package var now: () -> Date = Date.init

    package init() {}

    package convenience init(config: LazyLoadingConfig) {
        self.init()
        fetchThreshold = config.fetchThreshold
        displayThreshold = config.displayThreshold
        unloadThreshold = config.unloadThreshold
        unloadingEnabled = config.unloadingEnabled
    }

    /// Applies STEP Network's remote per-domain thresholds (read back from the
    /// ad template page), in viewport-height %. Remote values override whatever
    /// the point thresholds were — defaults or developer-set (product decision
    /// 2026-07-23: STEP always wins). Invalid configs are ignored. Returns
    /// whether the config was applied.
    @discardableResult
    package func applyRemote(_ config: RemoteLazyLoadConfig) -> Bool {
        guard config.isValid else {
            debugPrint("[SN] [LLM] Remote lazyLoad config ignored (invalid values): fetch \(config.fetch), render \(config.render)")
            return false
        }
        remoteConfig = config
        debugPrint("[SN] [LLM] Remote lazyLoad thresholds applied: fetch \(config.fetch)% of viewport, render \(config.render)%")
        triggerVisibilityCheck()
        return true
    }

    package func updateAdFrame(_ adId: String, frame: CGRect) {
        let wasNew = adUnitFrames[adId] == nil
        if adUnitFrames[adId] != frame { // Only update if frame actually changed
            adUnitFrames[adId] = frame
            triggerVisibilityCheck()

            // If this is a new ad frame and scrollViewBounds is already set, do an immediate check
            if wasNew && !scrollViewBounds.isEmpty {
                debugPrint("[SN] [LLM] New ad frame registered for \(adId), performing immediate visibility check")
                checkAdVisibility()
            }
        }
    }

    package func updateScrollViewBounds(_ bounds: CGRect) {
        if scrollViewBounds != bounds { // Only update if bounds actually changed
            scrollViewBounds = bounds
            triggerVisibilityCheck()
        }
    }

    // Provides a Publisher for a specific ad unit's state
    package func adStatesPublisher(for adId: String) -> AnyPublisher<AdLoadState, Never> {
        $adStates
            .compactMap { $0[adId] } // Get the state for this specific adId
            .eraseToAnyPublisher()
    }

    // Throttled visibility check to ensure updates during scrolling at controlled frequency
    private func triggerVisibilityCheck() {
        let currentTime = now()
        let timeSinceLastUpdate = currentTime.timeIntervalSince(lastUpdateTime)

        if timeSinceLastUpdate >= throttleInterval {
            // Enough time has passed, execute immediately
            lastUpdateTime = currentTime
            checkAdVisibility()
        } else {
            // Too soon, schedule for later if not already scheduled
            if throttleTimer == nil {
                let remainingTime = throttleInterval - timeSinceLastUpdate
                throttleTimer = Timer.publish(every: remainingTime, on: .main, in: .common)
                    .autoconnect()
                    .first()
                    .sink { [weak self] _ in
                        guard let self = self else { return }
                        self.throttleTimer = nil
                        self.lastUpdateTime = self.now()
                        self.checkAdVisibility()
                    }
            }
        }
    }

    private func checkAdVisibility() {
        guard !scrollViewBounds.isEmpty else {
            debugPrint("[SN] [LLM] checkAdVisibility: scrollViewBounds is empty. Skipping.")
            return
        }

        // Remote values are viewport-height % → convert against the live
        // viewport; without them, the point thresholds apply. Unload must stay
        // at least as far out as fetch, or ads would unload inside the zone
        // that refetches them (hysteresis).
        let fetchDistance: CGFloat
        let displayDistance: CGFloat
        if let remote = remoteConfig {
            fetchDistance = scrollViewBounds.height * remote.fetch / 100
            displayDistance = scrollViewBounds.height * remote.render / 100
        } else {
            fetchDistance = fetchThreshold
            displayDistance = displayThreshold
        }
        let fetchZone = scrollViewBounds.insetBy(dx: 0, dy: -fetchDistance)
        let displayZone = scrollViewBounds.insetBy(dx: 0, dy: -displayDistance)
        let unloadZone = scrollViewBounds.insetBy(dx: 0, dy: -max(unloadThreshold, fetchDistance))
        let currentTime = now()

        for (adId, adFrame) in adUnitFrames {
            let currentLoadState = adStates[adId] ?? .notLoaded
            var newState: AdLoadState? = nil

            // State Transition Logic
            if currentLoadState == .notLoaded && adFrame.intersects(fetchZone) {
                newState = .fetched
                // Clear any unload candidate status when fetching
                unloadCandidates.removeValue(forKey: adId)
            } else if currentLoadState == .fetched && adFrame.intersects(displayZone) {
                newState = .displayed
                // Clear any unload candidate status when displaying
                unloadCandidates.removeValue(forKey: adId)
            } else if (currentLoadState == .fetched || currentLoadState == .displayed) && !adFrame.intersects(unloadZone) && unloadingEnabled {
                // Option B: Stability Timer - Check if ad should be marked for unloading (only if unloading is enabled)
                if unloadCandidates[adId] == nil {
                    // First time this ad is out of unload zone, mark as candidate
                    unloadCandidates[adId] = currentTime
                    debugPrint("[SN] [LLM] Ad \(adId) marked as unload candidate")
                } else if let candidateTime = unloadCandidates[adId],
                         currentTime.timeIntervalSince(candidateTime) >= unloadStabilityDelay {
                    // Ad has been out of zone long enough, proceed with unloading
                    newState = .unloaded
                    unloadCandidates.removeValue(forKey: adId)
                }
                // If not enough time has passed, don't change state yet
            } else if currentLoadState == .unloaded && adFrame.intersects(fetchZone) {
                newState = .notLoaded // Reset to notLoaded to trigger recreation/re-fetch
                unloadCandidates.removeValue(forKey: adId)
            } else {
                // Ad is back in a safe zone, clear unload candidate status
                unloadCandidates.removeValue(forKey: adId)
            }

            if let newState = newState, newState != currentLoadState {
                debugPrint("[SN] [LLM] Ad \(adId) TRANSITION: \(currentLoadState.rawValue) -> \(newState.rawValue)")
                adStates[adId] = newState // Update the published state
            }
        }
    }
}
