import SwiftUI
import XCTest

@testable import MacMarkDownKit

final class EditorThemeStyleFileTests: XCTestCase {

    func testParsesSolarizedDarkStyleFile() {
        let theme = EditorTheme.styleFile(named: "Solarized (Dark)")
        XCTAssertNotNil(theme)
        XCTAssertEqual(theme?.displayName, "Solarized (Dark)")
        // editor { foreground: 839496 background: 002b36 }
        XCTAssertEqual(theme?.textColor, Color(red: 0x83 / 255.0, green: 0x94 / 255.0, blue: 0x96 / 255.0))
        XCTAssertEqual(theme?.backgroundColor, Color(red: 0x00 / 255.0, green: 0x2b / 255.0, blue: 0x36 / 255.0))
        // editor-selection { background: d33682 }
        XCTAssertEqual(theme?.selectionColor, Color(red: 0xd3 / 255.0, green: 0x36 / 255.0, blue: 0x82 / 255.0))
        // LINK { foreground: 268bd2 }
        XCTAssertEqual(theme?.linkColor, Color(red: 0x26 / 255.0, green: 0x8b / 255.0, blue: 0xd2 / 255.0))
    }

    func testParsesInlineStyleText() {
        let text = """
        editor
        foreground: ff0000
        background: 000000
        caret: 00ff00

        LINK
        foreground: 0000ff
        """
        let theme = EditorTheme.parseStyleFile(text, name: "Test")
        XCTAssertEqual(theme.textColor, Color(red: 1, green: 0, blue: 0))
        XCTAssertEqual(theme.backgroundColor, Color(red: 0, green: 0, blue: 0))
        XCTAssertEqual(theme.cursorColor, Color(red: 0, green: 1, blue: 0))
        XCTAssertEqual(theme.linkColor, Color(red: 0, green: 0, blue: 1))
        // Missing sections fall back to the base foreground.
        XCTAssertEqual(theme.headingColor, theme.textColor)
    }

    func testBundledStyleThemesAreDiscovered() {
        let names = ResourceLoader.availableThemeNames
        XCTAssertTrue(names.contains("Solarized (Dark)"))
        XCTAssertTrue(names.contains("Tomorrow+"))
        XCTAssertTrue(EditorTheme.fileBased.count >= 15)
    }

    func testThemeLookupFindsFileBasedTheme() {
        let theme = EditorTheme.theme(named: "Tomorrow+")
        XCTAssertEqual(theme.displayName, "Tomorrow+")
    }

    func testHexColorParsing() {
        XCTAssertEqual(Color(hexString: "#ff0000"), Color(red: 1, green: 0, blue: 0))
        XCTAssertEqual(Color(hexString: "0f0"), Color(red: 0, green: 1, blue: 0))
        XCTAssertNil(Color(hexString: "not-a-color"))
    }
}