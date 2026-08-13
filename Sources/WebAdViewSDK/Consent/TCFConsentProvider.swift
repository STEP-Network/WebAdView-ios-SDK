import Foundation

/// `ConsentProvider` for apps that already run their own TCF-certified CMP
/// (Didomi, Cookiebot, OneTrust, Usercentrics, …). The SDK does not show any
/// consent UI in this mode — it reads the user's answer from the IAB TCF
/// standard location (`UserDefaults`, the `IABTCF_*` keys every certified
/// CMP is required to maintain) and hands it to the ad page through a
/// standard in-app-webview `__tcfapi` stub, so GPT/Yield Manager can read
/// consent in-page.
///
/// Requirements (see GUIDE.md "Bringing your own CMP"):
/// - The app's CMP must be TCF-registered (it writes `IABTCF_TCString`).
/// - The ad template page must NOT load a CMP web tag of its own —
///   coordinate the template with STEP Network.
public final class TCFConsentProvider: NSObject, ConsentProvider {

    private static let tcStringKey = "IABTCF_TCString"
    private static let gdprAppliesKey = "IABTCF_gdprApplies"

    private let defaults: UserDefaults
    private var onChange: (() -> Void)?
    private var isObserving = false

    /// - Parameter defaults: injectable for tests; TCF-certified CMPs write
    ///   to `UserDefaults.standard`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
    }

    deinit {
        if isObserving {
            defaults.removeObserver(self, forKeyPath: Self.tcStringKey)
            defaults.removeObserver(self, forKeyPath: Self.gdprAppliesKey)
        }
    }

    /// True once the app's CMP has recorded an answer: a TC string exists,
    /// or the CMP determined GDPR does not apply (`IABTCF_gdprApplies == 0`,
    /// distinguished from the key being absent).
    public var isConsentDetermined: Bool {
        if let tcString = defaults.string(forKey: Self.tcStringKey), !tcString.isEmpty {
            return true
        }
        return (defaults.object(forKey: Self.gdprAppliesKey) as? Int) == 0
    }

    public func start(onChange: @escaping () -> Void) {
        self.onChange = onChange
        defaults.addObserver(self, forKeyPath: Self.tcStringKey, options: [], context: nil)
        defaults.addObserver(self, forKeyPath: Self.gdprAppliesKey, options: [], context: nil)
        isObserving = true
        // Consent may already be stored from a previous launch — open the
        // gate immediately instead of waiting for the next CMP write.
        onChange()
    }

    // swiftlint:disable:next block_based_kvo
    public override func observeValue(
        forKeyPath keyPath: String?,
        of object: Any?,
        change: [NSKeyValueChangeKey: Any]?,
        context: UnsafeMutableRawPointer?
    ) {
        debugPrint("[SN] [NATIVE] TCFConsentProvider: \(keyPath ?? "IABTCF") changed")
        onChange?()
    }

    /// The TC string crosses into JavaScript — encoded via JSONEncoder and
    /// spliced only as a JSON object literal (never raw interpolation), so a
    /// corrupt/hostile UserDefaults value stays a JS string value.
    public func javaScriptForWebView() -> String {
        struct Payload: Encodable {
            let tcString: String
            let gdprApplies: Bool?
        }
        let gdprApplies = (defaults.object(forKey: Self.gdprAppliesKey) as? Int).map { $0 != 0 }
        let payload = Payload(
            tcString: defaults.string(forKey: Self.tcStringKey) ?? "",
            gdprApplies: gdprApplies
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        // Minimal IAB-standard __tcfapi stub for in-app webviews: consent is
        // final at injection time, so every command answers from the same
        // snapshot with eventStatus 'tcloaded'.
        return """
        (function () {
            var tc = \(json);
            var nextListenerId = 1;
            function tcData(listenerId) {
                return {
                    tcString: tc.tcString,
                    gdprApplies: tc.gdprApplies,
                    tcfPolicyVersion: 2,
                    cmpStatus: 'loaded',
                    eventStatus: 'tcloaded',
                    listenerId: listenerId === undefined ? null : listenerId
                };
            }
            window.__tcfapi = function (command, version, callback, parameter) {
                if (command === 'ping') {
                    callback({
                        gdprApplies: tc.gdprApplies,
                        cmpLoaded: true,
                        cmpStatus: 'loaded',
                        displayStatus: 'disabled',
                        apiVersion: '2.2'
                    });
                } else if (command === 'getTCData') {
                    callback(tcData(), true);
                } else if (command === 'addEventListener') {
                    callback(tcData(nextListenerId++), true);
                } else if (command === 'removeEventListener') {
                    callback(true);
                } else {
                    callback(null, false);
                }
            };
        })();
        """
    }

    public func showPreferences() {
        debugPrint("""
        [SN] [NATIVE] TCFConsentProvider: showPreferences() is a no-op — \
        this app owns its CMP; open that CMP's preferences UI from the app.
        """)
    }
}
