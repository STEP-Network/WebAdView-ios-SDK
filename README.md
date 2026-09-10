# WebAdView SDK

**STEP Network's ad SDK for publisher apps** — web ads that are
privacy-compliant, lazy-loaded, and honestly measured, for apps built
natively for iOS **and for Flutter apps on iOS and Android**. Publishers in
the network drop it into their existing apps.

It comes in two forms that behave identically:

| Your app is built with | Use | Where |
|---|---|---|
| **Swift** (SwiftUI, or UIKit) on iOS 16+ | the **WebAdView Swift Package** — this repository's `Sources/` | [`STEP-Network/WebAdView-ios-SDK`](https://github.com/STEP-Network/WebAdView-ios-SDK) · [QUICKSTART.md](QUICKSTART.md) · [GUIDE.md](GUIDE.md) |
| **Flutter**, targeting iOS 16+ and Android 7+ | the **`webadview_flutter` plugin** — one Dart integration for both platforms; it runs this Swift SDK on iOS and a Kotlin port of it on Android | [`STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK`](https://github.com/STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK), folder `Flutter/webadview_flutter` · [plugin README](https://github.com/STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK/blob/main/Flutter/webadview_flutter/README.md) |

Ads render in a web view (`WKWebView` on iOS, Android `WebView` on
Android) and are served through Google Ad Manager (GAM) via STEP Network's
**Yield Manager** (the ad wrapper that controls sizes, formats, and demand
remotely). The SDK handles Didomi consent gating, scroll-based lazy
loading, and industry-standard (IAB/MRC) viewability measurement — both
natively and in Google's own Active View reporting — the same way on every
platform.

- **Platform:** iOS 16+ · Swift 5.9+ · SwiftUI (and UIKit, GUIDE §4b);
  Flutter 3.44+ on iOS 16+ and Android 7+ (API 24)
- **Distribution:** Swift Package Manager (Didomi is pulled automatically) —
  `https://github.com/STEP-Network/WebAdView-ios-SDK.git`, from `1.1.0`.
  The Flutter plugin is a Git dependency on
  `https://github.com/STEP-Network/WebAdView-Flutter-apps-on-iOS-and-Android-SDK.git`
  (that repository also carries this Swift package, which the plugin builds
  from source).
- **Footprint:** ~8 MB installed (mostly the bundled Didomi framework) —
  details and runtime cost in [GUIDE §8](GUIDE.md#8-debug-output)
- **Integrate in 10 minutes:** [QUICKSTART.md](QUICKSTART.md) — copy-paste recipe
- **Full reference:** [GUIDE.md](GUIDE.md) — the canonical integration guide
- **Visual overview:** [WebAdView-SDK.pdf](WebAdView-SDK.pdf) — illustrated
  "how it works & how to use it" for developers and non-developers alike,
  covering native iOS and the Flutter plugin (iOS + Android). Source:
  `Documentation/WebAdView-SDK.html` (print to PDF with headless Chrome).

## Try the demo first

The repository ships a complete demo app that consumes the SDK exactly as
an external app would. From a fresh copy of the repository (keep the
checkout at a path **without spaces** — Xcode 26.6 crashes while resolving
the local package graph otherwise):

1. Open `Example/Project AdView.xcodeproj` in Xcode.
2. Select any iPhone simulator as the run destination.
3. Press **Run**. Nothing else is required on the simulator — no signing or
   team; the first build resolves the Didomi package automatically, and a
   demo Didomi key is included.

What you will see: the consent notice on first launch → accept → live test
ads load as you scroll. Tap the **ladybug** button (top right) for the
debug overlay and detailed console logging in Xcode (`[SN] [VIEWABILITY]`,
`[SN] [LLM]`, …), including Google's real-time viewable-impression
verdicts. Ready to integrate? [QUICKSTART.md](QUICKSTART.md).

## Quick look

```swift
import WebAdViewSDK

// 1. Once at app launch (e.g. in your AppDelegate):
WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
    didomiAPIKey: "<YOUR-DIDOMI-API-KEY>",                 // from STEP Network
    adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!  // your template page, on your domain
))

// 2. Anywhere in your SwiftUI content:
ScrollView {
    WebAdView(adUnitId: "div-gpt-ad-mobile_1")
        .showAdLabel(true, text: "annonce")   // label text — "annonce" is Danish for "ad"; use any wording
        .frame(maxWidth: .infinity)
}
.lazyLoadAd()                  // required — installs loading and measurement
.background(DidomiWrapper())   // once anywhere in the hierarchy — hosts the consent notice
```

Those three pieces are the integration for a standard placement. Ad requests
start only after the user has answered the consent notice; the stored
answer then tells the ad stack what it may serve — personalized ads,
non-personalized/limited ads, or none, per your domain's configuration.

App already running its own consent platform? The SDK defers to it instead
of bringing Didomi — see [GUIDE §3b](GUIDE.md#3b-bringing-your-own-cmp) (quick path: QUICKSTART's Path B).

## Honest viewability

An ad inside a webview normally measures itself against its own window —
which it always fills — so Google would report ~100% viewability no matter
where the ad really was on screen. This SDK resizes each ad's webview to
exactly the **visible slice** of the creative (nothing moves visually), so
Active View and GAM reporting reflect true on-screen exposure. It's the
default — no configuration — and the SDK reports both Google's verdict and
its own native measurement to your app. Details, callbacks, and the per-ad
opt-out: [GUIDE.md §7](GUIDE.md#7-viewability-iabmrc); the native↔web protocol:
[Documentation/bridge-contract.md](Documentation/bridge-contract.md).

## SDK features

- **Consent-gated loading** — ads request only after the consent notice is
  answered; consent changes reload ads automatically. The SDK brings Didomi,
  or defers to your app's own consent system ([GUIDE §3b](GUIDE.md#3b-bringing-your-own-cmp)).
- **Lazy loading** — ads fetch and display as the user scrolls toward them;
  the distances are tuned remotely per publisher by STEP Network ([GUIDE §5](GUIDE.md#5-lazy-loading)).
- **Viewability** — native IAB/MRC measurement plus honest Google Active
  View reporting, both exposed as Swift callbacks ([GUIDE §7](GUIDE.md#7-viewability-iabmrc)).
- **Custom targeting** — safe key/value targeting on the ad request
  ([GUIDE §6](GUIDE.md#6-custom-targeting)).
- **Automatic ad sizing** — the container follows the creative that is
  actually delivered; ad clicks leave the app and open in the system
  browser ([GUIDE §4](GUIDE.md#4-show-ads)).
- **Debug logging** — one flag turns on tagged console output and an
  in-webview debug panel ([GUIDE §8](GUIDE.md#8-debug-output)).

## Repository layout

| Path | Contents |
|---|---|
| `Sources/WebAdViewCore` | Pure logic: viewability engine, lazy-load state machine, targeting-script builder. No WebKit/Didomi — builds on macOS for fast iteration. |
| `Sources/WebAdViewSDK` | The product: SwiftUI, WebKit, and Didomi integration, plus the UIKit hosting layer (`Hosting/`). `import WebAdViewSDK` brings everything, core types included. |
| `Tests/` | 121 tests across two targets: core logic (50) and SDK bridge/tracker/consent/hosting behavior (71). |
| `Example/` | The SwiftUI demo app — see *Try the demo first*. STEP Network's demo Didomi key is hardcoded in the demo app, the reference ad template and the Flutter example only — never in the SDK sources. |
| `Documentation/` | The native↔web bridge contract (shared by the Swift SDK and the Kotlin port), the reference ad-template pages, and the source of `WebAdView-SDK.pdf`. |
| `Flutter/webadview_flutter/` | The Flutter plugin: Dart API, iOS adapter over this SDK, Kotlin port for Android, and the NewsHub example app with end-to-end tests. |

## Development & tests

```bash
# Fast core-logic iteration (no simulator needed):
swift build --target WebAdViewCore

# Full test suites — Didomi is an iOS-only binary, so tests run on a simulator:
xcodebuild test -scheme WebAdViewSDK -destination 'platform=iOS Simulator,name=iPhone 17'
```

> `swift test` from the repo root does **not** work (Didomi is iOS-only) —
> always run the suites through `xcodebuild` on a simulator as above.

CI runs both Swift suites, the Example app build, and the Flutter plugin
(analyze, Dart tests, iOS and Android builds, Kotlin tests) on every pull
request and on pushes to `main`.

## Coordination with STEP Network

Ad unit IDs, sizes, formats, and targeting keys are configured remotely by
STEP Network; your Didomi API key and ad template URL are provided during
onboarding. Before shipping, walk through the checklist in
[GUIDE.md §9](GUIDE.md#9-step-network-coordination-checklist) — including replacing the test Didomi key and test
template URL with your own via `WebAdViewSDK.initialize(config:)`.

## License

© STEP Network. All rights reserved. Publishers and partners
collaborating with STEP Network may use the SDK per their agreement —
see [LICENSE](LICENSE). Any other use requires written permission from
STEP Network.
