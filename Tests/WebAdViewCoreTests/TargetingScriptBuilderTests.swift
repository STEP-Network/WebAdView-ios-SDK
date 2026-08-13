import Testing
@testable import WebAdViewCore

// MARK: - TargetingScriptBuilder tests
//
// The builder must JSON-encode keys/values so no targeting content can break
// out of the generated JavaScript.

@Suite("TargetingScriptBuilder")
struct TargetingScriptBuilderTests {

    @Test("Empty params produce no script")
    func emptyParamsProduceNil() {
        #expect(TargetingScriptBuilder.script(for: [:]) == nil)
    }

    @Test("Single value renders a quoted setTargeting call inside googletag.cmd")
    func singleValue() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["section": ["homepage"]]))
        #expect(script.contains(#"googletag.pubads().setTargeting("section", "homepage");"#))
        #expect(script.contains("googletag.cmd.push(function () {"))
    }

    @Test("Array values render a JSON array")
    func arrayValues() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["cats": ["sports", "news"]]))
        #expect(script.contains(#"setTargeting("cats", ["sports","news"]);"#))
    }

    @Test("Multiple keys render deterministically (sorted by key)")
    func deterministicOrder() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["b": ["2"], "a": ["1"]]))
        let aIndex = try #require(script.range(of: #""a""#)).lowerBound
        let bIndex = try #require(script.range(of: #""b""#)).lowerBound
        #expect(aIndex < bIndex)
    }

    @Test("Quotes in values are escaped, not script-breaking")
    func quotesEscaped() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["k": [#"va"l'ue"#]]))
        #expect(script.contains(#"va\"l'ue"#))
        // The raw quote must not terminate the JSON string (no `"va"` literal).
        #expect(!script.contains(#""va"l"#))
    }

    @Test("Newlines in values are escaped")
    func newlinesEscaped() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["k": ["line1\nline2"]]))
        #expect(script.contains(#"line1\nline2"#))
        #expect(!script.contains("line1\nline2"))
    }

    @Test("</script> cannot appear literally in output")
    func scriptTagNeutralized() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["k": ["</script><script>alert(1)</script>"]]))
        #expect(!script.contains("</script>"))
        #expect(script.contains(#"<\/script>"#))
    }

    @Test("Unicode values survive encoding")
    func unicodeValues() throws {
        let script = try #require(TargetingScriptBuilder.script(for: ["k": ["æøå emoji 🎯"]]))
        #expect(script.contains("æøå emoji 🎯"))
    }

    @Test("Malicious key cannot break out either")
    func maliciousKeyEscaped() throws {
        let script = try #require(TargetingScriptBuilder.script(for: [#"k", "x"); evil(("#: ["v"]]))
        // The key must be encoded as ONE JSON string with its quotes escaped…
        #expect(script.contains(#"k\", \"x\"); evil(("#))
        // …so the raw breakout sequence `("k", "x")` never appears unescaped.
        #expect(!script.contains(#"("k", "x")"#))
    }
}
