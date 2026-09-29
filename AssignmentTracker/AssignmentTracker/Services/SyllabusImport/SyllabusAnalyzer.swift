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

    @concurrent
    func analyze(_ text: String) async -> SyllabusAnalysis {
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
                let model = try await FoundationModelSyllabusParser().parse(text)
                guard !model.items.isEmpty || rules.items.isEmpty else {
                    return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: "Apple Intelligence found nothing"))
                }
                let modelTermStart = model.termStartText
                    .flatMap { resolver.resolve($0).date }
                    .map { calendar.startOfDay(for: $0) }
                return SyllabusAnalysis(
                    items: Self.withWeights(model.items, from: rules.items),
                    termStart: modelTermStart ?? rules.termStart,
                    engine: .onDeviceModel
                )
            } catch {
                return SyllabusAnalysis(items: rules.items, termStart: rules.termStart, engine: .rules(reason: "Apple Intelligence couldn’t read this syllabus"))
            }
        }
    }

    /// Fills missing weights from what the rule-based pass found for the same item.
    private static func withWeights(_ items: [DetectedItem], from rules: [DetectedItem]) -> [DetectedItem] {
        items.map { item in
            guard item.weight == nil,
                  let match = rules.first(where: { $0.weight != nil && RuleBasedSyllabusParser.titlesMatch($0.title, item.title) })
            else { return item }
            var item = item
            item.weight = match.weight
            return item
        }
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
