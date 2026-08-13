# WebAdView Bridge Contract

Platform-neutral specification of the contract between the **native SDK layer**
(iOS today, Android later) and the **web ad template** (GPT + Yield Manager)
loaded inside each ad webview. An Android port implements exactly this
contract against `android.webkit.WebView`; the template does not change.

---

## 1. Ad template URL contract

| Aspect | Value |
|---|---|
| Base URL | Required per app (`WebAdViewSDKConfig.adTemplateURL`) — no built-in default; each publisher hosts their own template page. STEP Network's test template: `https://adops.stepdev.dk/wp-content/ad-template.html?didomi-disable-notice=true` |
| `didomi-disable-notice=true` | Suppresses the Didomi **web** notice inside the ad view (consent is collected natively and injected). Guaranteed: the native SDK appends it if the configured URL lacks it. |
| `aym_debug=true` | Appended only when the SDK debug toggle is on. Enables Yield Manager (Assertive Yield) debug mode. |
| `rnd=<UUID>` | Always appended. Cache buster. |

The template page (reference implementations in this folder:
`example-ad-template.html` for standard mode,
`example-ad-template-own-cmp.html` for bring-your-own-CMP mode):
1. Standard mode only: loads the Didomi web SDK with `externalConsent`
   enabled (native consent applies). Own-CMP mode: the page contains NO
   consent code — native injects a `__tcfapi` stub instead (§3).
2. Loads the Yield Manager tag (`ay.delivery`) — STEP Network's **App
   workspace** tag, not a website's: it carries the app ad units and
   publishes the remote lazy-load values (§3.2).
3. Polls up to 500×10ms for `window.stepnetwork.adUnitId` (injected by native — see §3).
4. Creates a `div` with `id` and `data-ay-manager-id` set to the ad unit id, calls
   `ayManagerEnv.display(adUnitId)`, and registers
   `window.triggerManualAdEvent = () => ayManagerEnv.dispatchManualEvent()`.
5. Observes the ad div's size (ResizeObserver) and reports it to native (§2, `adSize`).

## 2. Web → native messages (`nativeBridge`)

iOS: `WKScriptMessageHandler` named `nativeBridge`
(`window.webkit.messageHandlers.nativeBridge.postMessage(...)`).
Android equivalent: `@JavascriptInterface` object (e.g. `window.nativeBridge.postMessage(JSON.stringify(...))`).

All messages are objects with a `type` discriminator:

### 2.1 `console` — bridged JS console output (debug builds only)
```json
{ "type": "console", "level": "log|info|warn|error|debug", "message": "<string>" }
```

### 2.2 `adSize` — the rendered creative's size
```json
{ "type": "adSize", "width": 320, "height": 250 }
```
- Sent only when both dimensions are non-zero.
- Native resizes the ad container to match (subject to UI-layout-only min/max constraints).

