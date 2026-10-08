import Foundation
import SwiftData
import Testing
@testable import AssignmentTracker

struct ImportRobustnessTests {
    @Test func zipReadsAStoredEntry() throws {
        let archive = try ZipArchive(data: Self.zip(name: "a.txt", method: 0, payload: Data("hello".utf8), declaredSize: 5))
        #expect(try archive.contents(of: "a.txt") == Data("hello".utf8))
    }

    @Test func zipRejectsAnEntryClaimingAHugeSize() throws {
        // A few bytes that claim to inflate to 4 GB must not allocate that much.
        let archive = try ZipArchive(data: Self.zip(name: "word/document.xml", method: 8, payload: Data([0x03, 0x00]), declaredSize: .max))
        #expect(throws: ZipArchive.ZipError.corrupt) { try archive.contents(of: "word/document.xml") }
    }

    @Test func unreadablePhotosFailWithoutCrashing() async {
        await #expect(throws: SyllabusImportError.unreadable("The photos couldn’t be opened.")) {
            try await SyllabusTextExtractor().extract(photos: [Data("not an image".utf8)], name: "Photo")
        }
    }

    @MainActor
    @Test func parserStopsWhenCancelled() async {
        let task = Task { try await FoundationModelSyllabusParser().parse("Problem Set 1 due Sep 8") }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @MainActor
    @Test func saveRunsOnce() throws {
        let container = try ModelContainer(for: ModelContainer.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let course = Course(name: "Psychology", color: .purple, sortIndex: 0)
        context.insert(course)

        let model = SyllabusImportModel(course: course, calendar: Fixtures.calendar, referenceDate: Fixtures.today)
        model.candidates = ImportCandidateBuilder.candidates(
            from: [DetectedItem(title: "Exam 1", kind: .exam, dateText: "Oct 15")],
            resolver: model.resolver, existing: []
        )
        #expect(model.save(in: context) == 1)
        #expect(model.save(in: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Assignment>()) == 1)
    }

    /// A one-entry ZIP: local header, data, central directory and end record.
    private static func zip(name: String, method: UInt16, payload: Data, declaredSize: UInt32) -> Data {
        func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
        let nameData = Data(name.utf8)

        var local = le32(0x0403_4B50) + le16(20) + le16(0) + le16(method) + le32(0) + le32(0)
        local += le32(UInt32(payload.count)) + le32(declaredSize)
        local += le16(UInt16(nameData.count)) + le16(0) + nameData + payload

        var central = le32(0x0201_4B50) + le16(20) + le16(20) + le16(0) + le16(method) + le32(0) + le32(0)
        central += le32(UInt32(payload.count)) + le32(declaredSize)
        central += le16(UInt16(nameData.count)) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0) + le32(0) + nameData

        let end = le32(0x0605_4B50) + le16(0) + le16(0) + le16(1) + le16(1)
            + le32(UInt32(central.count)) + le32(UInt32(local.count)) + le16(0)
        return local + central + end
    }
}
