import XCTest
@testable import MacMarkDownKit

/// The settings sliders draw a tick at the factory default and reset the value
/// to it when the tick is clicked, so a fresh install must actually get that
/// value — the constants and the initializer may never drift apart.
final class PreferencesTests: XCTestCase {

    @MainActor
    private func freshPreferences() -> Preferences {
        let name = "MacMarkDownPreferencesTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return Preferences(defaults: defaults)
    }

    /// The math parse options follow the HTML preferences: TeX-like math is on
    /// by default, inline `$…$` is opt-in, and
    /// the inline toggle alone cannot enable math parsing.
    @MainActor
    func testMathParseOptionsFollowTheRenderingPreferences() {
        let preferences = freshPreferences()
        XCTAssertTrue(preferences.parseOptions.enableMath)
        XCTAssertFalse(preferences.parseOptions.enableInlineMath)

        preferences.htmlMathJaxInlineDollar = true
        XCTAssertTrue(preferences.parseOptions.enableInlineMath)

        preferences.htmlMathJax = false
        XCTAssertFalse(preferences.parseOptions.enableMath)
        XCTAssertFalse(
            preferences.parseOptions.enableInlineMath,
            "inline math needs the TeX-math preference too"
        )
    }

    @MainActor
    func testEditorSlidersDefaultToTheFactoryDefaults() {
        let preferences = freshPreferences()
        XCTAssertEqual(
            preferences.editorBaseFontSize,
            Preferences.defaultEditorBaseFontSize,
            "the Size slider resets to the factory default"
        )
        XCTAssertEqual(
            preferences.editorLineSpacing,
            Preferences.defaultEditorLineSpacing,
            "the Line Spacing slider resets to the factory default"
        )
        XCTAssertEqual(
            preferences.editorMaximumWidth,
            Preferences.defaultEditorMaximumWidth,
            "the Max Width slider resets to the factory default"
        )
        XCTAssertEqual(
            preferences.editorHorizontalInset,
            Preferences.defaultEditorHorizontalInset,
            "the Horizontal Inset slider resets to the factory default"
        )
        XCTAssertEqual(
            preferences.editorVerticalInset,
            Preferences.defaultEditorVerticalInset,
            "the Vertical Inset slider resets to the factory default"
        )
    }

    /// A fresh install uses the system font: the empty name (the editor renders
    /// the system monospaced face) at the factory size.
    @MainActor
    func testEditorFontDefaultsToTheSystemFont() {
        let preferences = freshPreferences()
        XCTAssertEqual(preferences.editorBaseFontName, FontResolver.systemFontName)
        XCTAssertEqual(preferences.editorBaseFontSize, Preferences.defaultEditorBaseFontSize)
    }

    /// The legacy `SF Mono` default is folded into the system name when the
    /// preferences load, so both panes resolve it through one explicit branch.
    @MainActor
    func testLegacyStoredFontNameNormalizesToTheSystemName() {
        let name = "MacMarkDownPreferencesLegacyFontTests"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defaults.set("SF Mono", forKey: "editorFontName")
        defaults.set("SF Mono", forKey: "previewFontName")

        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.editorBaseFontName, FontResolver.systemFontName)
        XCTAssertEqual(preferences.previewFontName, FontResolver.systemFontName)
    }

    /// The preview's family follows the preview font policy: the editor's font
    /// by default, the system font, or its own custom family.
    @MainActor
    func testPreviewFontPolicyPicksThePreviewFamily() {
        let preferences = freshPreferences()
        XCTAssertEqual(preferences.previewFontPolicy, .followEditor)
        XCTAssertEqual(preferences.previewFontFamily, preferences.editorBaseFontName)

        preferences.previewFontPolicy = .system
        XCTAssertEqual(preferences.previewFontFamily, FontResolver.systemFontName)

        preferences.previewFontName = "Georgia"
        preferences.previewFontPolicy = .custom
        XCTAssertEqual(preferences.previewFontFamily, "Georgia")

        // Following the editor picks up a font change without touching the
        // preview's own settings.
        preferences.previewFontPolicy = .followEditor
        preferences.editorBaseFontName = "Menlo"
        XCTAssertEqual(preferences.previewFontFamily, "Menlo")
    }
}