### 2.3 `impressionViewable` — GPT Active View's viewable verdict
```json
{ "type": "impressionViewable", "slotId": "div-gpt-ad-mobile_1", "ts": 1730000000000 }
```
- Posted by a native-injected listener for the GPT.js `impressionViewable` ad
  event (<https://developers.google.com/publisher-tag/reference#googletag.events.impressionviewableevent>)
  — Google's own signal that the impression met the IAB/MRC viewable standard
  (≥50% in view for ≥1s). Fires at most once per impression.
- `slotId` is the GPT slot element id (matches the ad unit div id).
- Native logs it and forwards to the host app's `onActiveViewImpression`
  callback.
- Honesty: viewport resizing (§4.4) is on by default, so this reflects true
  on-screen exposure. For an ad opted out of resizing, the ad fills its own
  webview, Active View self-measures ~100%, and this fires optimistically
  shortly after render. The native viewability signal (§4/§5) stays
  authoritative.

### 2.4 `slotVisibilityChanged` — GPT's self-reported visibility % (debug only)
```json
{ "type": "slotVisibilityChanged", "slotId": "div-gpt-ad-mobile_1", "visiblePercent": 42, "ts": 1730000000000 }
```
- Posted by a diagnostic listener for the GPT.js `slotVisibilityChanged` event;
  the listener is injected **only when the SDK debug toggle is on** (zero
  footprint in production).
- `visiblePercent` is an integer 0–100. GPT throttles the event to ~200ms; the
  listener additionally drops unchanged values.
- Log-only on native — used to compare Google's measured percentage against
  the native ratio during viewport-resizing validation.

## 3. Native → web injections

Injected before/at page load (iOS: `WKUserScript`; Android: `evaluateJavascript` at `onPageStarted` — note Android has no true document-start user scripts, so inject as early as possible):

| Injection | Timing | Content |
|---|---|---|
| Consent handoff | document start | Provider-dependent. Default (SDK-owned Didomi): `Didomi.shared.getJavaScriptForWebView()` (iOS) / `Didomi.getInstance().getJavaScriptForWebView()` (Android) — passes native consent into the web Didomi SDK. Bring-your-own-CMP mode (`TCFConsentProvider`): a minimal in-app-webview `__tcfapi` stub (`ping`/`getTCData`/`addEventListener`/`removeEventListener`, `eventStatus: 'tcloaded'`) carrying the `IABTCF_TCString`/`IABTCF_gdprApplies` values as a JSON-encoded literal; the template must then NOT load a CMP web tag of its own. |
| Viewability shim | document start | See §4. Installs `window.stepnetwork._onViewability` and the page-side subscribe API. |
| Ad unit id | document end | `window.stepnetwork = window.stepnetwork \|\| {}; window.stepnetwork.adUnitId = '<id>';` |
| Custom targeting | document end | `googletag.cmd.push(function () { googletag.pubads().setTargeting(<key>, <value-or-array>); ... });` Keys/values MUST be JSON-encoded when generating this script — never raw string interpolation. |
| GPT Active View listener | document end | Static script: `googletag.cmd.push(...)` registering an `impressionViewable` listener that posts §2.3 messages. |
| Debug panel + console bridge | document end, debug only | Overlay showing ad unit + size + GPT console button; console method override posting `console` messages (§2.1). |
| GPT visibility probe | document end, debug only | Static script registering a `slotVisibilityChanged` listener that posts §2.4 messages (deduplicated on unchanged percentage). |
| DOM viewport probe | document end, debug only | Static script: `resize` listener that `console.log`s the settled DOM viewport (`[CLIP] DOM viewport now WxH`, 150ms debounce). Verification aid for §4.4 — proves what the page actually sees. |
| Debug page targeting | document end, debug only | `googletag.pubads().setTargeting('yb_target', 'alwayson-standard')` — debug-session page-level targeting; not injected in production. |

### 3.1 Manual render trigger (lazy loading)
When the lazy-load state machine reaches `displayed`, native evaluates:
```js
window.triggerManualAdEvent()            // preferred, registered by the template
// fallback:
window.ayManagerEnv.cmd.push(() => ayManagerEnv.dispatchManualEvent())
```

### 3.2 Remote lazy-load thresholds (native read-back)

Each publisher domain has its own lazy-load distances, configured remotely by
STEP Network. An AY (Yield Manager) variable resolves the domain and writes,
some time AFTER page load:

```js
window.stepnetwork.lazyLoad = { "fetch": 150, "render": 100 };
```

**Units: viewport-height percentage points** (confirmed by ad-ops
2026-07-23 — all STEP lazy loading runs in viewport percentages, never px).
100 = one full viewport; 150 = 1.5 viewports. `fetch` = distance before
viewport entry at which to request the ad; `render` = distance at which to
display it; `fetch ≥ render` always. Native converts against the live
scroll viewport: `distance = viewportHeight × value / 100` (re-derived on
every check, so rotations/resizes are tracked automatically).

Native reads the object back — the page needs no extra code beyond the ad
delivery tag it already carries:

- On `didFinish` navigation (iOS; Android: `onPageFinished`), evaluate a
  constant script returning `JSON.stringify(window.stepnetwork.lazyLoad)` or
  `null`. Poll up to 10 × 500ms (the global appears asynchronously).
  Consistently `null` after that → the AY variable didn't fire (ad-ops issue,
  not an SDK bug); keep current thresholds.
