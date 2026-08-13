import Foundation

/// Generates the `googletag.pubads().setTargeting(...)` script injected into
/// ad webviews.
///
/// Keys and values are JSON-encoded — never string-interpolated — so quotes,
/// newlines, `</script>`, or any other content in targeting values cannot
/// break out of the generated JavaScript.
public enum TargetingScriptBuilder {

    /// Returns the targeting script for the given parameters, or `nil` when
    /// there is nothing to inject.
    public static func script(for params: [String: [String]]) -> String? {
        guard !params.isEmpty else { return nil }

        // Sorted for deterministic output (stable across runs; testable).
        let calls = params.sorted { $0.key < $1.key }.compactMap { key, values -> String? in
            guard let jsKey = jsonString(key) else { return nil }
            if values.count == 1 {
                guard let jsValue = jsonString(values[0]) else { return nil }
                return "googletag.pubads().setTargeting(\(jsKey), \(jsValue));"
            } else {
                guard let jsArray = jsonString(values) else { return nil }
                return "googletag.pubads().setTargeting(\(jsKey), \(jsArray));"
            }
        }
        guard !calls.isEmpty else { return nil }

        return """
        googletag.cmd.push(function () {
            \(calls.joined(separator: "\n    "))
        });
        """
    }

    /// JSON-encodes a single string (including the surrounding quotes).
    static func jsonString(_ value: String) -> String? {
        encode(value)
    }

    /// JSON-encodes an array of strings.
    static func jsonString(_ values: [String]) -> String? {
        encode(values)
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        // Keep "/" escaped-free output compact; JSONEncoder default is fine.
        guard let data = try? encoder.encode([value]),
              var text = String(data: data, encoding: .utf8) else { return nil }
        // Unwrap the single-element array used to make scalars encodable.
        text = String(text.dropFirst().dropLast())
        // Defense in depth: prevent "</script>" from terminating an inline
        // script block even though these scripts are injected via WKUserScript.
        text = text.replacingOccurrences(of: "</", with: "<\\/")
        return text
    }
}
