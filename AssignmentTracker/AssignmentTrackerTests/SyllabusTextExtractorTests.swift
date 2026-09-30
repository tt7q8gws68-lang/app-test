import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AssignmentTracker

private final class BundleToken {}

func fixture(_ name: String) throws -> Data {
    let bundle = Bundle(for: BundleToken.self)
    let url = try #require(
        bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"),
        "Missing fixture \(name)"
    )
    return try Data(contentsOf: url)
}

struct SyllabusTextExtractorTests {
    let extractor = SyllabusTextExtractor()

    @Test func readsTextPDF() async throws {
        let result = try await extractor.extract(data: fixture("ECON220_Econometrics_Syllabus.pdf"), type: .pdf, name: "econ.pdf")
        #expect(result.recognizedPageCount == 0)
        #expect(result.text.contains("Classes begin Monday, August 31, 2026"))
        #expect(result.text.contains("Midterm Exam — Thursday, October 15, 10:00 AM"))
        #expect(result.fingerprint.count == 64)
    }

    @Test func readsScannedPDFWithOCR() async throws {
        let result = try await extractor.extract(data: fixture("MACRO210_Macroeconomics_Scan.pdf"), type: .pdf, name: "scan.pdf")
        #expect(result.recognizedPageCount == 1)
        #expect(result.text.contains("Intermediate Macroeconomics"))
        // Table rows come back as single lines with their columns.
        let midterm = try #require(result.text.components(separatedBy: .newlines).first { $0.contains("Midterm") })
        #expect(midterm.contains("Oct 16"))
    }

    @Test func readsDocxTableRowsAsColumns() async throws {
        let result = try await extractor.extract(data: fixture("MoneyBanking_Syllabus.docx"), type: SyllabusTextExtractor.docxType, name: "mb.docx")
        #expect(result.text.contains("Mon, Oct 5\tBank balance sheet memo\t10%"))
        #expect(result.text.contains("The first day of class is September 1, 2026."))
    }

    @Test func readsPlainText() async throws {
        let text = "HIST 480 Seminar\nBook review essay — 25%\nFinal research paper — 40%\n"
        let result = try await extractor.extract(data: Data(text.utf8), type: .plainText, name: "seminar.txt")
        #expect(result.text == text)
    }

    @Test func rejectsBrokenPDF() async throws {
        await #expect(throws: SyllabusImportError.unreadable("It may be damaged or not really a PDF.")) {
            try await extractor.extract(data: fixture("Broken_Syllabus.pdf"), type: .pdf, name: "broken.pdf")
        }
    }

    @Test func rejectsUnsupportedType() async {
        await #expect(throws: SyllabusImportError.unsupportedType("syllabus.pages")) {
            try await extractor.extract(data: Data("x".utf8), type: .zip, name: "syllabus.pages")
        }
    }

    @Test func rejectsEmptyFile() async {
        await #expect(throws: SyllabusImportError.emptyFile) {
            try await extractor.extract(data: Data(), type: .pdf, name: "empty.pdf")
        }
    }

    @Test func rejectsOversizedFile() async {
        let big = Data(count: Int(SyllabusTextExtractor.maxFileSize) + 1)
        await #expect(throws: SyllabusImportError.fileTooLarge(bytes: Int64(big.count))) {
            try await extractor.extract(data: big, type: .pdf, name: "big.pdf")
        }
    }

    @Test func rejectsTextTooShortToBeASyllabus() async {
        await #expect(throws: SyllabusImportError.noTextFound) {
            try await extractor.extract(data: Data("Hi".utf8), type: .plainText, name: "short.txt")
        }
    }

    @Test func rejectsFakeDocx() async {
        await #expect(throws: SyllabusImportError.unreadable("It doesn’t look like a valid Word document.")) {
            try await extractor.extract(data: Data(repeating: 7, count: 500), type: SyllabusTextExtractor.docxType, name: "fake.docx")
        }
    }

    @Test func zipReaderListsEntries() throws {
        let archive = try ZipArchive(data: fixture("MoneyBanking_Syllabus.docx"))
        #expect(Set(archive.entryNames) == ["[Content_Types].xml", "_rels/.rels", "word/document.xml"])
        #expect(throws: ZipArchive.ZipError.entryNotFound("missing.xml")) { try archive.contents(of: "missing.xml") }
    }
}

