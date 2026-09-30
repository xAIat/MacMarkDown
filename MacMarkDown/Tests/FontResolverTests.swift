import AppKit
import XCTest
@testable import MacMarkDownKit

/// The Font setting resolves through one explicit branch: the empty name means
/// the system font — the monospaced face (SF Mono) for the editor, the
/// proportional face (SF Pro, with PingFang SC for Chinese) for the preview —
/// and every other name resolves by PostScript name or family name.
final class FontResolverTests: XCTestCase {

    /// Earlier versions stored the literal `SF Mono`, which is not a resolvable
    /// family (the face is only reachable through AppKit, and CoreText silently
    /// substitutes Helvetica for the name), so it folds into the system name.
    func testLegacySystemMonospacedNamesNormalizeToTheSystemName() {
        XCTAssertEqual(FontResolver.normalized("SF Mono"), FontResolver.systemFontName)
        XCTAssertEqual(FontResolver.normalized("SFMono-Regular"), FontResolver.systemFontName)
        XCTAssertEqual(FontResolver.normalized("  SF Mono  "), FontResolver.systemFontName)
        XCTAssertEqual(FontResolver.normalized(nil), FontResolver.systemFontName)
        XCTAssertEqual(FontResolver.normalized("Menlo"), "Menlo")
    }

    @MainActor
    func testResolvesPostScriptAndFamilyNames() {
        XCTAssertEqual(FontResolver.font(named: "Menlo-Regular", size: 14)?.fontName, "Menlo-Regular")
        XCTAssertEqual(
            FontResolver.font(named: "Menlo", size: 14)?.fontName,
            "Menlo-Regular",
            "a family name must resolve to its regular face"
        )
        XCTAssertNil(FontResolver.font(named: FontResolver.systemFontName, size: 14))
        XCTAssertNil(FontResolver.font(named: "NoSuchFont-1234", size: 14))
    }

    /// The system name and unresolvable names keep each pane's own system face
    /// instead of leaving the text unstyled.
    @MainActor
    func testSystemAndUnknownNamesUseEachPanesSystemFace() {
        let systemMono = NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        XCTAssertEqual(FontResolver.editorFont(named: FontResolver.systemFontName, size: 14), systemMono)
        XCTAssertEqual(FontResolver.editorFont(named: "SF Mono", size: 14), systemMono)
        XCTAssertEqual(FontResolver.editorFont(named: "NoSuchFont-1234", size: 14), systemMono)

        XCTAssertEqual(FontResolver.previewFont(named: FontResolver.systemFontName, size: 14), .systemFont(ofSize: 14))
        XCTAssertEqual(FontResolver.previewFont(named: "SF Mono", size: 14), .systemFont(ofSize: 14))
        XCTAssertEqual(FontResolver.previewFont(named: "NoSuchFont-1234", size: 14), .systemFont(ofSize: 14))
    }

    @MainActor
    func testPreviewFontAppliesTheFamilyBoldFace() {
        XCTAssertEqual(
            FontResolver.previewFont(named: "Helvetica", size: 14, weight: .bold).fontName,
            "Helvetica-Bold"
        )
    }

    /// The synthetic italic a run gets when no real italic face covers it:
    /// a horizontal shear at the configured angle, with the size preserved so
    /// it drops into an attributed run next to the family's own faces.
    @MainActor
    func testSyntheticItalicShearsTheFaceWithoutChangingItsSize() throws {
        let menlo = try XCTUnwrap(NSFont(name: "Menlo-Regular", size: 14))
        let sheared = FontResolver.syntheticItalic(menlo)
        let matrix = CTFontGetMatrix(sheared as CTFont)
        XCTAssertEqual(matrix.a, 1, accuracy: 0.0001)
        XCTAssertEqual(matrix.d, 1, accuracy: 0.0001)
        XCTAssertEqual(
            matrix.c,
            CGFloat(tan(FontResolver.syntheticItalicAngle * .pi / 180)),
            accuracy: 0.0001,
            "the shear must use the configured synthetic-italic angle"
        )
        XCTAssertEqual(sheared.pointSize, 14, "the shear must not resize the run")
    }

    /// Drives the settings hint: a Latin monospaced family is not enough (it has
    /// no Chinese glyphs), and a proportional Chinese face is not either.
    @MainActor
    func testMonospacedCJKDetection() throws {
        XCTAssertFalse(FontResolver.isMonospacedCJK("Menlo"), "Menlo has no Chinese glyphs")
        XCTAssertFalse(FontResolver.isMonospacedCJK("PingFang SC"), "PingFang is proportional")
        XCTAssertFalse(FontResolver.isMonospacedCJK(FontResolver.systemFontName))

        guard FontResolver.font(named: "BIZ UDGothic", size: 14) != nil else {
            throw XCTSkip("BIZ UDGothic is not installed on this system")
        }
        XCTAssertTrue(
            FontResolver.isMonospacedCJK("BIZ UDGothic"),
            "a fixed-pitch family with Chinese coverage must be recognized"
        )
    }
}
