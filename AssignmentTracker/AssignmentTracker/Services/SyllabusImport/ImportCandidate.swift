import Foundation

/// A detected item on the review screen, before it becomes an `Assignment`.
nonisolated struct ImportCandidate: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    var kind: AssignmentKind
    /// The date as the syllabus wrote it, kept for display and for re-resolving
    /// when the semester start changes.
    var dateText: String?
    var dueDate: Date?
    var dateStatus: ResolvedDate.Status
    /// Once the person picks a date themselves, changing the semester start leaves it alone.
    var dateSetByUser = false
    var weight: String?
    var notes: String
    var isIncluded: Bool
    /// Title of a matching assignment already in the class.
    var duplicateOf: String?

    init(
        id: UUID = UUID(), title: String, kind: AssignmentKind, dateText: String? = nil,
        dueDate: Date? = nil, dateStatus: ResolvedDate.Status = .missing("No date given"),
        weight: String? = nil, notes: String = "", isIncluded: Bool = true, duplicateOf: String? = nil
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.dateText = dateText
        self.dueDate = dueDate
        self.dateStatus = dateStatus
        self.weight = weight
        self.notes = notes
        self.isIncluded = isIncluded
        self.duplicateOf = duplicateOf
    }

    var reviewReason: String? {
        switch dateStatus {
        case .confident: nil
        case .needsReview(let reason), .missing(let reason): reason
        }
    }

    /// Due before the import day: added as already done.
    func isPast(relativeTo now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let dueDate else { return false }
        return dueDate < calendar.startOfDay(for: now)
    }

    var suggestedPriority: Priority {
        let percent = weight.flatMap { Double($0.replacingOccurrences(of: "%", with: "")) }
        if kind == .exam || (percent ?? 0) >= 20 { return .high }
        if kind == .reading { return .low }
        return .medium
    }
}

/// Summary of an existing assignment, for duplicate checks.
nonisolated struct ExistingAssignment: Sendable {
    var title: String
    var dueDate: Date
}

nonisolated enum ImportCandidateBuilder {
    /// Resolves each item's date and decides whether it's included by default: items without
    /// a date or already in the class start unchecked. Past items are included and saved as done,
    /// so importing mid-semester still gives the class a complete record.
    static func candidates(
        from items: [DetectedItem], resolver: SyllabusDateResolver, existing: [ExistingAssignment]
    ) -> [ImportCandidate] {
        items.map { item in
            var candidate = ImportCandidate(title: item.title, kind: item.kind, dateText: item.dateText, weight: item.weight, notes: item.notes)
            resolve(&candidate, with: resolver)
            candidate.duplicateOf = duplicate(of: candidate, in: existing, calendar: resolver.calendar)?.title
            candidate.isIncluded = defaultInclusion(for: candidate)
            return candidate
        }
    }

    /// Re-resolves dates the person hasn't set by hand (after the semester start changes).
    static func reresolve(_ candidates: inout [ImportCandidate], with resolver: SyllabusDateResolver) {
        for index in candidates.indices where !candidates[index].dateSetByUser {
            let hadDate = candidates[index].dueDate != nil
            resolve(&candidates[index], with: resolver)
            // Items that just gained a date become importable.
            if !hadDate, candidates[index].dueDate != nil {
                candidates[index].isIncluded = defaultInclusion(for: candidates[index])
            }
        }
    }

    static func resolve(_ candidate: inout ImportCandidate, with resolver: SyllabusDateResolver) {
        guard let text = candidate.dateText else {
            candidate.dueDate = nil
            candidate.dateStatus = .missing("No date in the syllabus")
            return
        }
        let resolved = resolver.resolve(text)
        candidate.dueDate = resolved.date
        candidate.dateStatus = resolved.status
    }

    static func defaultInclusion(for candidate: ImportCandidate) -> Bool {
        candidate.dueDate != nil && candidate.duplicateOf == nil
    }

    /// Same title (ignoring case, punctuation and filler words) and same day, or same title
    /// when the candidate has no date yet.
    static func duplicate(of candidate: ImportCandidate, in existing: [ExistingAssignment], calendar: Calendar) -> ExistingAssignment? {
        let title = RuleBasedSyllabusParser.normalized(candidate.title)
        return existing.first { assignment in
            guard RuleBasedSyllabusParser.normalized(assignment.title) == title else { return false }
            guard let due = candidate.dueDate else { return true }
            return calendar.isDate(due, inSameDayAs: assignment.dueDate)
        }
    }
}