/// Extraction and parsing together, on the sample syllabi.
struct SyllabusEndToEndTests {
    @Test func scannedTableYieldsDatedItems() async throws {
        let text = try await SyllabusTextExtractor()
            .extract(data: fixture("MACRO210_Macroeconomics_Scan.pdf"), type: .pdf, name: "scan.pdf").text
        let items = RuleBasedSyllabusParser(calendar: Fixtures.calendar, referenceDate: Fixtures.today).parse(text).items

        let titles = items.map(\.title)
        #expect(titles.contains("Midterm Exam"))
        #expect(titles.contains("Quiz 3"))
        #expect(titles.contains("Research Paper"))
        #expect(!titles.contains { $0.localizedCaseInsensitiveContains("fall break") })

        let midterm = try #require(items.first { $0.title == "Midterm Exam" })
        #expect(midterm.kind == .exam)
        #expect(midterm.weight == "25%")
        let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, referenceDate: Fixtures.today)
        #expect(resolver.resolve(try #require(midterm.dateText)).date == Fixtures.date(2026, 10, 16, 13, 0))
    }

    @Test func textPDFWeeklyScheduleResolves() async throws {
        let text = try await SyllabusTextExtractor()
            .extract(data: fixture("ECON220_Econometrics_Syllabus.pdf"), type: .pdf, name: "econ.pdf").text
        let result = RuleBasedSyllabusParser(calendar: Fixtures.calendar, referenceDate: Fixtures.today).parse(text)
        #expect(result.termStart == Fixtures.date(2026, 8, 31))

        let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: result.termStart, referenceDate: Fixtures.today)
        func due(_ title: String) throws -> ResolvedDate {
            let item = try #require(result.items.first { $0.title == title }, "no item “\(title)” in \(result.items.map(\.title))")
            return resolver.resolve(try #require(item.dateText))
        }
        #expect(try due("Problem Set 1").date == Fixtures.date(2026, 9, 18, 23, 59))
        #expect(try due("Quiz 1").date == Fixtures.date(2026, 9, 24, 23, 59))
        #expect(try due("Midterm Exam").date == Fixtures.date(2026, 10, 15, 10, 0))
        #expect(try due("Final Exam").date == Fixtures.date(2026, 12, 11, 9, 0))
        if case .needsReview = try due("Empirical project proposal").status {} else { Issue.record("range should need review") }
        if case .missing = try due("Guest lecture reflection").status {} else { Issue.record("TBA should be missing") }

        #expect(result.items.first { $0.title == "Midterm Exam" }?.weight == "20%")
    }

    /// A 21-item syllabus whose schedule table has wrapped cells and several items per cell,
    /// plus date headings with bullets. PDFKit's plain text scrambled it into 7 wrong items.
    @Test func wrappedTableAndDateHeadingsFindEveryItem() async throws {
        let text = try await SyllabusTextExtractor()
            .extract(data: fixture("PSYC101_Psychology_Syllabus.pdf"), type: .pdf, name: "psyc.pdf").text
        let result = RuleBasedSyllabusParser(calendar: Fixtures.calendar, referenceDate: Fixtures.today).parse(text)

        #expect(result.termStart == Fixtures.date(2026, 8, 31))
        #expect(result.items.map(\.title) == [
            "Syllabus acknowledgment", "Discussion Post 1", "Worksheet 1: Designing a study", "Reading Check 1",
            "Discussion Post 2", "Worksheet 2: Sleep diary analysis", "Discussion Post 3",
            "Exam 1 (Chapters 1–6), in class", "Journal Entry 1: Memory experiment reflection", "Reading Check 2",
            "Research Paper Milestone 1: Topic", "Discussion Post 4", "Worksheet 3: Emotion regulation strategies",
            "Exam 2 (Chapters 7–11)", "Journal Entry 2", "Research Paper Milestone 2: Annotated bibliography",
            "Lab participation form (SONA credits, part 1)", "Poster draft for peer review",
            "Extra credit article summary", "Final research paper", "Cumulative final exam",
        ])
        #expect(result.items.filter { $0.kind == .exam }.count == 3)
        #expect(result.items.filter { $0.kind == .quiz }.count == 2)
        #expect(!result.items.contains { $0.kind == .reading }, "chapter citations in topics aren't readings")

        let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: result.termStart, referenceDate: Fixtures.today)
        func due(_ title: String) throws -> Date? {
            resolver.resolve(try #require(result.items.first { $0.title == title }?.dateText)).date
        }
        #expect(try due("Worksheet 1: Designing a study") == Fixtures.date(2026, 9, 8, 23, 59))
        #expect(try due("Research Paper Milestone 2: Annotated bibliography") == Fixtures.date(2026, 12, 3, 23, 59))
        #expect(try due("Lab participation form (SONA credits, part 1)") == Fixtures.date(2026, 10, 9, 23, 59))
        #expect(try due("Extra credit article summary") == Fixtures.date(2026, 11, 30, 23, 59))
        #expect(try due("Cumulative final exam") == Fixtures.date(2026, 12, 15, 10, 30))
    }

    @Test func docxWithMismatchedWeekdayIsFlagged() async throws {
        let text = try await SyllabusTextExtractor()
            .extract(data: fixture("MoneyBanking_Syllabus.docx"), type: SyllabusTextExtractor.docxType, name: "mb.docx").text
        let result = RuleBasedSyllabusParser(calendar: Fixtures.calendar, referenceDate: Fixtures.today).parse(text)
        #expect(result.termStart == Fixtures.date(2026, 9, 1))
        #expect(result.items.map(\.title) == [
            "Bank balance sheet memo", "Case analysis: 2008 crisis", "Midterm exam",
            "Group presentation", "Term paper", "Final exam",
        ])
        let resolver = SyllabusDateResolver(calendar: Fixtures.calendar, termStart: result.termStart, referenceDate: Fixtures.today)
        #expect(resolver.resolve(result.items[1].dateText!).status == .needsReview("Syllabus says Thursday but that date is a Wednesday"))
        #expect(resolver.resolve(result.items[4].dateText!).date == Fixtures.date(2026, 12, 7, 23, 59))
    }
}
