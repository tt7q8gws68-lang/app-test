import CoreGraphics
import Foundation
import Observation
import SwiftData

/// Drives syllabus import: reading the file, detecting items, and the editable review list.
/// Nothing touches the data store until `save(in:)`.
@Observable
final class SyllabusImportModel {
    enum Phase: Equatable {
        case choosingSource
        case working(String)
        case reviewing
    }

    var course: Course? {
        didSet { if course !== oldValue { refreshDuplicates() } }
    }
    var phase: Phase = .choosingSource
    var error: SyllabusImportError?

    var candidates: [ImportCandidate] = []
    /// First day of classes; changing it re-places every "Week N" date.
    var termStart: Date? {
        didSet { if termStart != oldValue { ImportCandidateBuilder.reresolve(&candidates, with: resolver) } }
    }
    var remindDayBefore = false

    private(set) var engine: DetectionEngine = .rules(reason: nil)
    private(set) var sourceName = ""
    private(set) var pageCount = 0
    private(set) var recognizedPageCount = 0
    private(set) var alreadyImported = false
    private var fingerprint = ""
    private var hasSaved = false

    private let calendar: Calendar
    private let referenceDate: Date

    init(course: Course? = nil, calendar: Calendar = .current, referenceDate: Date = .now) {
        self.course = course
        self.calendar = calendar
        self.referenceDate = referenceDate
    }

    var resolver: SyllabusDateResolver {
        SyllabusDateResolver(calendar: calendar, termStart: termStart, referenceDate: referenceDate)
    }

    var includedCount: Int {
        candidates.filter { $0.isIncluded && $0.dueDate != nil }.count
    }

    var pastIncludedCount: Int {
        candidates.filter { $0.isIncluded && $0.isPast(relativeTo: referenceDate, calendar: calendar) }.count
    }

    var undatedCount: Int {
        candidates.filter { $0.dueDate == nil }.count
    }

    /// Checks or unchecks every past (non-duplicate) item at once.
    func setPastIncluded(_ included: Bool) {
        for index in candidates.indices
        where candidates[index].isPast(relativeTo: referenceDate, calendar: calendar) && candidates[index].duplicateOf == nil {
            candidates[index].isIncluded = included
        }
    }

