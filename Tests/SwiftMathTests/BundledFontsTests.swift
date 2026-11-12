import XCTest
@testable import SwiftMath

/// The maths fonts the ocdnotes branch adds, by resource name: each loads with
/// its maths table and typesets an expression that leans on that table —
/// stretched delimiters, a fraction, a radical, blackboard letters.
final class BundledFontsTests: XCTestCase {

    static let added = [
        "NewCMMath-Regular", "NewCMMath-Book", "NewCMMath-Bold",
        "texgyrepagella-math", "texgyrebonum-math", "texgyreschola-math",
        "KpMath-Regular", "KpMath-Semibold", "KpMath-Bold",
    ]

    func testEachFontTypesets() throws {
        let latex = #"\left\{ \frac{a+1}{b^{2}} \;\middle|\; \sqrt{y} \in \mathbb{F}^{n} \right\}"#
        for name in Self.added {
            let font = try XCTUnwrap(MTFontManager.manager.font(withName: name, size: 20), name)
            XCTAssertNotNil(font.mathTable, name)
            let display = try XCTUnwrap(
                MTTypesetter.createLineForMathList(MTMathListBuilder.build(fromString: latex), font: font,
                                                   style: .display, separatesStatements: true), name)
            XCTAssertGreaterThan(display.width, 0, name)
            XCTAssertGreaterThan(display.ascent + display.descent, 20, name)
        }
    }
}
