import XCTest
@testable import SwiftMath

/// A letter after a superscript, drawn in under it when asked: `B^2A` as close as `B^2T`.
final class MTTuckTests: XCTestCase {

    /// The fonts checked: the default, and New Computer Modern, which OCDNotes sets maths in.
    private var fonts: [MTFont] {
        [MTFontManager.fontManager.defaultFont!,
         MTFontManager.fontManager.font(withName: "NewCMMath-Book", size: 30)!]
    }

    private func typeset(_ latex: String, font: MTFont, tucks: Bool,
                         style: MTLineStyle = .display) throws -> MTMathListDisplay {
        let list = try XCTUnwrap(MTMathListBuilder.build(fromString: latex), latex)
        return try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: style,
                                                                tucksUnderSuperscripts: tucks), latex)
    }

    /// Every line of glyphs in `display`, nested ones included, in its coordinates, in order.
    private func lines(in display: MTMathListDisplay, offset: CGPoint = .zero) -> [(MTCTLineDisplay, CGPoint)] {
        var found: [(MTCTLineDisplay, CGPoint)] = []
        for sub in display.subDisplays {
            if let line = sub as? MTCTLineDisplay {
                found.append((line, CGPoint(x: offset.x + line.position.x, y: offset.y + line.position.y)))
            } else if let list = sub as? MTMathListDisplay {
                found += lines(in: list, offset: CGPoint(x: offset.x + list.position.x, y: offset.y + list.position.y))
            } else if let fraction = sub as? MTFractionDisplay {
                let origin = CGPoint(x: offset.x, y: offset.y)
                if let numerator = fraction.numerator { found += lines(in: numerator, offset: origin) }
                if let denominator = fraction.denominator { found += lines(in: denominator, offset: origin) }
            }
        }
        return found
    }

    /// Where the last `letter` (math italic, as set) is drawn: its pen position, inside
    /// whichever line holds it.
    private func x(of letter: String, in display: MTMathListDisplay) throws -> CGFloat {
        let italic = changeFont(letter, fontStyle: .defaultStyle)
        for (line, origin) in lines(in: display).reversed() {
            guard let string = line.attributedString?.string as NSString? else { continue }
            let range = string.range(of: italic, options: .backwards)
            if range.location != NSNotFound {
                return origin.x + CTLineGetOffsetForStringIndex(line.line, range.location, nil)
            }
        }
        XCTFail("no \(letter)")
        return 0
    }

    /// How far `letter` moves in `latex` with tucking on.
    private func tuck(_ latex: String, letter: String, font: MTFont) throws -> CGFloat {
        try x(of: letter, in: typeset(latex, font: font, tucks: false))
            - x(of: letter, in: typeset(latex, font: font, tucks: true))
    }

    private func em(_ font: MTFont) -> CGFloat { font.fontSize }

    private func name(_ font: MTFont) -> String { CTFontCopyPostScriptName(font.ctFont) as String }

    // MARK: Off unless asked

    func testOffByDefault() throws {
        for font in fonts {
            let list = try XCTUnwrap(MTMathListBuilder.build(fromString: "B^2A"))
            let plain = try XCTUnwrap(MTTypesetter.createLineForMathList(list, font: font, style: .display))
            XCTAssertEqual(try x(of: "A", in: plain), try x(of: "A", in: typeset("B^2A", font: font, tucks: false)))
        }
    }

    func testTheSettingDoesNotOutliveTheTypesetting() throws {
        _ = try typeset("B^2A", font: fonts[0], tucks: true)
        XCTAssertFalse(MTTypesetter.tucksUnderSuperscripts)
    }

    // MARK: Slanted and upright letters

    /// Letters whose stroke leans away from the superscript: their foot reaches left of where
    /// they stand beside it.
    func testASlantedLetterIsDrawnIn() throws {
        for font in fonts {
            for letter in ["A", "J"] {
                let shift = try tuck("B^2\(letter)", letter: letter, font: font)
                XCTAssertGreaterThan(shift, 0.1 * em(font), "\(letter) in \(name(font))")
            }
        }
    }

    /// Letters already at their leftmost beside the superscript — the bar of a T, the top
    /// serifs of a V — stay where they are.
    func testALetterLeftmostAtTheTopStays() throws {
        for font in fonts {
            for letter in ["T", "V", "W", "Y"] {
                let shift = try tuck("B^2\(letter)", letter: letter, font: font)
                XCTAssertLessThan(shift, 0.02 * em(font), "\(letter) in \(name(font))")
            }
        }
    }

    /// Every capital ends up about as close beside the superscript as a T is: the space after a
    /// script, give or take the tip of a serif.
    func testCapitalsEndAsCloseAsT() throws {
        for font in fonts {
            let step = em(font) / 64
            func gap(_ letter: String) throws -> CGFloat {
                let display = try typeset("B^2\(letter)", font: font, tucks: true)
                let script = try XCTUnwrap(display.subDisplays.first { ($0 as? MTMathListDisplay)?.type == .superscript })
                let scriptInk = MTInkProfile(display: script, step: step)
                let (line, _) = try XCTUnwrap(lines(in: display).last)
                let letterInk = MTInkProfile(display: line, step: step)
                return try XCTUnwrap(scriptInk.rows.keys.compactMap { row -> CGFloat? in
                    guard let left = letterInk.left(row), let right = scriptInk.right(row) else { return nil }
                    return left - right
                }.min(), letter)
            }
            let t = try gap("T")
            for letter in ["A", "B", "E", "J", "P", "R"] {
                XCTAssertEqual(try gap(letter), t, accuracy: 0.08 * em(font), "\(letter) in \(name(font))")
            }
        }
    }

    func testALetterIsNeverPushedRight() throws {
        for font in fonts {
            for latex in ["B^2A", "x^2y", "B^{10}A", "f^2V", "P^2W", "B^2a", "B^\\prime A"] {
                let letter = String(latex.last!)
                XCTAssertGreaterThanOrEqual(try tuck(latex, letter: letter, font: font), 0, latex)
            }
        }
    }

    // MARK: Clear of everything

    /// The letter keeps the space after a script clear of the superscript's ink.
    func testTheSuperscriptStaysClear() throws {
        for font in fonts {
            for base in ["B", "f", "P", "x"] {
                for letter in ["A", "J", "V", "W", "Y"] {
                    let latex = "\(base)^2\(letter)"
                    let display = try typeset(latex, font: font, tucks: true)
                    let script = try XCTUnwrap(display.subDisplays.first { ($0 as? MTMathListDisplay)?.type == .superscript })
                    let step = em(font) / 64
                    let scriptInk = MTInkProfile(display: script, step: step)
                    let (line, _) = try XCTUnwrap(lines(in: display).last)
                    let letterInk = MTInkProfile(display: line, step: step)
                    let clearance = font.mathTable!.spaceAfterScript
                    for (row, extent) in letterInk.rows {
                        if let right = scriptInk.right(row) {
                            XCTAssertGreaterThanOrEqual(extent.lowerBound - right, clearance - 2 * step,
                                                        "\(latex) in \(name(font)), row \(row)")
                        }
                    }
                }
            }
        }
    }

    /// No nearer the base than the letter would be with no superscript at all.
    func testNeverNearerTheBaseThanWithoutTheScript() throws {
        for font in fonts {
            for (scripted, plain) in [("B^2A", "BA"), ("B^\\prime A", "BA"), ("P^2A", "PA"), ("V^2A", "VA")] {
                let tucked = try x(of: "A", in: typeset(scripted, font: font, tucks: true))
                let without = try x(of: "A", in: typeset(plain, font: font, tucks: true))
                XCTAssertGreaterThanOrEqual(tucked, without - 0.001, "\(scripted) in \(name(font))")
            }
        }
    }

    // MARK: Left as they are

    func testOtherCasesAreUnchanged() throws {
        let unchanged = [
            "B_2A",          // a subscript sits by the foot, which already reaches left
            "B_2^2A",        // with a subscript too
            "B^2=A",         // not a letter next
            "B^2(A)",        // a bracket next
            "B^2\\,A",       // spaced on purpose
            "B^2a",          // shorter than the superscript's middle: not beside it
            "B^2x",
            "BA",            // no script at all
            "B^2",
        ]
        for font in fonts {
            for latex in unchanged {
                let off = try typeset(latex, font: font, tucks: false)
                let on = try typeset(latex, font: font, tucks: true)
                XCTAssertEqual(off.width, on.width, accuracy: 0.0001, "\(latex) in \(name(font))")
                for ((a, p), (b, q)) in zip(lines(in: off), lines(in: on)) {
                    XCTAssertEqual(a.attributedString?.string, b.attributedString?.string, latex)
                    XCTAssertEqual(p.x, q.x, accuracy: 0.0001, "\(latex) in \(name(font))")
                }
            }
        }
    }

    // MARK: Anywhere in an expression

    func testInsideAFraction() throws {
        for font in fonts {
            XCTAssertGreaterThan(try tuck("\\frac{B^2A}{2}", letter: "A", font: font), 0.05 * em(font), name(font))
        }
    }

    func testAfterAWiderSuperscript() throws {
        for font in fonts {
            XCTAssertGreaterThan(try tuck("B^{10}A", letter: "A", font: font), 0.05 * em(font), name(font))
        }
    }

    func testInTextStyle() throws {
        for font in fonts {
            let off = try x(of: "A", in: typeset("AB^2=B^2A", font: font, tucks: false, style: .text))
            let on = try x(of: "A", in: typeset("AB^2=B^2A", font: font, tucks: true, style: .text))
            XCTAssertGreaterThan(off - on, 0.05 * em(font), name(font))
        }
    }

    /// The whole line is narrower by what the letter moved, and nothing else shifts.
    func testTheLineCloses() throws {
        for font in fonts {
            let off = try typeset("B^2A+1", font: font, tucks: false)
            let on = try typeset("B^2A+1", font: font, tucks: true)
            let shift = try tuck("B^2A+1", letter: "A", font: font)
            XCTAssertEqual(off.width - on.width, shift, accuracy: 0.0001, name(font))
        }
    }
}
