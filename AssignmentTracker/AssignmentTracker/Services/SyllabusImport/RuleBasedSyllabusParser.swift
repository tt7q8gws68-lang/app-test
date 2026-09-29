import Foundation

/// One graded item found in a syllabus, before its date is resolved.
nonisolated struct DetectedItem: Equatable, Sendable {
    var title: String
    var kind: AssignmentKind
    /// The date as written ("Oct 12", "Week 3, Friday"), or nil when none was found.
    var dateText: String?
    var weight: String?
    var notes: String = ""
}

nonisolated struct SyllabusParseResult: Equatable, Sendable {
    var items: [DetectedItem]
    var termStart: Date?
}

/// Line-by-line syllabus parser built on patterns. It's the fallback when the on-device
/// language model isn't available, and it handles the common layouts: schedule tables
/// ("Oct 12 | Problem Set 1 due | 5%"), week-by-week schedules ("Week 3" headers followed
/// by "Fri: Quiz 1"), and grading breakdowns whose weights are matched back to dated items.
nonisolated struct RuleBasedSyllabusParser {
    var calendar: Calendar = .current
    var referenceDate: Date = .now

    func parse(_ text: String) -> SyllabusParseResult {
        let lines = normalizedLines(text)
        let finder = SyllabusDateResolver(calendar: calendar, referenceDate: referenceDate)
        var termStart = finder.termStart(in: text)

        var dated: [DetectedItem] = []
        var undated: [DetectedItem] = []
        var weekContext: Int?

        for line in lines {
            var body = line
            if let header = weekHeader(in: line) {
                weekContext = header.week
                // "Week 3 (Sep 14–18)" also tells us when the term started.
                if termStart == nil, let expression = finder.firstExpression(in: header.rest),
                   let date = finder.resolve(expression.text).date {
                    termStart = weekOneStart(forWeek: header.week, containing: date)
                }
                body = header.rest
            }

            // "Oct 20: Quiz 3; Lab report 2 due" – later segments share the line's date.
            let lineDate = finder.firstExpression(in: body)?.text
            for segment in Self.segments(of: body) {
                guard let item = detectItem(in: segment, lineDate: lineDate, weekContext: weekContext, finder: finder)
                else { continue }
                if item.dateText == nil { undated.append(item) } else { dated.append(item) }
            }
        }

        // Grading breakdown lines ("Midterm Exam ..... 25%") lend their weight to dated items
        // with the same name. A category line ("Problem Sets ..... 25%") is the category's
        // total, so it isn't copied onto each problem set.
        for index in dated.indices where dated[index].weight == nil {
            let title = Self.normalized(dated[index].title)
            if let match = undated.first(where: { $0.weight != nil && Self.normalized($0.title) == title }) {
                dated[index].weight = match.weight
            }
        }

        // A syllabus with no dates at all still yields its items, for the person to date.
        let items = dated.isEmpty ? undated : dated
        return SyllabusParseResult(items: Self.deduplicated(items), termStart: termStart)
    }

    // MARK: - Line handling

    private func normalizedLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: "\t", with: " | ")
                    .replacingOccurrences(of: #" {3,}"#, with: " | ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
    }

    private func weekHeader(in line: String) -> (week: Int, rest: String)? {
        let ns = line as NSString
        guard let match = Self.weekHeaderPattern.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)),
              let week = Int(ns.substring(with: match.range(at: 1)))
        else { return nil }
        return (week, ns.substring(from: match.range.upperBound))
    }

    private func weekOneStart(forWeek week: Int, containing date: Date) -> Date? {
        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let start = mondayCalendar.dateInterval(of: .weekOfYear, for: date)?.start else { return nil }
        return calendar.date(byAdding: .day, value: -(week - 1) * 7, to: start)
    }

    private func detectItem(
        in segment: String, lineDate: String?, weekContext: Int?, finder: SyllabusDateResolver
    ) -> DetectedItem? {
        let text = segment.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, Self.ignoredLine.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil
        else { return nil }

        let expression = finder.firstExpression(in: text)
        var dateText = expression?.text ?? lineDate
        // A time elsewhere in the row ("Midterm (in class, 9:30am)") belongs to the date.
        if let date = dateText, Self.contains(Self.timePattern, in: text), !Self.contains(Self.timePattern, in: date) {
            let ns = text as NSString
            let time = Self.timePattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length))!
            dateText = "\(date) at \(ns.substring(with: time.range))"
        }
        let hasDueCue = Self.contains(Self.dueCue, in: text)

        guard let kind = Self.kind(of: text) ?? ((dateText != nil && hasDueCue) ? .assignment : nil) else { return nil }

        // "Fri: Quiz 1" under a "Week 3" header.
        if dateText == nil, let weekContext {
            let ns = text as NSString
            if let weekday = SyllabusDateResolver.weekdayName.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                dateText = "Week \(weekContext), \(ns.substring(with: weekday.range))"
            } else if hasDueCue {
                dateText = "Week \(weekContext)"
            }
        }

        let weight = Self.weight(in: text)
        let title = Self.cleanTitle(text, removing: expression?.range)
        guard title.count >= 3 else { return nil }

        return DetectedItem(
            title: title,
            kind: kind,
            dateText: dateText,
            weight: weight,
            notes: "From syllabus: \(text)"
        )
    }

    // MARK: - Classification

    static func kind(of text: String) -> AssignmentKind? {
        for (kind, pattern) in kindPatterns where contains(pattern, in: text) {
            return kind
        }
        return nil
    }

    static func weight(in text: String) -> String? {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if let match = percentPattern.firstMatch(in: text, range: whole) {
            return ns.substring(with: match.range(at: 1)) + "%"
        }
        if let match = pointsPattern.firstMatch(in: text, range: whole) {
            return ns.substring(with: match.range(at: 1)) + " pts"
        }
        return nil
    }

    /// Splits a line into separate items at semicolons and sentence breaks
    /// ("Panel data. Problem Set 3 due Oct 23").
    static func segments(of line: String) -> [String] {
        line.replacingOccurrences(of: #"(?<=[a-z0-9)])\.\s+(?=[A-Z])"#, with: ";", options: .regularExpression)
            .components(separatedBy: ";")
    }

    static func cleanTitle(_ text: String, removing dateRange: Range<String.Index>?) -> String {
        var working = text
        if let dateRange {
            // "Final Exam: Friday, December 11, 9 AM – noon, Hall B" – what follows the date
            // is logistics when the part before it already names the item.
            let before = String(text[..<dateRange.lowerBound])
            if kind(of: before) != nil, !before.contains("|") {
                working = before
            } else {
                working.replaceSubrange(dateRange, with: " ")
            }
        }

        // Table rows: keep the column that names the item.
        let columns = working.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        if columns.count > 1 {
            working = columns.first { kind(of: $0) != nil } ?? columns.max { $0.count < $1.count } ?? working
        }

        for pattern in titleNoise {
            working = pattern.stringByReplacingMatches(
                in: working, range: NSRange(working.startIndex..., in: working), withTemplate: " "
            )
        }
        working = working
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;()[]|•*·"))
        guard let first = working.first else { return "" }
        return first.uppercased() + working.dropFirst()
    }

    /// Whether one title's words appear, in order, within the other's
    /// ("Midterm" ~ "Midterm Exam", but not "Problem Set 1" ~ "Problem Set 10").
    static func titlesMatch(_ a: String, _ b: String) -> Bool {
        let x = normalized(a).split(separator: " "), y = normalized(b).split(separator: " ")
        guard !x.isEmpty, !y.isEmpty else { return false }
        let (short, long) = x.count <= y.count ? (x, y) : (y, x)
        return (0...(long.count - short.count)).contains { Array(long[$0..<($0 + short.count)]) == short }
    }

    static func normalized(_ title: String) -> String {
        title.lowercased()
            .replacingOccurrences(of: #"[^a-z0-9 ]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\b(due|the|a|an|and|of|on)\b"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func deduplicated(_ items: [DetectedItem]) -> [DetectedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert(normalized($0.title) + "|" + ($0.dateText ?? "")).inserted }
    }

    private static func contains(_ regex: NSRegularExpression, in text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    // MARK: - Patterns

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    /// Checked in order: the first match wins ("Final Project" is a project, "Final Exam" an exam).
    private static let kindPatterns: [(AssignmentKind, NSRegularExpression)] = [
        (.quiz, regex(#"\bquiz(zes)?\b"#)),
        (.exam, regex(#"\b(exam|midterm|mid-term|test)s?\b"#)),
        (.project, regex(#"\b(project|presentation|proposal|poster|capstone)s?\b"#)),
        (.assignment, regex(#"\b(assignment|homework|hw\s*#?\d*|problem sets?|p-?set|ps\s*#?\d+|essay|paper|lab report|lab \d+|report|memo|case (write-?up|study|analysis)|response|reflection|write-?up|submission|draft|due)\b"#)),
        (.reading, regex(#"\b(read|reading|readings|chapters?|ch\.\s*\d+)\b"#)),
        (.exam, regex(#"\bfinal\b"#)),
    ]

    private static let weekHeaderPattern = regex(#"^\s*(?:week|wk\.?)\s*(\d{1,2})\b\s*[:.\-–—]?\s*"#)
    private static let dueCue = regex(#"\b(due|submit|turn in|hand in)\b"#)
    /// Policy and logistics lines that mention keywords but aren't graded items.
    private static let ignoredLine = regex(#"\b(no class|holiday|break|office hours|late (work|policy|submissions?)|policy|accommodations?|academic integrity|drop deadline|withdraw)\b"#)
    private static let percentPattern = regex(#"(\d{1,3}(?:\.\d+)?)\s*%"#)
    private static let pointsPattern = regex(#"(\d{1,4})\s*(?:pts|points)\b"#)
    private static let timePattern = regex(#"\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b\.?|\b(?:[01]?\d|2[0-3]):[0-5]\d\b"#)
    private static let titleNoise: [NSRegularExpression] = [
        regex(#"\([^)]*\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b[^)]*\)"#),
        regex(#"(?:,|\bat|\bby|@)?\s*\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b\.?"#),
        regex(#"\(?\s*\d{1,3}(?:\.\d+)?\s*%(?:\s*of (?:the )?(?:final )?grade)?\s*\)?"#),
        regex(#"\(?\s*\d{1,4}\s*(?:pts|points)\s*\)?"#),
        regex(#"\s*[—–-]?\s*\bdate\s*$"#),
        regex(#"\b(is |are )?(due|by|at|on)\b(?=\W*$)"#),
        regex(#"^\s*(?:[-•*·]|\d{1,2}[.)])\s+"#),
        regex(#"^\s*(?:sun|mon|tue|wed|thu|fri|sat)[a-z]*\.?\s*[:,\-–]\s*"#),
        regex(#"\b(due|submit(?:ted)?)\s+(?:by|on|at)?\s*$"#),
        regex(#"\.{2,}"#),
    ]
}
