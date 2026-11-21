import CoreText
import SwiftUI

// MARK: - Glyph outlines for the tubes
//
// Each sign's text is turned into vector letter outlines with CoreText once, then cached.
// Coordinates are in points with the sign's centre at (0, 0), y growing downward.

struct NeonLetter {
    let path: Path
    let center: CGPoint
    let word: Int          // index into NeonSignGeometry.words
    let indexInWord: Int
}

struct NeonWordGeo {
    let line: Int          // which lyric line of the sign
    let letters: Range<Int>
    let bounds: CGRect
    let path: Path         // every letter
    let even: Path         // letters 0, 2, 4… (for two-colour "everyone" lines)
    let odd: Path
}

final class NeonSignGeometry {
    let letters: [NeonLetter]
    let words: [NeonWordGeo]
    let rows: [CGRect]       // one per wrapped row (for brackets)
    let lineWords: [Range<Int>]
    let bounds: CGRect
    let outline: Path        // the whole sign
    let fontSize: CGFloat

    init(letters: [NeonLetter], words: [NeonWordGeo], rows: [CGRect], lineWords: [Range<Int>],
         bounds: CGRect, outline: Path, fontSize: CGFloat) {
        self.letters = letters; self.words = words; self.rows = rows; self.lineWords = lineWords
        self.bounds = bounds; self.outline = outline; self.fontSize = fontSize
    }

    /// Tube width for this sign at a given thickness setting (0…1).
    func tube(_ thickness: Double) -> CGFloat { fontSize * CGFloat(0.028 + 0.05 * thickness) }
}

/// A font for glyph outlines: PostScript name, word spacing and row height (both × font size).
struct GlyphFace: Equatable {
    var name: String
    var space: CGFloat = 0.3
    var lineHeight: CGFloat = 1.15
}

enum NeonGlyphs {
    private static var cache: [String: NeonSignGeometry] = [:]
    private static let lock = NSLock()

    /// The sign for these lines, fitted inside `box`. Cached by text, font and size.
    static func sign(_ texts: [String], font: NeonFont, fontSize: CGFloat, box: CGSize) -> NeonSignGeometry {
        sign(texts, face: font.face, fontSize: fontSize, box: box)
    }

    /// Same, for any font face (used by other styles that letter their own signs).
    static func sign(_ texts: [String], face font: GlyphFace, fontSize: CGFloat, box: CGSize) -> NeonSignGeometry {
        let key = "\(font.name)|\(Int(fontSize))|\(Int(box.width))x\(Int(box.height))|" + texts.joined(separator: "\n")
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()

        var size = fontSize
        var geo = layout(texts, face: font, fontSize: size, maxWidth: box.width)
        for _ in 0..<3 {
            let k = min(box.width / max(1, geo.bounds.width), box.height / max(1, geo.bounds.height))
            guard k < 1 else { break }
            size = max(8, size * k * 0.98)
            geo = layout(texts, face: font, fontSize: size, maxWidth: box.width)
        }

        lock.lock()
        if cache.count > 80 { cache = [:] }
        cache[key] = geo
        lock.unlock()
        return geo
    }

    private struct WordShape {
        var width: CGFloat
        var glyphs: [(path: CGPath, center: CGPoint)]   // x from the word's left edge, y from baseline
    }

