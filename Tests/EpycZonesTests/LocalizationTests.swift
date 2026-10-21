import XCTest

/// The string catalog stays complete: every string the app shows has a
/// Brazilian Portuguese translation with the same placeholders.
final class LocalizationTests: XCTestCase {
    private var strings: [String: [String: Any]] = [:]

    override func setUpWithError() throws {
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Localizable.xcstrings")
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: catalog)) as? [String: Any]
        strings = try XCTUnwrap(json?["strings"] as? [String: [String: Any]])
    }

    /// Keys still used by the code; `make strings` marks the others stale.
    private var liveKeys: [String] {
        strings.filter { ($0.value["extractionState"] as? String) != "stale" }.map(\.key)
    }

    func testEveryStringHasABrazilianPortugueseTranslation() {
        let missing = liveKeys.filter { key in
            let localizations = strings[key]?["localizations"] as? [String: Any]
            return localizations?["pt-BR"] == nil
        }
        XCTAssertEqual(missing.sorted(), [], "Translate these in Resources/Localizable.xcstrings")
    }

    func testTranslationsKeepTheirPlaceholders() {
        for key in liveKeys {
            guard let localizations = strings[key]?["localizations"] as? [String: Any],
                  let portuguese = localizations["pt-BR"] as? [String: Any],
                  let unit = portuguese["stringUnit"] as? [String: Any],
                  let value = unit["value"] as? String,
                  portuguese["substitutions"] == nil else { continue }
            XCTAssertEqual(Self.placeholders(value), Self.placeholders(key), key)
        }
    }

    /// Placeholder types in order of their arguments, ignoring positions.
    private static func placeholders(_ format: String) -> [String] {
        let pattern = try! NSRegularExpression(pattern: "%(\\d+\\$)?(lld|@|d)")
        let range = NSRange(format.startIndex..., in: format)
        let matches = pattern.matches(in: format, range: range).enumerated().map { index, match -> (Int, String) in
            let position = Range(match.range(at: 1), in: format).map { Int(format[$0].dropLast()) ?? index + 1 } ?? index + 1
            let type = Range(match.range(at: 2), in: format).map { String(format[$0]) } ?? ""
            return (position, type)
        }
        return matches.sorted { $0.0 < $1.0 }.map(\.1)
    }
}
