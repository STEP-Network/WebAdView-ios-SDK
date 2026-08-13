//
//  Project_AdViewApp.swift
//  Project AdView
//
//

import SwiftUI
import WebAdViewSDK

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // One call replaces the previous hand-rolled Didomi setup.
        // The demo key and STEP Network's test template URL are hardcoded
        // HERE (in the demo app) on purpose — real apps inject their own
        // key and their own template URL, hosted on their own domain.
        WebAdViewSDK.initialize(config: WebAdViewSDKConfig(
            didomiAPIKey: "d0661bea-d696-4069-b308-11057215c4c4",
            adTemplateURL: URL(string: "https://adops.stepdev.dk/wp-content/ad-template.html?didomi-disable-notice=true")!
        ))
        #if DEBUG
        // Test-automation hook: a fresh install wipes stored Didomi consent
        // and this demo has no first-run notice UI, so automated runs would
        // hold ads back forever. Activate with:
        //   xcrun simctl launch <udid> <bundle> -SNConsentAcceptAll YES
        if UserDefaults.standard.bool(forKey: "SNConsentAcceptAll") {
            WebAdViewSDK.acceptAllConsentForTesting()
        }
        #endif
        return true
    }
}

@main
struct Project_AdViewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    var body: some Scene {
        WindowGroup {
            HomepageView()
                .environmentObject(DebugSettings.shared)
        }
    }
}