    private static func shape(_ word: String, font: CTFont) -> WordShape {
        let attr = NSAttributedString(string: word, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        var glyphs: [(CGPath, CGPoint)] = []
        for run in (CTLineGetGlyphRuns(line) as? [CTRun]) ?? [] {
            let n = CTRunGetGlyphCount(run)
            guard n > 0 else { continue }
            let attrs = CTRunGetAttributes(run) as NSDictionary
            // Characters the face lacks fall back to another font; use that one's outlines.
            let runFont = attrs[kCTFontAttributeName as String].map { $0 as! CTFont } ?? font
            var ids = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &ids)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                var t = CGAffineTransform(translationX: pos[i].x, y: -pos[i].y).scaledBy(x: 1, y: -1)
                guard let p = CTFontCreatePathForGlyph(runFont, ids[i], &t), !p.isEmpty else { continue }
                let b = p.boundingBoxOfPath
                glyphs.append((p, CGPoint(x: b.midX, y: b.midY)))
            }
        }
        return WordShape(width: width, glyphs: glyphs)
    }

    static func layout(_ texts: [String], font: NeonFont, fontSize: CGFloat, maxWidth: CGFloat) -> NeonSignGeometry {
        layout(texts, face: font.face, fontSize: fontSize, maxWidth: maxWidth)
    }

    static func layout(_ texts: [String], face font: GlyphFace, fontSize: CGFloat, maxWidth: CGFloat) -> NeonSignGeometry {
        let ct = CTFontCreateWithName(font.name as CFString, fontSize, nil)
        let space = fontSize * font.space
        let rowH = fontSize * font.lineHeight
        let lineGap = fontSize * 0.12
        let ascent = CTFontGetAscent(ct), descent = CTFontGetDescent(ct)
        // Baseline sits so the row's visual middle is the row centre (x-height-ish).
        let baselineShift = (ascent - descent) * 0.32

        struct Placed { var line: Int; var row: Int; var x: CGFloat; var shape: WordShape }
        var placed: [Placed] = []
        var rowWidths: [CGFloat] = []
        var rowY: [CGFloat] = []
        var y: CGFloat = 0
        for (li, text) in texts.enumerated() {
            let words = text.split(separator: " ").map(String.init)
            var x: CGFloat = 0
            var first = true
            if li > 0 { y += lineGap }
            rowWidths.append(0); rowY.append(y)
            for w in words {
                let s = shape(w, font: ct)
                if !first, x + space + s.width > maxWidth {
                    y += rowH
                    rowWidths.append(0); rowY.append(y)
                    x = 0; first = true
                }
                if !first { x += space }
                placed.append(Placed(line: li, row: rowWidths.count - 1, x: x, shape: s))
                x += s.width
                rowWidths[rowWidths.count - 1] = x
                first = false
            }
            y += rowH
        }
        let totalH = y
        var letters: [NeonLetter] = []
        var words: [NeonWordGeo] = []
        var lineWords: [Range<Int>] = Array(repeating: 0..<0, count: texts.count)
        var outline = Path()
        let rows = rowWidths.indices.map { r in
            CGRect(x: -rowWidths[r] / 2, y: rowY[r] - totalH / 2, width: rowWidths[r], height: rowH)
        }

        for p in placed {
            let row = rows[p.row]
            let ox = row.minX + p.x
            let baseline = row.midY + baselineShift
            var wp = Path(), even = Path(), odd = Path()
            let first = letters.count
            var bounds = CGRect.null
            for (gi, g) in p.shape.glyphs.enumerated() {
                let t = CGAffineTransform(translationX: ox, y: baseline)
                let path = Path(g.path).applying(t)
                letters.append(NeonLetter(path: path, center: g.center.applying(t), word: words.count, indexInWord: gi))
                wp.addPath(path)
                if gi % 2 == 0 { even.addPath(path) } else { odd.addPath(path) }
                bounds = bounds.union(path.boundingRect)
            }
            if bounds.isNull { bounds = CGRect(x: ox, y: row.minY, width: p.shape.width, height: rowH) }
            let r = lineWords[p.line]
            lineWords[p.line] = (r.isEmpty ? words.count : r.lowerBound)..<(words.count + 1)
            words.append(NeonWordGeo(line: p.line, letters: first..<letters.count, bounds: bounds,
                                     path: wp, even: even, odd: odd))
            outline.addPath(wp)
        }

        let ink = outline.boundingRect
        let bounds = ink.isNull ? CGRect(x: -10, y: -10, width: 20, height: 20) : ink.union(rows.reduce(CGRect.null) { $0.union($1) })
        return NeonSignGeometry(letters: letters, words: words, rows: rows, lineWords: lineWords,
                                bounds: bounds, outline: outline, fontSize: fontSize)
    }
}