- The payload is untrusted (third-party page JS). Strict validation before
  use: an object with exactly numeric `fetch`/`render`, both finite, > 0,
  ≤ 1000 (%), `fetch ≥ render`. Anything else is ignored.
- On success the config is applied to the live lazy-load manager (re-runs
  visibility immediately): the fetch/display zones derive from the
  percentages; the unload zone is `max(unloadThreshold, fetchDistance)` so
  ads never unload inside the zone that refetches them (hysteresis).
- **Precedence: remote always wins** — over the SDK defaults AND over
  point thresholds the app developer set explicitly (product decision
  2026-07-23). Local values only apply until remote values arrive / when
  none exist.
- **Cache:** the validated config is persisted per template host
  (`UserDefaults` key `sn.lazyLoad.<host>` on iOS; `SharedPreferences` on
  Android) and applied at scroll-view setup on later launches — the fetch
  threshold decides when to *create* the webview, so the very first launch
  necessarily runs on local values until the first page reports.

## 4. Viewability bridge

The DOM inside each ad webview only sees its own viewport (the ad fills it —
`100vw`/`100vh`), so any in-page measurement reports ~100% regardless of real
on-screen position. The native side owns the truth and pushes it in.

### 4.1 Shim (installed at document start by native)
```js
window.stepnetwork.viewability        // latest snapshot (pull model)
window.stepnetwork.onViewability(cb)  // subscribe (push model)
window.addEventListener('snviewability', e => e.detail)  // event model
window.stepnetwork._onViewability(p)  // NATIVE ENTRY POINT — do not call from page code
```

### 4.2 Payload (native → `_onViewability`)
```json
{
  "type": "viewability",
  "adUnitId": "div-gpt-ad-mobile_1",
  "ratio": 0.63,
  "visible": true,
  "dwellMs": 420,
  "thresholdMs": 1000,
  "mode": "display",
  "viewable": false,
  "appActive": true,
  "ts": 1730000000000
}
```
- `ratio` — fraction of the ad creative's pixels inside the effective viewport (0–1, 2 decimals).
- `visible` — `ratio >= 0.5 && appActive`.
- `dwellMs` — current continuous in-view time.
- `thresholdMs` — 1000 (display) or 2000 (video), per IAB/MRC. Today always
  1000: `video` is RESERVED — the engine supports it, but no public API sets
  it (creative type isn't knowable app-side; ActiveView handles video's
  playback-based standard in-page).
- `viewable` — latched verdict for this impression.
- `ts` — wall-clock ms since epoch (`Date.now()`-compatible).
- MUST be produced by a JSON encoder, never string interpolation.

### 4.3 Emit policy (native side)
- Boolean transitions (`visible`, `viewable`, `appActive`) — always sent.
- Ratio-only changes — sent when |Δratio| ≥ 0.05.
- Nothing while idle. Worst case ~4 messages/s per visible ad during scroll.

## 4.4 Viewport resizing (Module-6, DEFAULT — per-ad opt-out)

Native resizes the ad webview to the creative's visible slice
(and sets the page scroll offset to the slice origin) so in-page measurement
(GPT ActiveView) sees the true viewport:

- Applied only AFTER the creative has rendered (first `adSize` message) — ad
  requests never happen into a collapsed viewport.
- The native container keeps the full ad frame; only the webview inside it
  resizes, so layout never shifts.
- Fully hidden → 1pt sliver kept alive (zero frames can suspend media/JS).
- Change-driven with 2pt tolerance; no fixed-rate resizing.
- Android equivalent: resize the WebView inside a stable container and set
  `WebView.scrollTo(x, y)` to the slice origin.

## 5. Viewability state machine (per ad, native side)

IAB/MRC: viewable = ≥50% of pixels for ≥1s (display) / ≥2s (video), CONTINUOUS.
(`video` reserved — see §4.2; every public impression today runs `display`.)

