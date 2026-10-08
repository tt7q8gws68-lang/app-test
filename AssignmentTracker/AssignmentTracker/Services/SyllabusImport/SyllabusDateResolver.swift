import Foundation

/// A due date worked out from syllabus text, plus how much to trust it.
nonisolated struct ResolvedDate: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        /// An explicit, unambiguous date.
        case confident
        /// A date was chosen, but the person should check it (the reason says why).
        case needsReview(String)
        /// No date could be placed (the reason says what's missing).
        case missing(String)
    }

    var date: Date?
    var status: Status

    static func missing(_ reason: String) -> ResolvedDate {
        ResolvedDate(date: nil, status: .missing(reason))
    }
}

/// Turns syllabus date text such as "Oct 12", "10/12/26", "Oct 12–14", "Week 3, Friday"
/// or "Friday of week 3 at 5pm" into dates.
///
/// Relative "Week N" dates need the semester start. Ranges, week-only dates and weekday
/// mismatches resolve to a date but are flagged for review rather than guessed silently.
nonisolated struct SyllabusDateResolver {
    var calendar: Calendar
    /// First day of classes. Week 1 is the Monday-to-Sunday week that contains it.
    var termStart: Date?
    /// Anchors the year for dates written without one (normally the import date).
    var referenceDate: Date
    /// Time used when the syllabus gives none.
    var defaultHour = 23
    var defaultMinute = 59

    init(calendar: Calendar = .current, termStart: Date? = nil, referenceDate: Date = .now) {
        self.calendar = calendar
        self.termStart = termStart
        self.referenceDate = referenceDate
    }

    struct Expression: Equatable {
        let range: Range<String.Index>
        let text: String
    }

    // MARK: - Finding date text

    /// The first date-like phrase in `text` (explicit date, week reference, or TBA).
    func firstExpression(in text: String) -> Expression? {
        let candidates = Self.expressionPatterns.compactMap { firstMatch(of: $0, in: text) }
        guard let earliest = candidates.min(by: { $0.lowerBound < $1.lowerBound }) else { return nil }
        var range = earliest
        // Include a weekday written just before the date ("Mon, Oct 12") so it can be checked.
        let head = String(text[..<range.lowerBound])
        if let weekday = firstMatch(of: Self.leadingWeekday, in: head) {
            let offset = head.distance(from: head.startIndex, to: weekday.lowerBound)
            range = text.index(text.startIndex, offsetBy: offset)..<range.upperBound
        }
        // Extend over an adjacent time ("Oct 12 at 5pm", "Oct 12, 11:59 PM").
        let tail = String(text[range.upperBound...])
        if let time = firstMatch(of: Self.trailingTime, in: tail) {
            let offset = tail.distance(from: tail.startIndex, to: time.upperBound)
            range = range.lowerBound..<text.index(range.upperBound, offsetBy: offset)
        }
        return Expression(range: range, text: String(text[range]))
    }

    /// Finds the semester start in lines like "Classes begin August 31, 2026" or
    /// "First day of class: 8/31".
    func termStart(in text: String) -> Date? {
        for line in text.components(separatedBy: .newlines) {
            guard firstMatch(of: Self.termStartCue, in: line) != nil,
                  let expression = firstExpression(in: line)
            else { continue }
            let resolver = SyllabusDateResolver(calendar: calendar, termStart: nil, referenceDate: referenceDate)
            if let date = resolver.resolve(expression.text).date {
                return calendar.startOfDay(for: date)
            }
        }
        return nil
    }

    // MARK: - Resolving

    func resolve(_ rawText: String) -> ResolvedDate {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .missing("No date given") }

        if firstMatch(of: Self.tba, in: text) != nil {
            return .missing("Date to be announced")
        }

        let time = parseTime(in: text)
        var reviewReasons: [String] = []
        if time == nil, firstMatch(of: Self.timeRange, in: text) != nil {
            // e.g. "2–4pm" – keep the default time but point it out.
            reviewReasons.append("Time range in syllabus")
        }

        guard var result = resolveDay(in: text) else {
            return .missing("No date found in “\(text)”")
        }

        if case .needsReview(let reason) = result.status { reviewReasons.insert(reason, at: 0) }
        if case .missing = result.status { return result }

        if let day = result.date {
            let hour = time?.hour ?? defaultHour
            let minute = time?.minute ?? defaultMinute
            result.date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
        }
        result.status = reviewReasons.isEmpty ? .confident : .needsReview(reviewReasons.joined(separator: " · "))
        return result
    }

    // MARK: - Day parsing

    private func resolveDay(in text: String) -> ResolvedDate? {
        // An explicit date beats a "(Week 7)" label on the same line.
        guard let parsed = parseExplicitDays(in: text) else { return parseWeekReference(in: text) }
        guard let start = parsed.start else { return .missing("“\(text)” isn’t a valid date") }

        var reasons: [String] = []
        var day = start
        if let end = parsed.end, !calendar.isDate(end, inSameDayAs: start) {
            day = end
            reasons.append("Date range in syllabus – using the last day")
        }
        if let weekday = parseWeekday(in: text), parsed.end == nil,
           calendar.component(.weekday, from: day) != weekday {
            let written = calendar.weekdaySymbols[weekday - 1]
            let actual = calendar.weekdaySymbols[calendar.component(.weekday, from: day) - 1]
            reasons.append("Syllabus says \(written) but that date is a \(actual)")
        }
        return ResolvedDate(date: day, status: reasons.isEmpty ? .confident : .needsReview(reasons.joined(separator: " · ")))
    }

    private func parseWeekReference(in text: String) -> ResolvedDate? {
        let ns = text as NSString
        var weekNumber: Int?
        var endWeek: Int?
        if let match = Self.weekdayOfWeek.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            weekNumber = Int(ns.substring(with: match.range(at: 2)))
        } else if let match = Self.weekNumber.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
            weekNumber = Int(ns.substring(with: match.range(at: 1)))
            if match.range(at: 2).location != NSNotFound {
                endWeek = Int(ns.substring(with: match.range(at: 2)))
            }
        }
        guard let weekNumber, weekNumber >= 1 else { return nil }

        guard let termStart else {
            return .missing("Set the semester start date to place Week \(weekNumber)")
        }

        var reasons: [String] = []
        var week = weekNumber
        if let endWeek, endWeek > weekNumber {
            week = endWeek
            reasons.append("Spans weeks \(weekNumber)–\(endWeek) – using week \(endWeek)")
        }
        let weekday: Int
        if let parsed = parseWeekday(in: text) {
            weekday = parsed
        } else {
            reasons.append("Only the week is given – using Friday")
            weekday = 6 // Friday
        }

        var mondayCalendar = calendar
        mondayCalendar.firstWeekday = 2
        guard let weekOneStart = mondayCalendar.dateInterval(of: .weekOfYear, for: termStart)?.start,
              let weekStart = calendar.date(byAdding: .day, value: (week - 1) * 7, to: weekOneStart)
        else { return .missing("Couldn’t place Week \(weekNumber)") }

        // Monday = 0 … Sunday = 6
        let offset = (weekday + 5) % 7
        let day = calendar.date(byAdding: .day, value: offset, to: weekStart)
        return ResolvedDate(date: day, status: reasons.isEmpty ? .confident : .needsReview(reasons.joined(separator: " · ")))
    }

    private struct ParsedDays {
        var start: Date?
        var end: Date?
    }

    private func parseExplicitDays(in text: String) -> ParsedDays? {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        func group(_ match: NSTextCheckingResult, _ index: Int) -> String? {
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : ns.substring(with: range)
        }

        if let m = Self.isoDate.firstMatch(in: text, range: whole) {
            let date = makeDate(year: Int(group(m, 1)!), month: Int(group(m, 2)!)!, day: Int(group(m, 3)!)!)
            return ParsedDays(start: date)
        }

        if let m = Self.monthNameDate.firstMatch(in: text, range: whole) {
            let month = Self.monthNumber(group(m, 1)!)
            let year = group(m, 5).flatMap { Int($0) }
            let start = makeDate(year: year, month: month, day: Int(group(m, 2)!)!)
            var end: Date?
            if let endDay = group(m, 4).flatMap({ Int($0) }) {
                let endMonth = group(m, 3).map(Self.monthNumber) ?? month
                end = makeDate(year: year, month: endMonth, day: endDay, notBefore: start)
            }
            return ParsedDays(start: start, end: end)
        }

        if let m = Self.dayMonthDate.firstMatch(in: text, range: whole) {
            let date = makeDate(year: group(m, 3).flatMap { Int($0) }, month: Self.monthNumber(group(m, 2)!), day: Int(group(m, 1)!)!)
            return ParsedDays(start: date)
        }

        if let m = Self.numericDate.firstMatch(in: text, range: whole) {
            let year = group(m, 3).flatMap { Int($0) }.map(Self.expandYear)
            let start = makeDate(year: year, month: Int(group(m, 1)!)!, day: Int(group(m, 2)!)!)
            var end: Date?
            if let endMonth = group(m, 4).flatMap({ Int($0) }), let endDay = group(m, 5).flatMap({ Int($0) }) {
                let endYear = group(m, 6).flatMap { Int($0) }.map(Self.expandYear) ?? year
                end = makeDate(year: endYear, month: endMonth, day: endDay, notBefore: start)
            }
            return ParsedDays(start: start, end: end)
        }

        return nil
    }

    /// Builds a date, inferring the year when the syllabus omits it: the earliest matching
    /// date on or after a month before the term start (or four months before the import date).
    private func makeDate(year: Int?, month: Int, day: Int, notBefore: Date? = nil) -> Date? {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        func build(_ year: Int) -> Date? {
            let components = DateComponents(year: year, month: month, day: day)
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day // rejects Feb 30 etc.
            else { return nil }
            return date
        }
        if let year { return build(year) }

        let anchor: Date = notBefore
            ?? termStart.flatMap { calendar.date(byAdding: .day, value: -30, to: $0) }
            ?? calendar.date(byAdding: .month, value: -4, to: referenceDate)!
        let anchorYear = calendar.component(.year, from: anchor)
        return (anchorYear...(anchorYear + 1))
            .compactMap(build)
            .first { $0 >= calendar.startOfDay(for: anchor) }
    }

    private static func expandYear(_ year: Int) -> Int {
        year < 100 ? 2000 + year : year
    }

    // MARK: - Weekdays and times

    /// Calendar weekday number (Sunday = 1) of the first weekday name in `text`.
    private func parseWeekday(in text: String) -> Int? {
        let ns = text as NSString
        guard let match = Self.weekdayName.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let prefix = ns.substring(with: match.range(at: 1)).lowercased().prefix(2)
        let order = ["su", "mo", "tu", "we", "th", "fr", "sa"]
        return order.firstIndex(of: String(prefix)).map { $0 + 1 }
    }

    private func parseTime(in text: String) -> (hour: Int, minute: Int)? {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        if firstMatch(of: Self.noon, in: text) != nil { return (12, 0) }
        if firstMatch(of: Self.midnight, in: text) != nil { return (23, 59) }
        if let m = Self.twelveHourTime.firstMatch(in: text, range: whole) {
            var hour = Int(ns.substring(with: m.range(at: 1)))!
            let minute = m.range(at: 2).location == NSNotFound ? 0 : Int(ns.substring(with: m.range(at: 2)))!
            let isPM = ns.substring(with: m.range(at: 3)).lowercased() == "p"
            guard (1...12).contains(hour), minute < 60 else { return nil }
            if hour == 12 { hour = 0 }
            return (isPM ? hour + 12 : hour, minute)
        }
        if let m = Self.twentyFourHourTime.firstMatch(in: text, range: whole) {
            return (Int(ns.substring(with: m.range(at: 1)))!, Int(ns.substring(with: m.range(at: 2)))!)
        }
        return nil
    }

    private func firstMatch(of regex: NSRegularExpression, in text: String) -> Range<String.Index>? {
        let ns = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return Range(match.range, in: text)
    }

    // MARK: - Patterns

    private static let month = #"(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)\.?"#
    private static let ordinal = #"(?:st|nd|rd|th)?"#
    private static let dash = #"\s*(?:-|–|—|to|through|thru)\s*"#
    private static let weekday = #"(sun(?:day)?|mon(?:day)?|tue(?:s(?:day)?)?|wed(?:nesday)?|thu(?:r(?:s(?:day)?)?)?|fri(?:day)?|sat(?:urday)?)(?![a-z])\.?"#

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    static let monthNameDate = regex(#"\b"# + month + #"\s+(\d{1,2})"# + ordinal + #"(?:"# + dash + #"(?:"# + month + #"\s+)?(\d{1,2})"# + ordinal + #")?(?:,?\s+(\d{4}))?\b"#)
    static let dayMonthDate = regex(#"\b(\d{1,2})"# + ordinal + #"\s+(?:of\s+)?"# + month + #"(?:,?\s+(\d{4}))?\b"#)
    static let isoDate = regex(#"\b(\d{4})-(\d{2})-(\d{2})\b"#)
    static let numericDate = regex(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?(?:"# + dash + #"(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?)?(?![\d/])"#)
    static let weekNumber = regex(#"\bw(?:ee)?ks?\.?\s*(\d{1,2})(?:"# + dash + #"(\d{1,2}))?\b"#)
    static let weekdayOfWeek = regex(#"\b"# + weekday + #"\s+(?:of\s+)?w(?:ee)?ks?\.?\s*(\d{1,2})\b"#)
    static let weekdayName = regex(#"\b"# + weekday)
    static let weekExpression = regex(#"\bw(?:ee)?ks?\.?\s*\d{1,2}(?:"# + dash + #"\d{1,2})?\b(?:\s*[,:(–-]?\s*"# + weekday + #")?"#)
    static let leadingWeekday = regex(#"\b"# + weekday + #",?\s*$"#)
    static let tba = regex(#"\b(tba|tbd|to be (?:announced|determined))\b"#)
    static let twelveHourTime = regex(#"\b(\d{1,2})(?::(\d{2}))?\s*([ap])\.?\s?m\b\.?"#)
    static let twentyFourHourTime = regex(#"\b([01]?\d|2[0-3]):([0-5]\d)\b"#)
    static let timeRange = regex(#"\b\d{1,2}(?::\d{2})?\s*(?:-|–)\s*\d{1,2}(?::\d{2})?\s*[ap]\.?m\b"#)
    static let noon = regex(#"\bnoon\b"#)
    static let midnight = regex(#"\bmidnight\b"#)
    static let trailingTime = regex(#"^\s*(?:,|at|by|@)?\s*(?:\d{1,2}(?::\d{2})?\s*[ap]\.?\s?m\b\.?|\d{1,2}:\d{2}|noon|midnight)"#)
    static let termStartCue = regex(#"\b(classes|semester|term|quarter|instruction|course)\s+(begins?|starts?|commences?)\b|\bfirst (day|week) of (classes|class|the (semester|term))\b|\bweek\s*1\s*(begins|starts)\b"#)

    private static let expressionPatterns: [NSRegularExpression] = [
        tba, weekdayOfWeek, weekExpression, isoDate, monthNameDate, dayMonthDate, numericDate,
    ]

    private static func monthNumber(_ name: String) -> Int {
        let key = name.lowercased().prefix(3)
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
        return (months.firstIndex(of: String(key)) ?? 0) + 1
    }
}
