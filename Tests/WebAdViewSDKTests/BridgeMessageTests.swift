import Testing
import CoreGraphics
import UIKit
@testable import WebAdViewSDK
@testable import WebAdViewCore

// MARK: - nativeBridge message handling
//
// Exercises WebAdViewController.handleBridgeMessage directly — the seam that
// backs the WKScriptMessageHandler (WKScriptMessage can't be constructed in
// tests). Bodies mimic what the injected GPT listeners post; every field is
// untrusted, so the malformed cases must not crash and must not fire callbacks
// with garbage.

@MainActor
private func makeController() -> WebAdViewController {
    WebAdViewController(
        baseURL: "https://example.invalid/ad-template.html",
        adUnitId: "div-gpt-ad-mobile_1",
        debugSettings: DebugSettings()
    )
}

@MainActor
@Suite("nativeBridge — impressionViewable")
struct ImpressionViewableMessageTests {

    @Test("Valid message fires the callback with the slot id")
    func validMessage() {
        let controller = makeController()
        var received: [String] = []
        controller.onActiveViewImpression = { received.append($0) }

        controller.handleBridgeMessage([
            "type": "impressionViewable",
            "slotId": "div-gpt-ad-mobile_1",
            "ts": 1730000000000
        ] as [String: Any])

        #expect(received == ["div-gpt-ad-mobile_1"])
    }

    @Test("Missing slotId falls back to 'unknown' without crashing")
    func missingSlotId() {
        let controller = makeController()
        var received: [String] = []
        controller.onActiveViewImpression = { received.append($0) }

        controller.handleBridgeMessage(["type": "impressionViewable"] as [String: Any])

        #expect(received == ["unknown"])
    }

    @Test("Mistyped slotId falls back to 'unknown' without crashing")
    func mistypedSlotId() {
        let controller = makeController()
        var received: [String] = []
        controller.onActiveViewImpression = { received.append($0) }

        controller.handleBridgeMessage([
            "type": "impressionViewable",
            "slotId": 12345
        ] as [String: Any])

        #expect(received == ["unknown"])
    }

    @Test("No callback registered — message is a safe no-op")
    func noCallback() {
        let controller = makeController()
        controller.handleBridgeMessage([
            "type": "impressionViewable",
            "slotId": "div-gpt-ad-mobile_1"
        ] as [String: Any])
        // Reaching here without a crash is the assertion.
    }
}

@MainActor
@Suite("WebAdView defaults")
struct WebAdViewDefaultTests {

    @Test("Honest viewport resizing (Module-6) is ON by default")
    func viewportResizingDefaultsOn() {
        #expect(WebAdView(adUnitId: "ad").viewportResizingEnabled == true)
    }

    @Test(".viewportResizing(false) opts a single ad out")
    func viewportResizingOptOut() {
        #expect(WebAdView(adUnitId: "ad").viewportResizing(false).viewportResizingEnabled == false)
    }
}

@MainActor
@Suite("nativeBridge — slotVisibilityChanged and robustness")
struct SlotVisibilityMessageTests {

    @Test("Valid slotVisibilityChanged is accepted (log-only, no callback)")
    func validVisibility() {
        let controller = makeController()
        var impressionFired = false
        controller.onActiveViewImpression = { _ in impressionFired = true }

        controller.handleBridgeMessage([
            "type": "slotVisibilityChanged",
            "slotId": "div-gpt-ad-mobile_1",
            "visiblePercent": NSNumber(value: 42),
            "ts": NSNumber(value: 1730000000000)
        ] as [String: Any])

        #expect(!impressionFired)
    }

    @Test("Mistyped visiblePercent does not crash")
    func mistypedPercent() {
        let controller = makeController()
        controller.handleBridgeMessage([
            "type": "slotVisibilityChanged",
            "slotId": "div-gpt-ad-mobile_1",
            "visiblePercent": "not-a-number"
        ] as [String: Any])
    }

    @Test("Unknown type and non-dictionary bodies are tolerated")
    func unknownAndGarbage() {
        let controller = makeController()
        var impressionFired = false
        controller.onActiveViewImpression = { _ in impressionFired = true }

        controller.handleBridgeMessage(["type": "somethingElse"] as [String: Any])
        controller.handleBridgeMessage("just a string")
        controller.handleBridgeMessage(["no", "type", "key"])

        #expect(!impressionFired)
    }

    @Test("Clip delivered before the webview exists survives and applies on first adSize")
    func clipBeforeViewLoadIsApplied() async throws {
        let controller = makeController()
        controller.viewportResizingEnabled = true

        // Below-fold static ads get their ONLY clip emission at
        // resetImpression time, before SwiftUI loads the controller's view.
        // It must be remembered, not dropped (regression: it was dropped
        // because the webView nil-guard preceded the pendingClip assignment).
        let fullyHidden = ViewportClipCalculator.Clip(
            sliceFrame: .zero, isFullyVisible: false, isFullyHidden: true
        )
        controller.applyViewportClip(fullyHidden) // webView is nil here

        controller.loadViewIfNeeded() // creates the webview at full size
        controller.handleBridgeMessage([
            "type": "adSize",
            "width": NSNumber(value: 320),
            "height": NSNumber(value: 320)
        ] as [String: Any])

        // The pending clip is applied via DispatchQueue.main.async — give the
        // main queue a turn.
        try await Task.sleep(nanoseconds: 200_000_000)

        #expect(controller.webView.frame.height == 1)
    }

    @Test("adSize with missing or mistyped dimensions is dropped without resizing")
    func malformedAdSizeIgnored() {
        let malformedBodies: [[String: Any]] = [
            ["type": "adSize"],
            ["type": "adSize", "width": NSNumber(value: 320)],
            ["type": "adSize", "width": "320", "height": "250"],
        ]
        for body in malformedBodies {
            let controller = makeController()
            var received: CGSize?
            controller.onAdSizeChange = { received = $0 }

            controller.handleBridgeMessage(body)

            #expect(received == nil, "body \(body) must not resize")
        }
    }

    @Test("adSize handling is unchanged by the refactor")
    func adSizeStillWorks() {
        let controller = makeController()
        var received: CGSize?
        controller.onAdSizeChange = { received = $0 }

        // NSNumber, as WKScriptMessage actually delivers JS numbers
        controller.handleBridgeMessage([
            "type": "adSize",
            "width": NSNumber(value: 320),
            "height": NSNumber(value: 250)
        ] as [String: Any])

        #expect(received == CGSize(width: 320, height: 250))
    }
}
