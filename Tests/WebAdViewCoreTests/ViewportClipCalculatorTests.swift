import Testing
import CoreGraphics
@testable import WebAdViewCore

// MARK: - ViewportClipCalculator tests (Module-6 viewport resizing)

private let viewport = CGRect(x: 0, y: 0, width: 400, height: 800)

@Suite("ViewportClipCalculator")
struct ViewportClipCalculatorTests {

    @Test("Fully visible ad needs no clipping (slice == full ad bounds, offset zero)")
    func fullyVisible() {
        let ad = CGRect(x: 40, y: 300, width: 320, height: 250)
        let clip = ViewportClipCalculator.clip(adFrame: ad, viewport: viewport)
        #expect(clip.isFullyVisible)
        #expect(!clip.isFullyHidden)
        #expect(clip.sliceFrame == CGRect(x: 0, y: 0, width: 320, height: 250))
        #expect(clip.contentOffset == .zero)
    }

    @Test("Ad scrolled half past the top: slice starts mid-creative, offset matches")
    func clippedFromTop() {
        // Ad's top 125pt are above the viewport.
        let ad = CGRect(x: 40, y: -125, width: 320, height: 250)
        let clip = ViewportClipCalculator.clip(adFrame: ad, viewport: viewport)
        #expect(!clip.isFullyVisible && !clip.isFullyHidden)
        #expect(clip.sliceFrame == CGRect(x: 0, y: 125, width: 320, height: 125))
        #expect(clip.contentOffset == CGPoint(x: 0, y: 125))
    }

    @Test("Ad entering from the bottom: slice is the creative's top, no offset")
    func clippedFromBottom() {
        // Only the top 100pt are inside the viewport.
        let ad = CGRect(x: 40, y: 700, width: 320, height: 250)
        let clip = ViewportClipCalculator.clip(adFrame: ad, viewport: viewport)
        #expect(clip.sliceFrame == CGRect(x: 0, y: 0, width: 320, height: 100))
        #expect(clip.contentOffset == .zero)
    }

    @Test("Horizontal clipping works the same way")
    func clippedHorizontally() {
        // Left 60pt outside the viewport.
        let ad = CGRect(x: -60, y: 300, width: 320, height: 250)
        let clip = ViewportClipCalculator.clip(adFrame: ad, viewport: viewport)
        #expect(clip.sliceFrame == CGRect(x: 60, y: 0, width: 260, height: 250))
        #expect(clip.contentOffset == CGPoint(x: 60, y: 0))
    }

    @Test("Fully offscreen ad is fully hidden with a zero slice")
    func fullyOffscreen() {
        let ad = CGRect(x: 40, y: 900, width: 320, height: 250)
        let clip = ViewportClipCalculator.clip(adFrame: ad, viewport: viewport)
        #expect(clip.isFullyHidden)
        #expect(clip.sliceFrame == .zero)
    }

    @Test("Zero-size ad and null viewport are safe")
    func degenerateInputs() {
        #expect(ViewportClipCalculator.clip(adFrame: .zero, viewport: viewport).isFullyHidden)
        #expect(ViewportClipCalculator.clip(adFrame: CGRect(x: 0, y: 0, width: 320, height: 250), viewport: .null).isFullyHidden)
        #expect(ViewportClipCalculator.clip(adFrame: CGRect(x: 0, y: 0, width: 320, height: 250), viewport: .zero).isFullyHidden)
    }

    @Test("differsSignificantly ignores sub-tolerance jitter, catches real change")
    func significanceThreshold() {
        let base = ViewportClipCalculator.clip(
            adFrame: CGRect(x: 0, y: 700, width: 320, height: 250), viewport: viewport)
        let jitter = ViewportClipCalculator.clip(
            adFrame: CGRect(x: 0, y: 701, width: 320, height: 250), viewport: viewport)
        let real = ViewportClipCalculator.clip(
            adFrame: CGRect(x: 0, y: 740, width: 320, height: 250), viewport: viewport)
        #expect(!ViewportClipCalculator.differsSignificantly(base, jitter))
        #expect(ViewportClipCalculator.differsSignificantly(base, real))
    }
}
