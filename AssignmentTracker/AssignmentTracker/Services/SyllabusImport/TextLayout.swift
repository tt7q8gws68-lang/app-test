import CoreGraphics
import Foundation

/// A run of text and where it sits on the page, in top-down coordinates (y grows downward).
nonisolated struct TextFragment: Equatable, Sendable {
    var text: String
    var rect: CGRect
}

/// Rebuilds reading order from positioned text so tables survive extraction.
///
/// PDFKit's `page.string` and raw OCR both scramble tables: a cell that wraps onto a second
/// line gets split away from its row, neighbouring rows run together, and columns are only a
/// space apart. Here fragments are grouped into visual lines, columns are joined with " | ",
/// and lines whose first column is empty (wrapped cells) are folded back into the row above.
nonisolated enum TextLayout {
    static let columnSeparator = " | "

    static func reconstruct(_ fragments: [TextFragment]) -> String {
        let lines = visualLines(fragments.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty })
        var rows: [Row] = []
        for line in lines {
            if let last = rows.last, last.isContinued(by: line) {
                rows[rows.count - 1].absorb(line)
            } else {
                rows.append(Row(line))
            }
        }
        return rows.map(\.text).joined(separator: "\n")
    }

    /// Joins words on the same line into fragments. A gap wider than a column gutter (about
    /// three-quarters of the line height, well over a normal word space) starts a new fragment,
    /// which is how table columns stay apart.
    static func fragments(fromWords words: [TextFragment]) -> [TextFragment] {
        var fragments: [TextFragment] = []
        for line in visualLines(words) {
            var current: TextFragment?
            for word in line.fragments {
                guard var run = current else {
                    current = word
                    continue
                }
                let gap = word.rect.minX - run.rect.maxX
                if gap > max(word.rect.height, 1) * 0.75 {
                    fragments.append(run)
                    current = word
                } else {
                    run.text += " " + word.text
                    run.rect = run.rect.union(word.rect)
                    current = run
                }
            }
            if let current { fragments.append(current) }
        }
        return fragments
    }

    // MARK: - Lines

    struct Line {
        var fragments: [TextFragment]
        var midY: CGFloat
        var height: CGFloat

        var minX: CGFloat { fragments.first?.rect.minX ?? 0 }
        var minY: CGFloat { fragments.map(\.rect.minY).min() ?? midY }
        var maxY: CGFloat { fragments.map(\.rect.maxY).max() ?? midY }
    }

    /// Groups fragments whose vertical centres are close into lines, each sorted left to right.
    static func visualLines(_ fragments: [TextFragment]) -> [Line] {
        var lines: [Line] = []
        for fragment in fragments.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            let height = max(fragment.rect.height, 1)
            if let index = lines.indices.last,
               abs(lines[index].midY - fragment.rect.midY) <= max(lines[index].height, height) * 0.45 {
                lines[index].fragments.append(fragment)
                let count = CGFloat(lines[index].fragments.count)
                lines[index].midY += (fragment.rect.midY - lines[index].midY) / count
                lines[index].height = max(lines[index].height, height)
            } else {
                lines.append(Line(fragments: [fragment], midY: fragment.rect.midY, height: height))
            }
        }
        for index in lines.indices {
            lines[index].fragments.sort { $0.rect.minX < $1.rect.minX }
        }
        return lines
    }

    // MARK: - Rows

    private struct Cell {
        var x: CGFloat
        var text: String
    }

    private struct Row {
        var cells: [Cell]
        var height: CGFloat
        var bottom: CGFloat

        init(_ line: Line) {
            cells = line.fragments.map { Cell(x: $0.rect.minX, text: $0.text) }
            height = line.height
            bottom = line.maxY
        }

        var minX: CGFloat { cells.first?.x ?? 0 }

        /// A line continues this row when the row has several columns, the line's first column
        /// is empty (it starts to the right of the row's first cell), and it sits right below.
        func isContinued(by line: Line) -> Bool {
            guard cells.count >= 2 else { return false }
            let indent = line.minX - minX
            let gap = line.minY - bottom
            return indent > height * 1.5 && gap < height * 0.9
        }

        mutating func absorb(_ line: Line) {
            for fragment in line.fragments {
                // The cell whose left edge is closest to, and not right of, this fragment.
                let tolerance = height
                let index = cells.lastIndex { $0.x <= fragment.rect.minX + tolerance } ?? 0
                cells[index].text += " " + fragment.text
            }
            bottom = max(bottom, line.maxY)
        }

        var text: String {
            cells.map { $0.text.trimmingCharacters(in: .whitespaces) }.joined(separator: TextLayout.columnSeparator)
        }
    }
}