```
idle ──(ratio ≥ 0.5 && appActive)──────────────▶ counting(since: t)
counting ──(ratio < 0.5 || !appActive)─────────▶ idle          // timer RESETS
counting ──(t − since ≥ threshold)─────────────▶ viewable      // latched
viewable ──(reset() on webview recreation)─────▶ idle          // new impression
```

- Backgrounding (app resigns active) resets all running timers — an ad behind
  the app switcher is not human-viewable.
- The verdict latches per impression; a new webview for the same slot = new impression.
- Dwell accrual requires a steady ticker (~10Hz) while counting — geometry
  callbacks alone go quiet when the user stops scrolling.
- Effective viewport = scroll container's visible bounds ∩ window safe area.
  Known limitation: arbitrary floating overlays are not detected.

## 6. Lazy-loading state machine (per ad, native side)

Distances are from the scroll viewport's edges, in points/dp:

```
notLoaded ──(within fetchThreshold, default 800)──▶ fetched     // webview created, HTML loads
fetched ──(within displayThreshold, default 200)──▶ displayed   // manual render trigger fires (§3.1)
fetched|displayed ──(outside unloadThreshold, default 1600, for ≥2s stability, only if unloading enabled)──▶ unloaded
unloaded ──(within fetchThreshold)────────────────▶ notLoaded   // recreate on re-entry
```

- Visibility checks throttled to ~15fps (67ms), leading+trailing edge.
- Unloading defaults to OFF (UX over memory).
- Hysteresis: display-in vs the much larger unload-out distance prevents
  flicker; the unload zone is always at least the fetch distance
  (`max(unloadThreshold, fetchDistance)`, §3.2).
- The fetch/display distances are remotely overridden per publisher domain
  via `window.stepnetwork.lazyLoad` in viewport-height % (§3.2); the point
  values above are the local starting values.

## 7. Configuration surface (per platform)

| Name | Meaning |
|---|---|
| consent provider | SDK-owned Didomi (default; `didomiAPIKey` injected at SDK init — never hardcode in the SDK), app-owned TCF CMP (reads the standardized `IABTCF_*` storage: `UserDefaults` on iOS, `SharedPreferences` on Android), or app-owned Didomi (`AppDidomiConsentProvider` on iOS: gates on Didomi's own answered-state — a TC string published before the user answers does not open the gate — while the page hand-off stays the `__tcfapi` stub). Consent changes AFTER an ad has loaded reload that ad's page (the consent hand-off is a load-time snapshot; the reload triggers only when the provider's hand-off script actually changed). |
| `adTemplateURL` | Base template URL (§1). |
| `fetchThreshold` / `displayThreshold` / `unloadThreshold` | Lazy-load distances in points (default 800/200/1600). Fetch/display are remotely overridden per domain via `window.stepnetwork.lazyLoad` in viewport-height % — remote always wins, even over explicitly set values (§3.2). |
| `unloadingEnabled` | Default `false`. |
| viewability mode | Always `display`. `video` reserved (engine-level only, no public setter — see §4.2). |
| debug toggle | Runtime flag gating all SDK logging + debug panel + `aym_debug`. |

## 8. Android port assessment (honest)

**Transfers 1:1 (this document):** template URL contract, message schemas,
targeting conventions, both state machines, config surface, consent-gating
architecture (the Didomi Android SDK mirrors iOS: initialize / onReady /
event listener / `getJavaScriptForWebView`).

**Must be rewritten per platform (all view/geometry code):**
- `android.webkit.WebView` + `WebViewClient`/`WebChromeClient` instead of
  WKWebView/WKUserScript. Script injection timing differs (no document-start
  user scripts — inject at `onPageStarted`).
- View-position tracking: Compose `onGloballyPositioned` / RecyclerView scroll
  listeners instead of SwiftUI GeometryReader/PreferenceKeys.
- External-URL handling via `Intent.ACTION_VIEW`.
- App-lifecycle: `ProcessLifecycleOwner` / `ON_PAUSE`-`ON_RESUME` instead of
  `willResignActive`/`didBecomeActive`.

**Recommendation:** the portable core logic is ~150 lines; hand-port against
this contract rather than introducing Kotlin Multiplatform.
