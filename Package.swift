// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WebAdViewSDK",
    platforms: [
        .iOS(.v16),
        // Core is pure logic; declaring macOS enables fast host-side iteration
        // (`swift build --target WebAdViewCore`). The SDK product is iOS-only
        // in practice — Didomi ships no macOS slice.
        .macOS(.v11),
    ],
    products: [
        .library(name: "WebAdViewSDK", targets: ["WebAdViewSDK"]),
    ],
    dependencies: [
        .package(url: "https://github.com/didomi/didomi-ios-sdk-spm", from: "2.44.0"),
        // NOTE: GoogleMobileAds deliberately absent — ads render via GPT inside
        // the WKWebView; the native GMA SDK was linked but never imported.
    ],
    targets: [
        // Pure logic — no Didomi/WebKit/UIKit. Unit-testable anywhere.
        .target(name: "WebAdViewCore"),
        // Full SDK — SwiftUI/WebKit/Didomi. Re-exports Core.
        .target(
            name: "WebAdViewSDK",
            dependencies: [
                "WebAdViewCore",
                .product(name: "Didomi", package: "didomi-ios-sdk-spm"),
            ],
            linkerSettings: [
                // Required by the Didomi binary xcframework when consumed
                // from a package target.
                .linkedFramework("JavaScriptCore"),
                .linkedFramework("SystemConfiguration"),
            ]
        ),
        .testTarget(
            name: "WebAdViewCoreTests",
            dependencies: ["WebAdViewCore"]
        ),
        // Imports Didomi transitively — runs on iOS simulator only (not `swift test`).
        .testTarget(
            name: "WebAdViewSDKTests",
            dependencies: ["WebAdViewSDK"]
        ),
    ]
)
