import Testing
@testable import WebAdViewSDK

// MARK: - Template URL assembly
//
// `assembleTemplateURLString` must guarantee `didomi-disable-notice=true`
// on every template URL — including app-supplied custom `adTemplateURL`s
// that forgot it (otherwise the Didomi web notice appears inside every ad
// webview on top of the native one).

@Suite("Template URL assembly")
struct TemplateURLAssemblyTests {

    @Test @MainActor func customURLWithoutQueryGetsNoticeSuppression() {
        let url = WebAdViewController.assembleTemplateURLString(
            baseURL: "https://publisher.dk/ads/template.html",
            debugEnabled: false,
            randomValue: "R"
        )
        #expect(url == "https://publisher.dk/ads/template.html?didomi-disable-notice=true&rnd=R")
    }

    @Test @MainActor func customURLWithExistingQueryGetsNoticeSuppression() {
        let url = WebAdViewController.assembleTemplateURLString(
            baseURL: "https://publisher.dk/ads/template.html?site=news",
            debugEnabled: false,
            randomValue: "R"
        )
        #expect(url == "https://publisher.dk/ads/template.html?site=news&didomi-disable-notice=true&rnd=R")
    }

    @Test @MainActor func urlAlreadyCarryingTheParamKeepsSingleOccurrence() {
        // STEP Network's test template URL, as documented in QUICKSTART.md
        let base = "https://adops.stepdev.dk/wp-content/ad-template.html?didomi-disable-notice=true"
        let url = WebAdViewController.assembleTemplateURLString(
            baseURL: base,
            debugEnabled: false,
            randomValue: "R"
        )
        let occurrences = url.components(separatedBy: "didomi-disable-notice").count - 1
        #expect(occurrences == 1)
        #expect(url == "\(base)&rnd=R")
    }

    @Test @MainActor func debugFlagAppendsAymDebug() {
        let url = WebAdViewController.assembleTemplateURLString(
            baseURL: "https://publisher.dk/t.html?didomi-disable-notice=true",
            debugEnabled: true,
            randomValue: "R"
        )
        #expect(url == "https://publisher.dk/t.html?didomi-disable-notice=true&aym_debug=true&rnd=R")
    }
}
