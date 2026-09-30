import Foundation
import FoundationModels

/// Detects syllabus items with Apple's on-device language model (guided generation).
///
/// The model only copies what the syllabus says, including each date exactly as written;
/// `SyllabusDateResolver` then turns that text into dates. Keeping date arithmetic out of the
/// model means it can't invent a date, and every resolution is deterministic and tested.
nonisolated struct FoundationModelSyllabusParser {
    enum Unavailable: Error, Equatable {
        case deviceNotEligible
        case appleIntelligenceNotEnabled
        case modelNotReady
        case other

        var explanation: String {
            switch self {
            case .deviceNotEligible: "This device doesn’t support Apple Intelligence"
            case .appleIntelligenceNotEnabled: "Apple Intelligence is turned off"
            case .modelNotReady: "The Apple Intelligence model is still downloading"
            case .other: "Apple Intelligence isn’t available right now"
            }
        }
    }

    /// Characters per request. The on-device context window is about 4,096 tokens and has to
    /// hold the instructions, the schema and the answer too.
    static let chunkSize = 2_200

    static var availability: Result<Void, Unavailable> {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .success(())
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .failure(.deviceNotEligible)
            case .appleIntelligenceNotEnabled: return .failure(.appleIntelligenceNotEnabled)
            case .modelNotReady: return .failure(.modelNotReady)
            @unknown default: return .failure(.other)
            }
        }
    }

    struct ChunkFailure: Error {}

    /// Reads the syllabus in chunks. A chunk that fails (a guardrail, or a response too long
    /// for the context window) is split and retried, and if it still fails it's skipped, so one
    /// bad passage can't discard what the other chunks found. Throws only if every chunk failed.
    /// `progress` gets (chunks done, total chunks).
    @concurrent
    func parse(
        _ text: String, progress: @Sendable (Int, Int) async -> Void = { _, _ in }
    ) async throws -> (items: [DetectedItem], termStartText: String?) {
        var items: [DetectedItem] = []
        var termStartText: String?
        let chunks = Self.chunks(of: text)
        var failures = 0

        for (index, chunk) in chunks.enumerated() {
            await progress(index, chunks.count)
            do {
                for generated in try await Self.generate(chunk) {
                    if termStartText == nil, !generated.firstDayOfClasses.isEmpty {
                        termStartText = generated.firstDayOfClasses
                    }
                    items += generated.items.compactMap { Self.detectedItem(from: $0, source: chunk) }
                }
            } catch {
                failures += 1
            }
        }
        await progress(chunks.count, chunks.count)
        if failures == chunks.count { throw ChunkFailure() }
        return (items, termStartText)
    }

    /// One request, split in half and retried when the passage is too long for the model.
    private static func generate(_ chunk: String, depth: Int = 0) async throws -> [GeneratedSyllabus] {
        // A fresh session per request keeps each one inside the context window.
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(
                to: "Syllabus text:\n\n\(chunk)",
                generating: GeneratedSyllabus.self,
                options: GenerationOptions(samplingMode: .greedy)
            )
            return [response.content]
        } catch LanguageModelSession.GenerationError.exceededContextWindowSize where depth < 2 {
            let halves = halve(chunk)
            guard halves.count == 2 else { throw ChunkFailure() }
            var results: [GeneratedSyllabus] = []
            for half in halves {
                results += (try? await generate(half, depth: depth + 1)) ?? []
            }
            if results.isEmpty { throw ChunkFailure() }
            return results
        }
    }

    private static func halve(_ chunk: String) -> [String] {
        let lines = chunk.components(separatedBy: .newlines)
        guard lines.count >= 2 else { return [chunk] }
        let middle = lines.count / 2
        return [lines[..<middle].joined(separator: "\n"), lines[middle...].joined(separator: "\n")]
    }

    private static let instructions = """
        You extract graded work from a college course syllabus. List EVERY assignment, homework, \
        problem set, worksheet, discussion post, journal, essay, paper, lab, quiz, exam, project, \
        presentation, milestone and required reading that has a due date or scheduled date. \
        Schedule tables use " | " between columns: one row can hold several items, so list each \
        one separately with that row's date. Do not stop early or summarize; include every item. \
        Skip lecture topics, holidays, office hours and policies. \
        Copy titles and dates exactly as written. Never calculate or guess dates.
        """

    /// Splits at line breaks. Each chunk after the first repeats the latest "Week N" header
    /// so weekday-only lines keep their week.
    static func chunks(of text: String) -> [String] {
        var chunks: [String] = []
        var current = ""
        var lastWeekHeader: String?
        for line in text.components(separatedBy: .newlines) {
            if current.count + line.count > chunkSize, !current.isEmpty {
                chunks.append(current)
                current = lastWeekHeader.map { "\($0)\n" } ?? ""
            }
            if line.range(of: #"^\s*(week|wk\.?)\s*\d"#, options: [.regularExpression, .caseInsensitive]) != nil {
                lastWeekHeader = line
            }
            current += line + "\n"
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { chunks.append(current) }
        return chunks
    }

    /// Drops items the source text doesn't back up, so a hallucinated title can't slip through.
    static func detectedItem(from item: GeneratedItem, source: String) -> DetectedItem? {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count >= 2 else { return nil }
        let words = RuleBasedSyllabusParser.normalized(title).split(separator: " ").filter { $0.count > 2 }
        let normalizedSource = RuleBasedSyllabusParser.normalized(source)
        let found = words.filter { normalizedSource.contains($0) }
        guard !words.isEmpty, Double(found.count) / Double(words.count) >= 0.5 else { return nil }

        let dateText = item.dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawWeight = item.weight.trimmingCharacters(in: .whitespacesAndNewlines)
        var weight = rawWeight.isEmpty ? nil : RuleBasedSyllabusParser.weight(in: rawWeight) ?? rawWeight
        if let stated = weight, !lineStates(weight: stated, for: title, in: source) {
            weight = nil
        }
        return DetectedItem(
            title: title,
            kind: item.kind.assignmentKind,
            dateText: dateText.isEmpty ? nil : dateText,
            weight: weight,
            notes: item.details.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// True when a single line names the item and gives the weight. The model tends to copy a
    /// category's total ("Problem Sets (5) … 25%") onto every member.
    static func lineStates(weight: String, for title: String, in source: String) -> Bool {
        let number = weight.filter { $0.isNumber || $0 == "." }
        let normalizedTitle = RuleBasedSyllabusParser.normalized(title)
        guard !number.isEmpty, !normalizedTitle.isEmpty else { return false }
        return source.components(separatedBy: .newlines).contains { line in
            line.contains(number) && RuleBasedSyllabusParser.normalized(line).contains(normalizedTitle)
        }
    }
}

@Generable(description: "Graded work found in part of a course syllabus")
nonisolated struct GeneratedSyllabus {
    @Guide(description: "The first day of classes exactly as written, for example 'August 31, 2026'. Empty if this text doesn't say.")
    var firstDayOfClasses: String

    @Guide(description: "Every assignment, quiz, exam, project and reading in this text, in order")
    var items: [GeneratedItem]
}

@Generable
nonisolated struct GeneratedItem {
    @Guide(description: "Short title as written, for example 'Problem Set 3' or 'Midterm Exam'")
    var title: String

    var kind: GeneratedKind

    @Guide(description: "The due or scheduled date copied exactly as written, including any week number, weekday, range and time, for example 'Week 3, Friday', 'Oct 12–14' or 'Dec 4 at 5 PM'. Empty if no date is given.")
    var dateText: String

    @Guide(description: "Grade weight or points as written, for example '15%' or '50 points'. Empty if not given.")
    var weight: String

    @Guide(description: "A few words of useful detail such as location or format. Usually empty.")
    var details: String
}

@Generable
nonisolated enum GeneratedKind {
    case assignment, exam, quiz, project, reading

    var assignmentKind: AssignmentKind {
        switch self {
        case .assignment: .assignment
        case .exam: .exam
        case .quiz: .quiz
        case .project: .project
        case .reading: .reading
        }
    }
}
