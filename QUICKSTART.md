# Quickstart — add STEP Network ads to your app in 10 minutes

The shortest path to a working, honestly-measured ad **inside your
existing app**. Copy-paste friendly; no prior knowledge of the SDK
assumed. The complete reference is [GUIDE.md](GUIDE.md).

## What you need

From your STEP Network onboarding:

1. **Your ad unit IDs** (one per placement).
2. **Your Didomi API key** — or nothing here, if your app already has its
   own consent system (see *Path B* below).
3. **Your ad template URL** (the page ads render in, hosted on your domain).

> No setup yet? Working **test values for all three** are listed at the
> bottom of this guide — you can complete every step with them.

## 1. Add the SDK package

In your app project: **File → Add Package Dependencies…**, paste the
repository URL, and add the **WebAdViewSDK** product to your app target.

> Package not published yet? Use **Add Local…** (bottom-left in the same
> dialog) and select your copy of the `SDK-WebAdView` folder instead.

> ⚠️ **Your app must be a standard App project.** Swift Playgrounds / App
> Playground packages (`.swiftpm`) are NOT supported: that format cannot
> embed the Didomi binary framework the SDK depends on, so the app crashes
> at launch on a physical device (a white screen) — even though it may
> appear to work in the simulator.

## Which describes your app?

- **Path A — my app has no consent setup** (most apps): the SDK brings the
  consent box (Didomi) for you. → Continue with **steps 2–4** below.
- **Path B — my app already shows its own consent box** (Didomi managed by
  your app, Cookiebot, OneTrust, Usercentrics, or another TCF-certified
  consent platform, "CMP"): the SDK must not show a second one — it reads
  your existing CMP's answer instead. → Jump to **[Path B](#path-b-your-app-already-has-a-consent-system)**
  further down, then come back to step 4.

## 2. (Path A) Initialize once, at app launch

Your app already starts up in one of two places — add the SDK call there.

**If your app is pure SwiftUI** — add the `init()` to your `App` struct:

```swift
import SwiftUI
import WebAdViewSDK

@main
struct MyAppApp: App {   // keep your app's own name
    init() {
        WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
            didomiAPIKey: "<YOUR-DIDOMI-API-KEY>",              // from STEP Network
            adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!  // from STEP Network
        ))
        DebugSettings.shared.isDebugEnabled = true  // console logging (remove for release)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

**If your app already has an `AppDelegate`** — put the same call at the top
of your existing `application(_:didFinishLaunchingWithOptions:)`:

```swift
import WebAdViewSDK

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
        didomiAPIKey: "<YOUR-DIDOMI-API-KEY>",
        adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!
    ))
    DebugSettings.shared.isDebugEnabled = true  // console logging (remove for release)
    // …your existing launch code…
    return true
}
```

## 3. (Path A) Put ads in a scroll view

This is a complete working screen. Add it to your project as a new file to
see ads immediately — then move the pieces into your own screens.

```swift
import SwiftUI
import WebAdViewSDK

struct AdExampleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // An ad above the fold ("annonce" is Danish for "ad" — use any label text)
                WebAdView(adUnitId: "div-gpt-ad-mobile_1")
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)

                // Your content
                ForEach(0..<12, id: \.self) { i in
                    Text("Content section \(i + 1)")
                        .frame(maxWidth: .infinity, minHeight: 80)
                }

                // An ad below the fold
                WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)

                Button("Privacy Settings") {
                    WebAdViewSDK.showConsentPreferences()
                }
            }
            .padding()
        }
        .lazyLoadAd()                  // REQUIRED — ads never load without it
        .background(DidomiWrapper())   // consent notice + preferences host
    }
}
```

When you move this into your own screens, keep three pieces: a
`WebAdView(adUnitId:)` per ad, `.lazyLoadAd()` on the containing
`ScrollView` or `List` (required — ads never load without it), and
`.background(DidomiWrapper())` once anywhere in the hierarchy. A `List`
works the same — see GUIDE §5 for one thing to know about row recycling.

Now continue with **step 4**.

## Path B: your app already has a consent system

Your CMP keeps showing the consent box exactly as it does today — the SDK
just waits for its answer. Use these instead of steps 2–3:

**Initialize at launch** (in your `App.init` as shown, or the same call in
your existing `application(_:didFinishLaunchingWithOptions:)`):

```swift
import SwiftUI
import WebAdViewSDK

@main
struct MyAppApp: App {   // keep your app's own name
    init() {
        WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
            consentProvider: TCFConsentProvider(),  // reads your CMP's answer — no Didomi key needed
            adTemplateURL: URL(string: "<YOUR-AD-TEMPLATE-URL>")!  // from STEP Network
        ))
        DebugSettings.shared.isDebugEnabled = true  // console logging (remove for release)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

