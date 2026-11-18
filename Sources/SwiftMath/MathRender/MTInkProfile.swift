import CoreGraphics
import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Where something's ink is, row by row: for each thin horizontal band of the
/// line, the leftmost and rightmost inked point in it. Found by drawing it
/// into a small bitmap, so it follows the real outlines — a slanted stroke, a
/// serif, the curve of a 2 — rather than a bounding box.
///
/// Rows are `step` high and counted up from the baseline, `row = floor(y / step)`,
/// so two profiles made with the same step line up row for row.
struct MTInkProfile {

    let step: CGFloat
    /// The inked extent of each row that has ink in it, by row number.
    private(set) var rows: [Int: ClosedRange<CGFloat>] = [:]

    var isEmpty: Bool { rows.isEmpty }
    var lowestRow: Int? { rows.keys.min() }
    var highestRow: Int? { rows.keys.max() }

    /// The leftmost ink in `row`, if it has any.
    func left(_ row: Int) -> CGFloat? { rows[row]?.lowerBound }
    /// The rightmost ink in `row`, if it has any.
    func right(_ row: Int) -> CGFloat? { rows[row]?.upperBound }
    /// The leftmost ink anywhere.
    var leftmost: CGFloat? { rows.values.map(\.lowerBound).min() }

    /// The ink of `display` in its parent's coordinates, where its `position` is.
    init(display: MTDisplay, step: CGFloat) {
        let bounds = display.displayBounds()
        // A slanted glyph can reach a little past the box it's measured by.
        let pad = max(bounds.height, 1) * 0.25
        self.init(step: step, covering: bounds.insetBy(dx: -pad, dy: -pad)) { context in
            #if canImport(UIKit)
            // Rules — fraction bars, root lines — are drawn by UIKit, into its current context.
            UIGraphicsPushContext(context)
            display.draw(context)
            UIGraphicsPopContext()
            #else
            display.draw(context)
            #endif
        }
    }

    /// The ink of `glyph` in `font`, with its origin — the pen position on the
    /// baseline — at `origin`.
    init?(glyph: CGGlyph, font: CTFont, origin: CGPoint, step: CGFloat) {
        guard let path = CTFontCreatePathForGlyph(font, glyph, nil) else { return nil }
        let box = path.boundingBoxOfPath
        guard !box.isNull, box.width > 0, box.height > 0 else { return nil }
        let placed = box.offsetBy(dx: origin.x, dy: origin.y)
        self.init(step: step, covering: placed.insetBy(dx: -step, dy: -step)) { context in
            context.translateBy(x: origin.x, y: origin.y)
            context.addPath(path)
            context.fillPath()
        }
    }

    /// Draws with `draw`, in the parent's coordinates, into a bitmap covering
    /// `area`, and reads the inked extent of each row.
    private init(step: CGFloat, covering area: CGRect, draw: (CGContext) -> Void) {
        self.step = step
        guard step > 0, area.width > 0, area.height > 0 else { return }
        // Whole rows and columns, lined up with the shared row numbering.
        let firstRow = Int((area.minY / step).rounded(.down))
        let lastRow = Int((area.maxY / step).rounded(.up))
        let firstColumn = Int((area.minX / step).rounded(.down))
        let lastColumn = Int((area.maxX / step).rounded(.up))
        let width = lastColumn - firstColumn, height = lastRow - firstRow
        guard width > 0, height > 0, width * height < 4_000_000,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return }
        // Ink on white: text with no colour of its own draws black.
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        // One pixel a step; y up from the baseline, as the typesetter has it.
        context.scaleBy(x: 1 / step, y: 1 / step)
        context.translateBy(x: -CGFloat(firstColumn) * step, y: -CGFloat(firstRow) * step)
        context.setFillColor(gray: 0, alpha: 1)
        context.setStrokeColor(gray: 0, alpha: 1)
        context.textMatrix = .identity
        draw(context)

        guard let data = context.data else { return }
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height)
        let bytesPerRow = context.bytesPerRow
        for y in 0..<height {
            // The bitmap's memory starts at its top row.
            let line = pixels + (height - 1 - y) * bytesPerRow
            var first: Int?, last: Int?
            // Anything short of white: a light colour, or the edge of a stroke.
            for x in 0..<width where line[x] < 230 {
                if first == nil { first = x }
                last = x
            }
            if let first, let last {
                rows[firstRow + y] = (CGFloat(firstColumn + first) * step)...(CGFloat(firstColumn + last + 1) * step)
            }
        }
    }

    /// The same ink, grown up and down by `rows` rows: each row reaching as
    /// far as any within that distance. Keeps a clearance round corners, not
    /// only straight across.
    func grown(by count: Int) -> MTInkProfile {
        guard count > 0 else { return self }
        var grown = MTInkProfile(step: step)
        for (row, extent) in rows {
            for r in (row - count)...(row + count) {
                if let existing = grown.rows[r] {
                    grown.rows[r] = min(existing.lowerBound, extent.lowerBound)...max(existing.upperBound, extent.upperBound)
                } else {
                    grown.rows[r] = extent
                }
            }
        }
        return grown
    }

    private init(step: CGFloat) { self.step = step }
}
