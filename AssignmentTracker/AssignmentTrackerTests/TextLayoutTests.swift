import CoreGraphics
import Foundation
import Testing
@testable import AssignmentTracker

struct TextLayoutTests {
    private func fragment(_ text: String, x: CGFloat, line: Int, height: CGFloat = 12) -> TextFragment {
        TextFragment(text: text, rect: CGRect(x: x, y: CGFloat(line) * 14, width: CGFloat(text.count) * 5, height: height))
    }

    @Test func wrappedCellsRejoinTheirRow() {
        let text = TextLayout.reconstruct([
            fragment("2", x: 54, line: 0), fragment("Tue 9/8", x: 88, line: 0),
            fragment("Research methods and ethics", x: 152, line: 0), fragment("Discussion Post 1; Worksheet 1:", x: 352, line: 0),
            fragment("in human subjects (Ch. 2)", x: 152, line: 1), fragment("Designing a study", x: 352, line: 1),
            fragment("3", x: 54, line: 2), fragment("Thu 9/17", x: 88, line: 2), fragment("Reading Check 1", x: 352, line: 2),
        ])
        #expect(text == """
            2 | Tue 9/8 | Research methods and ethics in human subjects (Ch. 2) | Discussion Post 1; Worksheet 1: Designing a study
            3 | Thu 9/17 | Reading Check 1
            """)
    }

    @Test func paragraphsAndBulletsAreNotMerged() {
        let text = TextLayout.reconstruct([
            fragment("The semester starts on Monday, August 31.", x: 54, line: 0),
            fragment("11:59 PM.", x: 54, line: 1),
            fragment("Friday, October 9", x: 54, line: 2),
            fragment("• Lab participation form", x: 60, line: 3),
        ])
        #expect(text.components(separatedBy: "\n").count == 4)
    }

    @Test func distantLinesAreNotContinuations() {
        // Same indentation, but a blank line apart: a new block, not a wrapped cell.
        let text = TextLayout.reconstruct([
            fragment("Oct 9", x: 54, line: 0), fragment("Problem Set 3", x: 200, line: 0),
            fragment("Notes about the course", x: 200, line: 3),
        ])
        #expect(text == "Oct 9 | Problem Set 3\nNotes about the course")
    }

    @Test func wideGapsSplitWordsIntoColumns() {
        let words = [
            TextFragment(text: "Oct", rect: CGRect(x: 54, y: 0, width: 15, height: 12)),
            TextFragment(text: "16", rect: CGRect(x: 72, y: 0, width: 10, height: 12)),
            TextFragment(text: "Midterm", rect: CGRect(x: 200, y: 0, width: 40, height: 12)),
            TextFragment(text: "Exam", rect: CGRect(x: 243, y: 0, width: 24, height: 12)),
        ]
        #expect(TextLayout.fragments(fromWords: words).map(\.text) == ["Oct 16", "Midterm Exam"])
    }
}
