import XCTest
@testable import CachedRemoteImage

/// The user-facing strings resolve to Japanese.
///
/// 5.0.0 replaced the Japanese messages with English literals and nothing to translate them, so a
/// Japanese app showing the default error view showed English. These tests pin both halves of the
/// fix: every string the sources look up has a Japanese entry, and the built bundle serves it.
final class LocalizationTests: XCTestCase {

    private static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let sourcesDirectory = packageRoot.appendingPathComponent("Sources/CachedRemoteImage")

    private static let catalogURL = sourcesDirectory.appendingPathComponent("Resources/Localizable.xcstrings")

    /// The catalog's keys mapped to their Japanese value, or `nil` when the key has no translated `ja`.
    private func japaneseByKey() throws -> [String: String?] {
        let data = try Data(contentsOf: Self.catalogURL)
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        return strings.mapValues { entry in
            let localizations = entry["localizations"] as? [String: Any]
            let unit = (localizations?["ja"] as? [String: Any])?["stringUnit"] as? [String: Any]
            guard unit?["state"] as? String == "translated" else { return nil }
            return unit?["value"] as? String
        }
    }

    /// Every literal handed to `String(localized:bundle: .module)` or `Text(_:bundle: .module)`.
    private func lookedUpKeys() throws -> Set<String> {
        let pattern = try NSRegularExpression(
            pattern: #"(?:String\(\s*localized:|Text\()\s*"((?:[^"\\]|\\.)*)"\s*,\s*bundle:\s*\.module"#
        )
        var keys: Set<String> = []
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: Self.sourcesDirectory, includingPropertiesForKeys: nil))
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            let range = NSRange(source.startIndex..., in: source)
            for match in pattern.matches(in: source, range: range) {
                keys.insert(String(source[Range(match.range(at: 1), in: source)!]))
            }
        }
        return keys
    }

    func testEveryLookedUpStringHasJapanese() throws {
        let catalog = try japaneseByKey()
        let keys = try lookedUpKeys()
        XCTAssertFalse(keys.isEmpty, "The source scan found no localized lookups; the pattern no longer matches the code.")

        for key in keys.sorted() {
            guard let japanese = catalog[key] else {
                XCTFail("\"\(key)\" is looked up but missing from Localizable.xcstrings")
                continue
            }
            XCTAssertNotNil(japanese, "\"\(key)\" has no translated Japanese")
        }
    }

    func testCatalogHasNoUnusedKeys() throws {
        let used = try lookedUpKeys()
        for key in try japaneseByKey().keys.sorted() {
            XCTAssertTrue(used.contains(key), "\"\(key)\" is in the catalog but nothing looks it up")
        }
    }

    // MARK: - The built bundle

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(
            Bundle.module.path(forResource: language, ofType: "lproj"),
            "The CachedRemoteImage resource bundle ships no \(language).lproj"
        )
        return try XCTUnwrap(Bundle(path: path))
    }

    func testErrorMessagesAreJapanese() throws {
        let ja = try bundle(for: "ja")
        let en = try bundle(for: "en")
        let expected: [(error: ImageLoadError, english: String, japanese: String)] = [
            (.libraryNotConfigured, "Image loading isn't set up", "画像の読み込みが設定されていません"),
            (.invalidURL("x"), "That image address isn't valid", "無効な画像URLです"),
            (.transportFailed(reason: "x"), "Couldn't load the image", "画像の読み込みに失敗しました"),
            (.notAnImage(byteCount: 0), "Couldn't display the image", "画像を表示できませんでした"),
        ]
        for (error, english, japanese) in expected {
            XCTAssertEqual(ja.localizedString(forKey: english, value: nil, table: nil), japanese)
            XCTAssertEqual(en.localizedString(forKey: english, value: nil, table: nil), english)
            // `localizedMessage` resolves in the test process's language, which is one of the two.
            XCTAssertTrue([english, japanese].contains(error.localizedMessage), error.localizedMessage)
        }
    }

    func testRetryButtonIsJapanese() throws {
        let ja = try bundle(for: "ja")
        XCTAssertEqual(ja.localizedString(forKey: "Retry", value: nil, table: nil), "再試行")
    }

    /// A bundle that ships only `ja.lproj` hands Japanese to every language, English included,
    /// because it is the only localization to choose from. English needs its own `en.lproj`.
    func testEachLanguageGetsItsOwnStrings() {
        let localizations = Bundle.module.localizations
        XCTAssertEqual(Bundle.module.developmentLocalization, "en")
        XCTAssertTrue(localizations.contains("en"), "No en.lproj: \(localizations)")
        XCTAssertTrue(localizations.contains("ja"), "No ja.lproj: \(localizations)")

        func chosen(for preferences: [String]) -> String? {
            Bundle.preferredLocalizations(from: localizations, forPreferences: preferences).first
        }
        XCTAssertEqual(chosen(for: ["ja-JP"]), "ja")
        XCTAssertEqual(chosen(for: ["en-US"]), "en")
    }
}
