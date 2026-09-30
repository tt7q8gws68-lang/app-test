import Foundation

/// Which detector produced the items, shown on the review screen.
nonisolated enum DetectionEngine: Equatable, Sendable {
    case onDeviceModel
    /// Pattern-based detection, with the reason the model wasn't used (nil if it wasn't tried).
    case rules(reason: String?)
}

nonisolated struct SyllabusAnalysis: Sendable {
    var items: [DetectedItem]
    var termStart: Date?
    var engine: DetectionEngine
}

/// Chooses a detector: the on-device model when Apple Intelligence is available, otherwise
/// (or if the model fails) the rule-based parser.
nonisolated struct SyllabusAnalyzer {
    var calendar: Calendar = .current
    var referenceDate: Date = .now

    /// `progress` gets (chunks read, total chunks) while the on-device model works.
    @concurrent
    func analyze(_ text: String, progress: @Sendable (Int, Int) async -> Void = { _, _ in }) async -> SyllabusAnalysis {
        let rules = RuleBasedSyllabusParser(calendar: calendar, referenceDate: referenceDate).parse(text)
        let resolver = SyllabusDateResolver(calendar: calendar, referenceDate: referenceDate)

        if Self.forcesRules {
            return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: nil))
        }

        switch FoundationModelSyllabusParser.availability {
        case .failure(let unavailable):
            return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: unavailable.explanation))
        case .success:
            do {
                let model = try await FoundationModelSyllabusParser().parse(text, progress: progress)
                guard !model.items.isEmpty || rules.items.isEmpty else {
                    return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: "Apple Intelligence found nothing"))
                }
                let modelTermStart = model.termStartText
                    .flatMap { Self.isStatedAsTermStart($0, in: text) ? resolver.resolve($0).date : nil }
                    .map { calendar.startOfDay(for: $0) }
                let termStart = rules.termStart ?? modelTermStart
                var dayResolver = resolver
                dayResolver.termStart = termStart
                return SyllabusAnalysis(
                    items: Self.merge(model: model.items, rules: rules.items) { a, b in
                        guard let a, let b else { return true }
                        guard let x = dayResolver.resolve(a).date, let y = dayResolver.resolve(b).date else { return a == b }
                        return calendar.isDate(x, inSameDayAs: y)
                    },
                    termStart: termStart,
                    engine: .onDeviceModel
                )
            } catch {
                return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: "Apple Intelligence couldn’t read this syllabus"))
            }
        }
    }

    /// Accepts the model's semester start only when a line of the syllabus gives that date
    /// as the start ("Classes begin …"). Otherwise the model tends to offer the first date it
    /// sees, which would silently shift every "Week N" date.
    static func isStatedAsTermStart(_ dateText: String, in text: String) -> Bool {
        let needle = dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return false }
        return text.components(separatedBy: .newlines).contains { line in
            line.localizedCaseInsensitiveContains(needle)
                && SyllabusDateResolver.termStartCue.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
    }

    /// Cross-checks the model against the rule-based pass. The model is better at finding items
    /// in free-form prose; the rules copy dates literally from the item's own line or week header.
    /// So when both find an item, the rules' date text wins (the model sometimes files an item
    /// under the wrong week), and items only the rules found are added.
    static func merge(
        model: [DetectedItem], rules: [DetectedItem],
        sameDay: (String?, String?) -> Bool = { $0 == nil || $1 == nil || $0 == $1 }
    ) -> [DetectedItem] {
        var merged: [DetectedItem] = []
        var matchedRules = Set<Int>()
        for var item in model {
            let title = RuleBasedSyllabusParser.normalized(item.title)
            if let index = rules.indices.first(where: {
                !matchedRules.contains($0) && RuleBasedSyllabusParser.normalized(rules[$0].title) == title
            }) {
                matchedRules.insert(index)
                let rule = rules[index]
                if let date = rule.dateText { item.dateText = date }
                // A keyword match ("Reading Check" → quiz) is more specific than the model's
                // tendency to call everything an assignment.
                if rule.kind != .assignment { item.kind = rule.kind }
                if item.weight == nil { item.weight = rule.weight }
                // The syllabus line itself says more than the model's paraphrase.
                if !rule.notes.isEmpty { item.notes = rule.notes }
            }
            merged.append(item)
        }
        for (index, rule) in rules.enumerated() where !matchedRules.contains(index) {
            // Skip near-duplicates such as the model's "Midterm" for the rules' "Midterm Exam".
            let alreadyListed = merged.contains {
                RuleBasedSyllabusParser.titlesMatch($0.title, rule.title) && sameDay($0.dateText, rule.dateText)
            }
            if !alreadyListed { merged.append(rule) }
        }
        return merged
    }

    /// Debug builds can force the rule-based parser with the launch argument
    /// `-SyllabusDetector rules`, to test the fallback on a device that has Apple Intelligence.
    private static var forcesRules: Bool {
        #if DEBUG
        UserDefaults.standard.string(forKey: "SyllabusDetector") == "rules"
        #else
        false
        #endif
    }
}