> Your own consent system **is Didomi**? Use
> `consentProvider: AppDidomiConsentProvider()` on that line instead — the
> SDK then asks your Didomi directly whether the notice has been answered
> (details: GUIDE §3b).

**Put ads in a scroll view** — a complete working screen; add it as a new
file, then move the pieces into your own screens:

```swift
import SwiftUI
import WebAdViewSDK

struct AdExampleView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // An ad above the fold
                WebAdView(adUnitId: "div-gpt-ad-mobile_1")
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)

                // Your content
                ForEach(0..<12, id: \.self) { i in
                    Text("Content section \(i + 1)")
                        .frame(maxWidth: .infinity, minHeight: 80)
                }

                // An ad below the fold
                WebAdView(adUnitId: "div-gpt-ad-mobile_2")
                    .showAdLabel(true, text: "annonce")
                    .frame(maxWidth: .infinity)
            }
            .padding()
        }
        .lazyLoadAd()   // REQUIRED — ads never load without it
        // No consent code here: your own CMP shows the notice and
        // preferences UI, and ads wait automatically until it has an answer.
    }
}
```

In your own screens: a `WebAdView(adUnitId:)` per ad, and `.lazyLoadAd()`
on the containing `ScrollView`/`List` — that's all.

Two things to know:

- On Path B, the ad template page must contain **no consent code of its
  own** — your app's consent system is the only one. Tell STEP Network you
  use your own CMP and they provide a matching template URL
  (reference: `Documentation/example-ad-template-own-cmp.html`). The test
  template under *Test values* is built for Path A and won't work here.
- Details, requirements, and the production caveat:
  [GUIDE.md §3b "Bringing your own CMP"](GUIDE.md).

## 4. Run

Press **Run** (▶) on an iPhone simulator and open the screen with the ads.
You should see:

1. The consent notice on first launch. Until it's answered, no ad requests
   happen. (Path B: the notice you see is your own CMP's — ads load once
   it has been answered.)
2. After tapping accept: the top ad loads within a couple of seconds.
3. Scrolling down: the second ad loads as it approaches, and Google counts
   its viewable impression only when it's actually on screen.
4. In Xcode's console: tagged log lines — `[SN] [VIEWABILITY]` (native
   measurement, `✅ VIEWABLE (latched)` when an impression counts),
   `[SN] [VIEWABILITY] [ACTIVEVIEW]` (Google's verdicts), `[SN] [LLM]`
   (lazy loading).

## Run on your iPhone

The same project runs on a physical device with three extra clicks: project
→ **Signing & Capabilities** → select your **Team** (a free personal Apple
ID team works), pick your iPhone as the run destination, and press Run. The
phone must have **Developer Mode** enabled (Settings → Privacy & Security)
and will ask you to trust the developer profile the first time.

## Test values

Don't have your own key, template URL, or ad unit IDs yet? Use these
values from STEP Network in the snippets above while you develop:

- **Ad unit IDs:** `div-gpt-ad-mobile_1` … `div-gpt-ad-mobile_5` (STEP
  Network's test placements — they serve test creatives).
- **Didomi API key:** ask STEP Network, or use the test key found in the
  demo app (`Example/Project AdView/Project_AdViewApp.swift`). Test-only —
  production apps always get their own key.
- **Ad template URL:** STEP Network's test template,
  `https://adops.stepdev.dk/wp-content/ad-template.html?didomi-disable-notice=true`.
  Test-only — production apps host their own template page on their own
  domain (provided during STEP Network onboarding, like the key).

## If something doesn't work

| Symptom | Fix |
|---|---|
| Ads never appear | Is `.lazyLoadAd()` on the ScrollView? Was the consent notice answered? Is `WebAdViewSDK.initialize` called before any view? |
| Ads never appear (Path B) | Has your own CMP recorded an answer? It must have written `IABTCF_TCString` to UserDefaults — see GUIDE §3b. |
| No consent notice | Path A: is `.background(DidomiWrapper())` in the hierarchy? Delete the app and reinstall (consent is remembered per install). Path B: the SDK never shows one — your own CMP does. |
| No `[SN]` console output | Is `DebugSettings.shared.isDebugEnabled = true` set? |

Prefer testing in a sandbox first? Create a fresh SwiftUI **App** project
(not a Playground), point its `WindowGroup` at `AdExampleView()`, and use
the paste files above as-is.

Everything else — sizing, targeting, viewability callbacks, opt-outs,
production checklist: **[GUIDE.md](GUIDE.md)**.