    /// Whether any item's date depends on the semester start.
    var usesRelativeWeeks: Bool {
        candidates.contains { $0.dateText?.range(of: #"\bw(ee)?ks?\b"#, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    // MARK: - Importing

    func importFile(_ url: URL) async {
        await run(named: url.lastPathComponent) {
            try await SyllabusTextExtractor().extract(from: url)
        }
    }

    /// Shows progress while the photo picker hands over the files, before `importPhotos`.
    func prepareForPhotos(count: Int) {
        error = nil
        phase = .working(count == 1 ? "Loading photo…" : "Loading \(count) photos…")
    }

    func importPhotos(_ photos: [Data]) async {
        let name = photos.count == 1 ? "Photo" : "\(photos.count) photos"
        await run(named: name) {
            try await SyllabusTextExtractor().extract(photos: photos, name: name)
        }
    }

    func importScan(_ images: [CGImage]) async {
        let name = images.count == 1 ? "Scanned page" : "\(images.count) scanned pages"
        await run(named: name) {
            try await SyllabusTextExtractor().extract(images: images, name: name)
        }
    }

    private func run(named name: String, extract: () async throws -> ExtractedSyllabus) async {
        error = nil
        phase = .working("Reading \(name)…")
        do {
            let extracted = try await extract()
            let usesModel = FoundationModelSyllabusParser.availability.isAvailable
            phase = .working(usesModel ? "Finding assignments with Apple Intelligence…" : "Finding assignments…")
            let analysis = await SyllabusAnalyzer(calendar: calendar, referenceDate: referenceDate)
                .analyze(extracted.text) { [weak self] done, total in
                    guard total > 1, !Task.isCancelled else { return }
                    await MainActor.run {
                        self?.phase = .working("Finding assignments with Apple Intelligence…\nPart \(min(done + 1, total)) of \(total)")
                    }
                }
            // The analyzer falls back to the rules when cancelled, so check before showing results.
            try Task.checkCancellation()
            apply(analysis, from: extracted)
            phase = .reviewing
        } catch {
            // Cancelled when the sheet closed; there's nothing left to show an error on.
            guard !Task.isCancelled else { return }
            self.error = error as? SyllabusImportError ?? .unreadable(error.localizedDescription)
            phase = .choosingSource
        }
    }

    private func apply(_ analysis: SyllabusAnalysis, from extracted: ExtractedSyllabus) {
        sourceName = extracted.sourceName
        pageCount = extracted.pageCount
        recognizedPageCount = extracted.recognizedPageCount
        fingerprint = extracted.fingerprint
        engine = analysis.engine
        alreadyImported = course?.importedSyllabusFingerprints.contains(extracted.fingerprint) ?? false
        // Set without triggering re-resolution; candidates are built with it below.
        termStart = analysis.termStart
        candidates = ImportCandidateBuilder.candidates(from: analysis.items, resolver: resolver, existing: existingAssignments)
    }

    // MARK: - Review edits

    func addCandidate() -> ImportCandidate.ID {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: referenceDate))!
        var candidate = ImportCandidate(
            title: "", kind: .assignment,
            dueDate: calendar.date(bySettingHour: 23, minute: 59, second: 0, of: tomorrow),
            dateStatus: .confident
        )
        candidate.dateSetByUser = true
        candidates.append(candidate)
        return candidate.id
    }

    func delete(_ id: ImportCandidate.ID) {
        candidates.removeAll { $0.id == id }
    }

    func toggleIncluded(_ id: ImportCandidate.ID) {
        guard let index = candidates.firstIndex(where: { $0.id == id }), candidates[index].dueDate != nil else { return }
        candidates[index].isIncluded.toggle()
    }

    func startOver() {
        phase = .choosingSource
        hasSaved = false
        candidates = []
        error = nil
    }

    private var existingAssignments: [ExistingAssignment] {
        (course?.assignments ?? []).map { ExistingAssignment(title: $0.title, dueDate: $0.dueDate) }
    }

    private func refreshDuplicates() {
        guard !candidates.isEmpty else { return }
        alreadyImported = course?.importedSyllabusFingerprints.contains(fingerprint) ?? false
        let existing = existingAssignments
        for index in candidates.indices {
            let wasDuplicate = candidates[index].duplicateOf != nil
            candidates[index].duplicateOf = ImportCandidateBuilder.duplicate(of: candidates[index], in: existing, calendar: calendar)?.title
            if wasDuplicate != (candidates[index].duplicateOf != nil) {
                candidates[index].isIncluded = ImportCandidateBuilder.defaultInclusion(for: candidates[index], resolver: resolver)
            }
        }
    }

    // MARK: - Saving

    /// Adds the checked items to the course as regular assignments. Returns how many were added.
    /// Runs once per review, so a double-tapped Save can't add everything twice.
    @discardableResult
    func save(in context: ModelContext) -> Int {
        guard let course, !hasSaved else { return 0 }
        hasSaved = true
        var created: [Assignment] = []
        for candidate in candidates where candidate.isIncluded {
            guard let dueDate = candidate.dueDate else { continue }
            let title = candidate.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let assignment = Assignment(
                title: title.isEmpty ? candidate.kind.label : title,
                notes: candidate.notes,
                dueDate: dueDate,
                priority: candidate.suggestedPriority,
                remindDayBefore: remindDayBefore,
                kind: candidate.kind,
                weight: candidate.weight
            )
            context.insert(assignment)
            assignment.course = course
            if candidate.isPast(relativeTo: referenceDate, calendar: calendar) {
                assignment.setCompleted(true)
            }
            created.append(assignment)
        }
        if !fingerprint.isEmpty, !course.importedSyllabusFingerprints.contains(fingerprint) {
            course.importedSyllabusFingerprints.append(fingerprint)
        }
        if remindDayBefore, !created.isEmpty {
            Task {
                await ReminderScheduler.requestAuthorization()
                created.forEach { ReminderScheduler.sync($0) }
            }
        }
        return created.count
    }
}

private extension Result where Success == Void {
    var isAvailable: Bool {
        if case .success = self { true } else { false }
    }
}
