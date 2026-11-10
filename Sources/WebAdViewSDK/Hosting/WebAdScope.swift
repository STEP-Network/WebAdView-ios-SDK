import Foundation
import CoreGraphics
import Combine
import WebAdViewCore

/// UIKit-level equivalent of the `.lazyLoadAd()` SwiftUI modifier: one scope
/// per scroll container, owning that container's lazy-load state machine and
/// viewability measurement.
///
/// Hosts that are not SwiftUI (the Flutter plugin, a UIKit table view) create
/// one scope per scrollable screen, feed it geometry in window coordinates —
/// the container's visible rect plus, per ad, the whole ad frame (label
/// included, drives lazy loading) and the creative-only frame (drives
/// viewability) — and create a `WebAdHostView` per ad once the scope reports
/// `.fetched`. The state machines are the same ones the SwiftUI view uses;
/// only the geometry source differs.
///
/// Main thread only.
public final class WebAdScope {

    let manager: LazyLoadingManager
    let tracker: ViewabilityTracker

    /// - Parameter config: starting lazy-load thresholds. STEP Network's
    ///   remote per-domain values (cached from a previous read-back, or read
    ///   live from the next loaded ad page) always override them.
    public convenience init(config: LazyLoadingConfig = LazyLoadingConfig()) {
        self.init(
            config: config,
            remoteStore: RemoteLazyLoadStore(),
            templateHost: WebAdViewSDK.configuration?.adTemplateURL.host
        )
    }

    /// Internal seam: injectable cache + host for tests.
    init(config: LazyLoadingConfig, remoteStore: RemoteLazyLoadStore, templateHost: String?) {
        manager = LazyLoadingManager(config: config)
        tracker = ViewabilityTracker()
        // Same start-up rule as LazyLoadAdInternalModifier.onAppear: a cached
        // remote config applies before any page has loaded.
        if let host = templateHost, let cached = remoteStore.load(forHost: host) {
            manager.applyRemote(cached)
        }
    }

    // MARK: Geometry input (window coordinates, points)

    /// The scroll container's visible rect. Feeds both state machines.
    public func updateViewport(_ rect: CGRect) {
        manager.updateScrollViewBounds(rect)
        tracker.updateScrollViewBounds(rect)
    }

    /// The whole ad frame (label included) — lazy loading.
    public func updateAdFrame(_ adUnitId: String, frame: CGRect) {
        manager.updateAdFrame(adUnitId, frame: frame)
    }

    /// The creative-only frame (label excluded) — viewability measurement.
    public func updateCreativeFrame(_ adUnitId: String, frame: CGRect) {
        tracker.updateContentFrame(adUnitId, frame: frame)
    }

    /// Geometry of one ad for the batch entry point.
    public struct AdGeometry {
        /// Whole ad frame, label included (lazy loading).
        public let frame: CGRect
        /// Creative-only frame (viewability).
        public let creative: CGRect
        public init(frame: CGRect, creative: CGRect) {
            self.frame = frame
            self.creative = creative
        }
    }

    /// Preferred entry point: the viewport and every ad's geometry in ONE
    /// call per rendered frame. Each state machine runs exactly one pass per
    /// batch (the per-item methods above each run a pass of their own, so
    /// N ads cost N passes — fine for a UIKit host updating a single row,
    /// wasteful for a host that re-reports everything per frame).
    public func updateGeometry(viewport: CGRect, ads: [String: AdGeometry]) {
        var frames: [String: CGRect] = [:]
        var creatives: [String: CGRect] = [:]
        frames.reserveCapacity(ads.count)
        creatives.reserveCapacity(ads.count)
        for (adUnitId, geometry) in ads {
            frames[adUnitId] = geometry.frame
            creatives[adUnitId] = geometry.creative
        }
        manager.updateGeometry(bounds: viewport, frames: frames)
        tracker.updateGeometry(viewport: viewport, contentFrames: creatives)
    }

    // MARK: Registration

    /// Registers an ad unit for measurement (display standard). Ad unit ids
    /// must be unique within a scope.
    public func register(_ adUnitId: String) {
        tracker.register(adUnitId, mode: .display)
    }

    /// Forgets an ad unit in both state machines (the host destroyed its view).
    public func unregister(_ adUnitId: String) {
        manager.removeAd(adUnitId)
        tracker.unregister(adUnitId)
    }

    /// The host stopped reporting geometry for an ad whose `WebAdHostView`
    /// it keeps alive for later re-attachment (recycled rows, disposed
    /// widgets): load state, impression and verdict survive; nothing is
    /// measured or transitioned until geometry is reported again.
    public func detach(_ adUnitId: String) {
        manager.detachAd(adUnitId)
        tracker.detach(adUnitId)
    }

    /// Whether the hosting screen is on top. Pass `false` while another
    /// screen covers this one: ads underneath must not accrue dwell.
    public func setHostVisible(_ visible: Bool) {
        tracker.setHostVisible(visible)
    }

    // MARK: Outputs

    /// Current lazy-load state (`.notLoaded` until the first transition).
    public func loadState(for adUnitId: String) -> AdLoadState {
        manager.adStates[adUnitId] ?? .notLoaded
    }

    /// Lazy-load state stream. Replays the current state on subscribe (once
    /// one exists) and emits only on change.
    public func loadStates(for adUnitId: String) -> AnyPublisher<AdLoadState, Never> {
        manager.adStatesPublisher(for: adUnitId)
            .removeDuplicates()
            .eraseToAnyPublisher()
    }

    /// Viewability updates for an ad (the UIKit-level `.onViewabilityChange`),
    /// rate-limited for out-of-process hosts: the first update, every boolean
    /// transition (`isVisible` / `isViewable` / `isAppActive`) and
    /// `becameViewable` arrive immediately; ratio/dwell-only changes at most
    /// every 67 ms with a trailing coalesced send, so the resting state always
    /// arrives. Worst case ≤ 15 updates/s per ad; nothing while idle.
    public func viewabilityUpdates(for adUnitId: String) -> AnyPublisher<ViewabilityUpdate, Never> {
        tracker.hostUpdates(for: adUnitId)
    }
}
