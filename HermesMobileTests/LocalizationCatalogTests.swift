import XCTest

/// Guards the App Localization effort (issues #290, #291, …): every translatable key in
/// `Localizable.xcstrings` must carry a non-empty value in **each shipped language**. This
/// catches a dropped/forgotten translation before it ships as a blank string in that
/// language's build.
///
/// The catalog is JSON on disk; we read the source file directly (located relative to
/// this test via `#filePath`) so the guard runs without bundling the catalog into the
/// test target. Keys explicitly marked `"shouldTranslate": false` (brand names,
/// format-only artifacts) are intentionally skipped.
///
/// When a new language is added to the catalog, add its code to `shippedLanguages` so the
/// guard covers it too.
final class LocalizationCatalogTests: XCTestCase {

    /// Non-English languages compiled into the app. Keep in sync with `knownRegions` in the
    /// project file and the languages present in `Localizable.xcstrings`.
    private static let shippedLanguages = ["de", "es", "fr", "it", "pl", "pt-BR", "nl", "tr", "ru", "ja", "zh-Hans", "ko", "ar", "he", "ur", "zh-Hant", "zh-HK"]

    private func resourceURL(_ relativePath: String) -> URL {
        // .../HermesMobileTests/LocalizationCatalogTests.swift
        //   -> repo root -> HermesMobile/Resources/<relativePath>
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // HermesMobileTests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("HermesMobile/Resources")
            .appendingPathComponent(relativePath)
    }

    private func catalogURL() -> URL {
        resourceURL("Localizable.xcstrings")
    }

    /// True iff the language entry holds a non-empty value — either a plain `stringUnit` or
    /// a `plural` variation where every category is filled.
    private func hasNonEmptyValue(_ localization: [String: Any]) -> Bool {
        if let value = (localization["stringUnit"] as? [String: Any])?["value"] as? String {
            return !value.isEmpty
        }
        if let plural = ((localization["variations"] as? [String: Any])?["plural"] as? [String: Any]), !plural.isEmpty {
            return plural.values.allSatisfy { cat in
                let value = ((cat as? [String: Any])?["stringUnit"] as? [String: Any])?["value"] as? String
                return !(value ?? "").isEmpty
            }
        }
        return false
    }

    func testShippedLanguageTranslationsHaveNoEmptyValues() throws {
        let url = catalogURL()
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("Could not read String Catalog at \(url.path); skipping — the source tree is not present in this environment (e.g. on a physical device or a remote test runner). Runs on the simulator/CI where the checkout exists.")
        }
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(root["sourceLanguage"] as? String, "en", "Development language should remain English.")
        let strings = try XCTUnwrap(root["strings"] as? [String: Any])
        XCTAssertGreaterThan(strings.count, 200, "Catalog is unexpectedly small — string extraction may have regressed.")

        for language in Self.shippedLanguages {
            var missing: [String] = []
            var translated = 0

            for (key, rawEntry) in strings {
                guard let entry = rawEntry as? [String: Any] else { continue }
                if entry["shouldTranslate"] as? Bool == false { continue }   // intentionally excluded

                guard let localization = (entry["localizations"] as? [String: Any])?[language] as? [String: Any] else {
                    missing.append(key)
                    continue
                }
                hasNonEmptyValue(localization) ? (translated += 1) : missing.append(key)
            }

            XCTAssertTrue(missing.isEmpty,
                          "[\(language)] \(missing.count) translatable key(s) have no value: \(missing.sorted())")
            XCTAssertGreaterThan(translated, 200, "[\(language)] Far fewer translations than expected — something dropped.")
        }
    }

    func testAppTransportSecurityAllowsTailscaleHTTPRange() throws {
        let url = resourceURL("Info.plist")
        guard let data = try? Data(contentsOf: url) else {
            throw XCTSkip("Could not read Info.plist at \(url.path); skipping — the source tree is not present in this environment.")
        }

        let root = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let ats = try XCTUnwrap(root["NSAppTransportSecurity"] as? [String: Any])
        XCTAssertEqual(ats["NSAllowsLocalNetworking"] as? Bool, true)

        let exceptionDomains = try XCTUnwrap(ats["NSExceptionDomains"] as? [String: Any])
        let tailscaleRange = try XCTUnwrap(exceptionDomains["100.64.0.0/10"] as? [String: Any])
        XCTAssertEqual(tailscaleRange["NSExceptionAllowsInsecureHTTPLoads"] as? Bool, true)
    }
}
