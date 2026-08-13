# WebAdView SDK — Integration Guide

Privacy-compliant web ads for SwiftUI apps: Didomi consent gating, scroll-based
lazy loading, Google Ad Manager targeting via STEP Network's Yield Manager
(the ad wrapper that controls sizes, formats, and demand remotely), and
true IAB/MRC viewability measurement.

- **Platform:** iOS 16+ · Swift 5.9+ · SwiftUI
- **Distribution:** Swift Package Manager (Didomi is pulled automatically)

> **New here?** Run the demo app first (*Try the demo first* in
> [README.md](README.md)), then integrate with the 10-minute copy-paste
> recipe in [QUICKSTART.md](QUICKSTART.md). This guide is the full
> reference behind both.

**Contents:**
[1. Install](#1-install-spm) ·
[2. Initialize](#2-initialize-at-app-launch) ·
[3. Consent UI](#3-consent-ui-standard-mode--sdk-owned-didomi) ·
[3b. Your own CMP](#3b-bringing-your-own-cmp) ·
[4. Show ads](#4-show-ads) ·
[5. Lazy loading](#5-lazy-loading) ·
[6. Targeting](#6-custom-targeting) ·
[7. Viewability](#7-viewability-iabmrc) ·
[8. Debug](#8-debug-output) ·
[9. Checklist](#9-step-network-coordination-checklist) ·
[10. Troubleshooting](#10-troubleshooting)

---

## 1. Install (SPM)

In your app project in Xcode: **File → Add Package Dependencies…**, enter
the repository URL, and add the **WebAdViewSDK** product to your app
target — or add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/STEP-Network/WebAdView-ios-SDK.git", from: "1.0.0"),
]
```

Then `import WebAdViewSDK` — everything comes through the one module.

> ⚠️ Use a standard Xcode **App project** — Swift Playgrounds (`.swiftpm`)
> packages cannot embed the Didomi binary framework and crash on physical
> devices. The `Example/` app in this repo is a working reference consumer.

## 2. Initialize at app launch

Call once, before any `WebAdView` exists. In a pure-SwiftUI app the
simplest place is your `App` struct's initializer:

```swift
import SwiftUI
import WebAdViewSDK

@main
struct YourApp: App {
    init() {
        WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
            didomiAPIKey: "<YOUR-DIDOMI-API-KEY>",                      // required
            adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!       // required — your template page, on your domain
        ))
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

If you prefer an AppDelegate (or already have one), that works too — a new
SwiftUI project has none, so create it with `@UIApplicationDelegateAdaptor`:

```swift
import SwiftUI
import WebAdViewSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
            didomiAPIKey: "<YOUR-DIDOMI-API-KEY>",                      // required
            adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!       // required — your template page, on your domain
        ))
        return true
    }
}

@main
struct YourApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

Both values come from your STEP Network onboarding:

- **`didomiAPIKey`** — your Didomi API key. Don't commit real keys; inject
  them (xcconfig, CI secret, …).
- **`adTemplateURL`** — the page every ad webview loads, hosted on **your
  own domain**, containing the Yield Manager tag and the Didomi web tag in
  external-consent mode (`Documentation/example-ad-template.html` is a
  complete working page; `Documentation/bridge-contract.md` is the spec).
  The SDK automatically appends `didomi-disable-notice=true` if missing, so
  a bare URL is safe.
- No setup yet? Use the test values in
  [QUICKSTART.md](QUICKSTART.md#test-values).
- If `initialize` is never called, ads don't load and an unconditional
  `[SN] [ERROR]` warning is printed. Check `WebAdViewSDK.isInitialized`
  at runtime if needed. (`didomiDisableRemoteConfig:` exists as an advanced
  option — leave it at `false` unless STEP Network says otherwise.)

### Your app already has a consent system (CMP)?

Initialize with a consent provider instead of a Didomi key, and the SDK
defers to your CMP:

```swift
WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
    consentProvider: TCFConsentProvider(),   // reads your CMP's answer
    adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!
))
```

Skip §3 (your CMP owns the consent UI) and read
[§3b Bringing your own CMP](#3b-bringing-your-own-cmp).

## 3. Consent UI (standard mode — SDK-owned Didomi)

Didomi needs a view controller to present from. Put a `DidomiWrapper`
anywhere in your hierarchy, and offer a way to reopen preferences somewhere
in your content:

```swift
var body: some View {
    NavigationView {
        ScrollView {
            VStack {
                // …your content and WebAdViews…

                Button("Privacy Settings") {
                    WebAdViewSDK.showConsentPreferences()
                }
            }
        }
    }
    .background(DidomiWrapper())   // consent notice + preferences host
}
```

On a fresh install the Didomi notice appears automatically on first launch
(no code needed). Until the user has answered it, the SDK makes no ad
requests at all — the ad slots simply stay empty (no errors, nothing is
sent to Google).

Once answered (accept or decline), the stored answer tells the ad stack
what it may do, and the ad stack decides what serves: full consent enables
personalized ads; a decline means non-personalized/limited ads — or,
depending on the Google Ad Manager / Yield Manager configuration for the
domain, no ads at all. Viewability measurement — native and Active View —
is identical regardless of the answer. Consent changes are applied
automatically: ads waiting for consent load, and ads already on screen
reload with the new answer — you don't have to do anything.

### 3b. Bringing your own CMP

If your app **already runs its own consent platform** (CMP) — Didomi
managed by the app itself, Cookiebot, OneTrust, Usercentrics, or any other
CMP certified for TCF (the IAB's Transparency & Consent Framework, the
industry-standard consent format) — the SDK shows no consent UI of its own
and reads the user's answer from the standard `IABTCF_*` UserDefaults keys
every certified CMP maintains:

```swift
WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
    consentProvider: TCFConsentProvider(),   // reads your CMP's answer
    adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!
))
```

**Is your app's own CMP Didomi itself?** Then use
`consentProvider: AppDidomiConsentProvider()` instead (same setup
otherwise), and add Didomi through the same Swift Package the SDK uses
(`didomi-ios-sdk-spm`) — SPM links one shared Didomi binary for both.
Because they share that binary, this provider asks Didomi directly whether
the user has **actually answered** the notice — the most precise gate this
mode can have. (A second Didomi copy via CocoaPods or a manually embedded
framework would collide with the SDK's — don't mix installation methods.)

In this mode:

- No Didomi key, no `DidomiWrapper` — your CMP shows the notice and the
  preferences UI (`WebAdViewSDK.showConsentPreferences()` is a logged
  no-op, except with `AppDidomiConsentProvider`, where it opens your
  Didomi preferences).
- The consent gate is unchanged: ads wait until your CMP has recorded an
  answer, and consent changes (re)load ads automatically — including ads
  already on screen.
- The SDK hands your CMP's consent to the ad page via the standard
  `__tcfapi` mechanism, so the ad template page must contain **no consent
  code of its own** — use `Documentation/example-ad-template-own-cmp.html`
  as the reference and coordinate with STEP Network.
- For setups beyond TCF, implement the small `ConsentProvider` protocol
  yourself (`Sources/WebAdViewSDK/Consent/ConsentProvider.swift`).

> ⚠️ This mode has been verified end-to-end in STEP Network's reference
> setups (app-owned Didomi, and Usercentrics/Cookiebot via a TCF 2.2
> configuration: consent gate, ad delivery, and reload-on-change all
> confirmed against live test ads). Each publisher's own setup must still
> be validated with STEP Network before production.

### Pre-launch check for a non-Didomi CMP (and the fix if it fails)

Some CMP configurations publish a TC string already at first launch,
**before** the user has answered the notice. The TCF standard gives the
SDK no way to distinguish that from a real answer, so ads would start
requesting with that pre-answer state. (`AppDidomiConsentProvider` is
immune — it asks Didomi directly.)

**How to check (part of the pre-launch test with STEP Network):** delete
the app, reinstall, launch with SDK debug logging on (§8), and don't touch
the consent notice. If no `Loading URL` lines appear in the console until
you answer the notice — your CMP behaves correctly and you are done. If
ads start loading *before* you answer, first look for a setting in your
CMP's dashboard that delays the consent string until user interaction —
that is the right fix.

**If the CMP can't be reconfigured**, ask it directly from code instead —
the same approach `AppDidomiConsentProvider` uses for Didomi. Add this
file to your app and replace the two marked spots with your CMP SDK's own
API calls:

```swift
import Foundation
import WebAdViewSDK

/// Consent provider that asks YOUR consent platform directly whether the
/// user has answered — instead of trusting the shared TCF storage alone.
final class MyCMPConsentProvider: ConsentProvider {

    // Reads the standard TCF storage for the page hand-off — keep as is.
    private let tcf = TCFConsentProvider()

    var isConsentDetermined: Bool {
        // REPLACE with your CMP SDK's "has the user answered?" API, e.g.:
        //   OneTrust:     OTPublishersHeadlessSDK.shared.shouldShowBanner() == false
        //   Usercentrics: UsercentricsCore.shared.status.shouldCollectConsent == false
        false   // fail-closed until wired up — ads never load while false
    }

    func start(onChange: @escaping () -> Void) {
        // Keeps the page hand-off fresh whenever the TCF storage changes:
        tcf.start(onChange: onChange)
        // ADD: subscribe to your CMP SDK's consent-changed callback and
        // call onChange() from it, so ads (re)load on every answer.
    }

    // Hand-off to the ad page — keep as is (the standard __tcfapi stub).
    func javaScriptForWebView() -> String { tcf.javaScriptForWebView() }

    // Open your CMP's preferences UI here, or leave as a no-op.
    func showPreferences() {}
}
```

Then initialize with it (everything else stays as above):

```swift
WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
    consentProvider: MyCMPConsentProvider(),
    adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!
))
```

Re-run the check above — ads must now wait until the notice is answered.

## 4. Show ads

```swift
ScrollView {
    VStack {
        WebAdView(adUnitId: "div-gpt-ad-mobile_1")
            .showAdLabel(true, text: "annonce")
            .frame(maxWidth: .infinity)

        // …content…

        WebAdView(adUnitId: "div-gpt-ad-mobile_2")
            .showAdLabel(true)
            .frame(maxWidth: .infinity)
    }
}
.lazyLoadAd()   // ← REQUIRED on the scroll container (see below)
```

> **`.lazyLoadAd()` is required, not optional.** It installs the loading
> and viewability machinery; without it, `WebAdView`s stay blank forever.
> Attach it to the scroll container that holds your ads — `ScrollView` and
> `List` both work (see §5 for the `List` difference).

**⚠️ Ad unit IDs, sizes, and formats are configured remotely by STEP
Network's Yield Manager.** Local frame constraints are UI-layout only —
they never change which creative is served. Coordinate ad unit IDs,
dimensions, and targeting with STEP Network before implementation.

### Sizing (UI-layout only)

```swift
WebAdView(
    adUnitId: "div-gpt-ad-mobile_3",
    initialWidth: 320, initialHeight: 320,  // container size while loading
    maxHeight: 600                          // container constraint (can clip — prefer flexible)
)
.frame(maxWidth: .infinity)                 // safe: allows automatic resizing
```

The webview auto-resizes to the delivered creative. Restrictive `.frame()`
values can crop ads — prefer `maxWidth: .infinity`.

### Force a reload

```swift
WebAdView(adUnitId: "div-gpt-ad-mobile_1")
    .id(adKey)          // change adKey (e.g. UUID()) to fully recreate the ad
```

## 5. Lazy loading

```swift
.lazyLoadAd()                                          // defaults: fetch 800pt, display 200pt
.lazyLoadAd(unloadingEnabled: true)                    // + unload far-away ads (memory-sensitive UIs)
.lazyLoadAd(fetchThreshold: 1000, displayThreshold: 300, unloadThreshold: 2000)
```

States per ad: `notLoaded → fetched` (HTML loads) `→ displayed` (ad
renders). With unloading enabled, ads >1600pt away for 2s are torn down and
recreated on re-entry. Unloading is **off by default** (UX over memory).

**The distances are managed remotely by STEP Network.** Each publisher
domain gets its own tuned fetch/display values, expressed as **percentages
of the screen height** (100 = one full screen; fetch 150 / display 100 =
"request 1.5 screens early, show one screen early"). The SDK reads them
from the loaded ad page and remembers them between launches. **The remote
values always win:** the numbers in your code — defaults *and* custom
`.lazyLoadAd(fetchThreshold:...)` values — are only starting values used
until STEP Network's values arrive. You don't need to configure anything.

### Using a `List` instead of a `ScrollView`

`.lazyLoadAd()` works the same attached to a `List` — ads in rows load,
measure, and clip correctly. One difference: `List` recycles its rows, so
an ad row scrolled far off screen is destroyed and recreated on return —
each re-entry is a **new impression and a new ad request**, regardless of
`unloadingEnabled`. In a `ScrollView`, ads stay alive unless you enable
unloading.

## 6. Custom targeting

```swift
WebAdView(adUnitId: "div-gpt-ad-mobile_1")
    .customTargeting("section", "homepage")
    .customTargeting("tags", ["breaking", "featured"])
```

Values are JSON-encoded into the GPT call — any characters are safe.
**Targeting keys must be configured by STEP Network in Google Ad Manager
before they affect delivery.**

## 7. Viewability (IAB/MRC)

The SDK measures true on-screen viewability natively: an impression is
**viewable** when ≥50% of the creative's pixels are on screen for a
continuous ≥1s — the display standard set by the IAB and the Media Rating
Council, which ad buyers audit against. Dips below 50% and app
backgrounding reset the timer; the verdict latches once per impression.

There is nothing to configure per creative type: Google's Active View
applies the correct standard per creative automatically inside the webview
(including video's 2s-of-playback rule), and the native signal is the
geometric on-screen truth for any creative.

```swift
WebAdView(adUnitId: "div-gpt-ad-mobile_1")
    .onViewabilityChange { update in
        if update.becameViewable {
            // fires exactly once per impression
            print("\(update.adUnitId) viewable! ratio=\(update.ratio) dwell=\(update.dwell)s")
        }
    }
```

`ViewabilityUpdate` fields: `ratio` (0–1 fraction of pixels on screen),
`isVisible` (≥50% and app active), `dwell` (continuous seconds in view),
`isViewable` (latched verdict), `becameViewable`, `mode`, `isAppActive`.

### Google's own verdict: `.onActiveViewImpression()`

The SDK also listens for GPT's `impressionViewable` event inside the
webview — Active View's real-time "this impression counted as viewable"
signal, the same standard GAM reporting is built on:

```swift
WebAdView(adUnitId: "div-gpt-ad-mobile_1")
    .onActiveViewImpression { slotId in
        // Google counted a viewable impression for this slot
    }
```

> With viewport resizing on (the default) this reflects true exposure and
> lands within ~a second of the native `becameViewable` latch. For an ad
> opted out via `.viewportResizing(false)` it fires optimistically shortly
> after render — the native signal stays authoritative either way.

### Reading the signal inside the ad webview (JS)

The native measurement is also bridged into every ad page
(`window.stepnetwork.viewability`, `window.stepnetwork.onViewability(...)`,
and a `snviewability` DOM event). Full payload and message spec:
[Documentation/bridge-contract.md §4.1](Documentation/bridge-contract.md).

### GAM/Active View measure honestly by default: `.viewportResizing()`

The SDK resizes each ad's webview to exactly the **visible slice** of the
creative (shifting the page content so nothing appears to move). The DOM
viewport then equals what's truly on screen, so Active View and GAM
reporting reflect real viewability. **On by default** — no configuration.

```swift
WebAdView(adUnitId: "div-gpt-ad-mobile_1")
    .viewportResizing(false)    // opt a single ad OUT (not recommended)
```

Applied automatically: clipping starts only after the creative has rendered
(ads are never requested into a collapsed viewport); the SwiftUI layout
keeps the full ad frame (no content jumping); fully hidden ads keep a 1pt
sliver (a zero frame can suspend the page); updates are change-driven with
a 2pt tolerance.

**Why an opt-out exists:** honest measurement means reported viewability
*drops* from a fake ~100% to reality. If STEP Network flags a misbehaving
placement, that single ad can be opted out while it's investigated — its
Active View numbers then read ~100% regardless of position, and only the
native signal is trustworthy for it.

## 8. Debug output

Toggle the ladybug icon (demo app) or set the flag directly:

```swift
DebugSettings.shared.isDebugEnabled = true
```

The flag is **off by default**, so release builds are automatically clean —
users never see debug output unless the app explicitly enables it. It is
remembered between launches and takes effect immediately (logging at once;
the in-ad overlay panel on the next ad load). It is also a live, runtime
switch: apps can wire it to a hidden developer control — the demo app's
ladybug button is exactly that — so logging can be turned on in a
production build while investigating an issue.

With debugging on: `[SN] [VIEWABILITY]` live per-ad measurement lines
(ratio, timer, `✅ VIEWABLE (latched)`), `[SN] [LLM]` lazy-loading
transitions, `[SN] [NATIVE]` / `[HTML]` consent flow and bridged page
console output, plus an in-webview debug panel and Yield Manager debug
mode (`aym_debug=true`). Watch live from a terminal:

```bash
xcrun simctl launch --console-pty booted <your-bundle-id> | grep VIEWABILITY
```

### Footprint and performance

**In short:** the SDK is light. ~8 MB added install size is a few percent
of a typical app (and less than most native ad SDKs); install size does
not affect speed. At runtime the SDK costs essentially nothing while no
ad is on screen, and a visible ad costs about what displaying rich
content costs in any app — bounded by lazy loading no matter how long
the feed is. It will not make an app feel slow.

**Install size:** the SDK adds about **8 MB** to the installed app
(measured on a Release device build): ~7 MB is the embedded Didomi
framework — included in every consent mode, also with an app-owned CMP —
and ~1 MB is the SDK code itself. App Store downloads are compressed, so
the over-the-wire size is smaller.

**Runtime cost** (A/B-measured against an identical screen without ads;
simulator numbers — treat as indicative):

- SDK initialized, no ads loaded yet: ≈ **+7 MB** app memory.
- Two ads loaded and rendered: ≈ **+30–45 MB** in the app process —
  roughly 10–20 MB per active ad webview. (WebKit additionally runs page
  content in separate system processes that iOS manages and reclaims
  outside the app's own memory.)
- CPU: no measurable idle cost; brief single-digit percentages while an
  ad loads. The viewability ticker (10 Hz) only runs while an ad is
  actively counting toward a viewable impression.

Per-ad cost is bounded by design: a webview only exists once lazy loading
fetches it, `unloadingEnabled: true` tears down far-away ads in long
feeds, and `List` row recycling destroys off-screen ad rows automatically
(§5).

## 9. STEP Network coordination checklist

Before shipping, confirm with STEP Network:
- [ ] Ad unit IDs for your placements
- [ ] Expected sizes/formats per ad unit (Yield Manager config)
- [ ] Custom targeting keys registered in Google Ad Manager
- [ ] Your ad template URL (production, hosted on your domain — not the test template)
- [ ] Your domain added to STEP Network's lazy-loading configuration, so
      your app gets your tuned fetch/render distances (§5; until then a
      safe fallback applies)
- [ ] Your Didomi API key (standard mode; production, not the test key)
- [ ] If bringing your own CMP (§3b): ad template page without a CMP web
      tag, and end-to-end validation with STEP Network before launch —
      including the pre-answer consent check (§3b) for non-Didomi CMPs

## 10. Troubleshooting

| Symptom | Check |
|---|---|
| Ads never load | Was `WebAdViewSDK.initialize(config:)` called? Is consent given (notice answered)? Standard mode: is `DidomiWrapper` in the hierarchy? |
| Ads never load (own-CMP mode, §3b) | Has your CMP recorded an answer? It must have written `IABTCF_TCString` to UserDefaults (or `IABTCF_gdprApplies = 0`). |
| No consent notice appears (own-CMP mode, §3b) | Expected — the SDK never shows one in this mode; your own CMP does. |
| Build error: `missing required modules: 'JavaScriptCore', 'SystemConfiguration'` | Update to a SDK version ≥ this one (the SDK carries the imports); clean build folder. |
| No debug output | Enable the debug flag (ladybug / `DebugSettings.shared.isDebugEnabled = true`). |
| Ads clipped/distorted | Remove restrictive `.frame()`/max constraints, or align them with STEP Network's Yield Manager config. |
| Viewability never latches | The ad must be ≥50% on screen continuously — check the `[SN] [VIEWABILITY]` ratio lines; nav bars/safe areas clip the effective viewport. |
| Targeting has no effect | Keys must be configured by STEP Network in GAM first. |
| Many ads = jank | Apply `.lazyLoadAd()` to the ScrollView; consider `unloadingEnabled: true`. |

## Development (this repo)

```bash
# Fast core-logic iteration (no simulator):
swift build --target WebAdViewCore

# Full package test suites (WebAdViewCore + WebAdViewSDK):
xcodebuild test -scheme WebAdViewSDK -destination 'platform=iOS Simulator,name=iPhone 17'

# Demo app:
xcodebuild build -project "Example/Project AdView.xcodeproj" -scheme "Project AdView" \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

> `swift test` from the repo root does **not** work — Didomi is an iOS-only
> binary framework, so the suites must run on a simulator via `xcodebuild`.
