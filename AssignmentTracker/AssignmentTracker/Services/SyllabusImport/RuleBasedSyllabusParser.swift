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

/// Line-by-line syllabus parser built on patterns. It runs on every import (cross-checking the
/// on-device model) and is the fallback when the model isn't available. It handles the common
/// layouts: schedule tables ("Oct 12 | Topic | Problem Set 1; Quiz 2", one item per cell),
/// week-by-week schedules ("Week 3" headers followed by "Fri: Quiz 1"), date headings with
/// bullets under them, and grading breakdowns whose weights are matched back to dated items.
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
        /// A date written on its own line ("Friday, October 9"), applied to the lines under it.
        var dateHeading: String?

        func record(_ item: DetectedItem) {
            if item.dateText == nil { undated.append(item) } else { dated.append(item) }
        }

        for line in lines {
            var body = line
            if let header = weekHeader(in: line) {
                weekContext = header.week
                dateHeading = nil
                // "Week 3 (Sep 14–18)" also tells us when the term started.
                if termStart == nil, let expression = finder.firstExpression(in: header.rest),
                   let date = finder.resolve(expression.text).date {
                    termStart = weekOneStart(forWeek: header.week, containing: date)
                }
                body = header.rest
            }

            if let heading = Self.dateHeading(in: body, finder: finder) {
                dateHeading = heading
                continue
            }

            let cells = body.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if cells.count > 1 {
                // A table row: every cell that names an item is its own item, sharing the row's date.
                let rowDate = finder.firstExpression(in: body)?.text ?? dateHeading
                var rowItems: [DetectedItem] = []
                for cell in cells where Self.dateHeading(in: cell, finder: finder) == nil {
                    for piece in Self.pieces(of: cell) {
                        if let item = detectItem(in: piece, lineDate: rowDate, weekContext: weekContext, finder: finder) {
                            rowItems.append(item)
                        }
                    }
                }
                // A weight in its own column ("Midterm Exam | 20%") belongs to the row's one item.
                if rowItems.count == 1, rowItems[0].weight == nil,
                   let weightCell = cells.first(where: { Self.isWeightOnly($0) }) {
                    rowItems[0].weight = Self.weight(in: weightCell)
                }
                rowItems.forEach(record)
                continue
            }

            // Items under a date heading are usually bulleted, and a bullet there is an item
            // even without a keyword ("• Lab participation form").
            let isBullet = Self.contains(Self.bulletPrefix, in: body)
            var foundItem = false
            for sentence in Self.sentences(of: body) {
                // "Oct 20: Quiz 3; Lab report 2 due" – items in one sentence share its date,
                // but a date never carries over into the next sentence.
                let sentenceDate = finder.firstExpression(in: sentence)?.text ?? dateHeading
                for segment in sentence.components(separatedBy: ";") {
                    guard let item = detectItem(
                        in: segment, lineDate: sentenceDate, weekContext: weekContext, finder: finder,
                        acceptsAnyTitle: isBullet && dateHeading != nil
                    ) else { continue }
                    record(item)
                    foundItem = true
                }
            }
            // An ordinary line that isn't an item ends the dated block.
            if !isBullet, !foundItem { dateHeading = nil }
        }

        // Grading breakdown lines ("Midterm Exam ..... 25%") lend their weight to dated items
        // with the same name. A category line ("Problem Sets ..... 25%") is the category's
        // total, so it isn't copied onto each problem set.
        let weightedUndated = undated.filter { $0.weight != nil }.map { (title: Self.normalized($0.title), weight: $0.weight) }
        for index in dated.indices where dated[index].weight == nil {
            let title = Self.normalized(dated[index].title)
            if let match = weightedUndated.first(where: { $0.title == title }) {
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
        in segment: String, lineDate: String?, weekContext: Int?, finder: SyllabusDateResolver,
        acceptsAnyTitle: Bool = false
    ) -> DetectedItem? {
        let text = segment.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !Self.contains(Self.ignoredLine, in: text), !Self.contains(Self.columnHeader, in: text)
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

        guard let kind = Self.kind(of: text) ?? ((dateText != nil && (hasDueCue || acceptsAnyTitle)) ? .assignment : nil)
        else { return nil }

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

    /// The date text when a line is nothing but a date ("Friday, October 9", "Tue 9/8:").
    static func dateHeading(in line: String, finder: SyllabusDateResolver) -> String? {
        guard let expression = finder.firstExpression(in: line) else { return nil }
        var rest = line
        rest.removeSubrange(expression.range)
        let leftover = rest.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        return leftover.isEmpty ? expression.text : nil
    }

    static func isWeightOnly(_ cell: String) -> Bool {
        weight(in: cell) != nil
            && cell.replacingOccurrences(of: #"[\d.%\s]|pts|points"#, with: "", options: [.regularExpression, .caseInsensitive]).isEmpty
    }

    /// Splits a table cell into items: "Discussion Post 1; Worksheet 1: Designing a study".
    static func pieces(of cell: String) -> [String] {
        sentences(of: cell).flatMap { $0.components(separatedBy: ";") }
    }

    /// Splits a line at sentence breaks ("Panel data. Problem Set 3 due Oct 23").
    static func sentences(of line: String) -> [String] {
        line.replacingOccurrences(of: #"(?<=[a-z0-9)])\.\s+(?=[A-Z])"#, with: "\u{1E}", options: .regularExpression)
            .components(separatedBy: "\u{1E}")
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
            .replacingOccurrences(of: #"(\s*,)+"#, with: ",", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " :-–—,.;()[]|•*·"))
        // Trimming can take a closing parenthesis the title still needs: "Exam 2 (Chapters 7–11)".
        if working.filter({ $0 == "(" }).count > working.filter({ $0 == ")" }).count { working += ")" }
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
        (.quiz, regex(#"\b(quiz(zes)?|reading checks?|knowledge checks?|concept checks?)\b"#)),
        (.exam, regex(#"\b(exams?|midterms?|mid-terms?|prelims?)\b|\btests?\s*#?\d+\b|\b(unit|chapter|final|in-class|practice) tests?\b"#)),
        (.project, regex(#"\b(project|presentation|proposal|poster|capstone|demo)s?\b"#)),
        (.assignment, regex(#"\b(assignments?|homework|hw\s*#?\d*|problem sets?|p-?sets?|ps\s*#?\d+|problems? \d+|essays?|papers?|lab reports?|labs?\s*#?\d+|reports?|memos?|case (write-?up|study|analysis|brief)|responses?|reflections?|write-?ups?|submissions?|drafts?|discussion (posts?|boards?|forums?|questions?)|forum posts?|blog posts?|worksheets?|exercises?|journals?|journal entr(y|ies)|milestones?|deliverables?|checkpoints?|bibliograph(y|ies)|outlines?|abstracts?|critiques?|portfolios?|summar(y|ies)|extra credit|acknowledge?ments?|(book|article|literature|peer) reviews?|annotations?|due)\b"#)),
        // Only an actual reading, not a topic that cites a chapter ("Memory (Ch. 7)").
        (.reading, regex(#"\bread\s+(ch(apters?)?\b|pp?\.|pages?|articles?|sections?|§)|^\W*(?:(?:sun|mon|tue|wed|thu|fri|sat)[a-z]*\.?\s*[:\-–]\s*)?(read|readings?)\b(?!\s*(check|quiz))|\breadings? due\b"#)),
        (.exam, regex(#"\bfinal\b"#)),
    ]

    private static let weekHeaderPattern = regex(#"^\s*(?:week|wk\.?)\s*(\d{1,2})\b\s*[:.\-–—]?\s*"#)
    private static let dueCue = regex(#"\b(due|submit|turn in|hand in)\b"#)
    /// Policy and logistics lines that mention keywords but aren't graded items.
    private static let ignoredLine = regex(#"\b(no class|holiday|break|office hours|late (work|policy|submissions?)|policy|accommodations?|academic integrity|drop deadline|withdraw|review (session|day|class)|(exam|midterm|final|test) (review|prep))\b|^\s*(all|each|every|any|please)\b"#)
    /// Table column headings ("Assignments Due", "Topic & Readings").
    private static let columnHeader = regex(#"^\W*(wk|week|date|dates|day|class|session|topics?|topic\s*(&|and)\s*readings?|readings?|assignments?(\s+due)?|due|deliverables?|work due|what'?s due|notes|lecture|assessments?|schedule|weight|points)\W*$"#)
    private static let bulletPrefix = regex(#"^\s*[-•*·◦▪]\s"#)
    private static let percentPattern = regex(#"(\d{1,3}(?:\.\d+)?)\s*%"#)
    private static let pointsPattern = regex(#"(\d{1,4})\s*(?:pts|points)\b"#)
    private static let timePattern = regex(#"\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b\.?|\b(?:[01]?\d|2[0-3]):[0-5]\d\b"#)
    private static let titleNoise: [NSRegularExpression] = [
        regex(#"\([^)]*\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b[^)]*\)"#),
        regex(#"(?:,|\bat|\bby|@)?\s*\b\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b\.?"#),
        regex(#"\(?\s*\d{1,3}(?:\.\d+)?\s*%(?:\s*of (?:the )?(?:final )?grade)?\s*\)?"#),
        regex(#"\(?\s*\d{1,4}\s*(?:pts|points)\s*\)?"#),
        regex(#"\s*[—–-]?\s*\bdate\s*$"#),
        regex(#",?\s*\b(room|rm\.?|hall|bldg\.?|building)\s+\w+.*$"#),
        regex(#"\b(is |are )?(due|by|at|on)\b(?=\W*$)"#),
        regex(#"^\s*(?:[-•*·]|\d{1,2}[.)])\s+"#),
        regex(#"^\s*(?:sun|mon|tue|wed|thu|fri|sat)[a-z]*\.?\s*[:,\-–]\s*"#),
        regex(#"\b(due|submit(?:ted)?)\s+(?:by|on|at)?\s*$"#),
        regex(#"\.{2,}"#),
    ]
}
