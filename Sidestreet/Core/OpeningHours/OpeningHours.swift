import Foundation

/// Parser and evaluator for the OpenStreetMap `opening_hours` syntax.
///
/// Supports the commonly used subset: weekday ranges and lists, `24/7`,
/// multiple time spans, spans past midnight, open end (`18:00+`), `off` /
/// `closed`, month ranges, specific dates (`2026 Nov 21`, `Dec 24-26`),
/// nth weekday of the month (`Su[1]`, `Sa[-1]`), additional rules and
/// comments. Public/school-holiday rules (`PH`, `SH`) are recognised but cannot
/// be evaluated without a holiday calendar, so they are skipped and flagged.
///
/// Anything outside this subset (sunrise/sunset, week numbers, easter,
/// fallback rules `||`) makes `parse` return `nil`, so the app shows the raw
/// value and an "hours unknown" status instead of guessing.
struct OpeningHours: Hashable, Sendable {
    struct TimeSpan: Hashable, Sendable {
        /// Minutes after midnight. `end` may exceed 1440 for spans past midnight.
        var start: Int
        var end: Int
        var openEnd: Bool = false
    }

    struct MonthDay: Hashable, Sendable {
        var month: Int
        var day: Int
    }

    enum DateSelector: Hashable, Sendable {
        /// Inclusive month range, may wrap (Nov-Feb).
        case months(Int, Int)
        /// Inclusive date range within a year, may wrap.
        case dates(MonthDay, MonthDay)
    }

    struct Rule: Hashable, Sendable {
        var year: Int?
        var dateSelectors: [DateSelector] = []
        /// ISO weekdays 1 = Monday … 7 = Sunday; nil means every day.
        var weekdays: Set<Int>?
        /// For `Su[1]`-style selectors: allowed occurrences in the month (1…5, -1…-5).
        var nthOccurrences: Set<Int>?
        var spans: [TimeSpan]
        var isOff: Bool
        var isAdditional: Bool
        var isHolidayOnly: Bool
        var mentionsHoliday: Bool = false
        var comment: String?
    }

    enum Status: Hashable, Sendable {
        case open(closesAt: Date?)
        case closed(opensAt: Date?)
        case unknown
    }

    let raw: String
    let rules: [Rule]
    /// True when the value contained PH/SH rules that were not evaluated.
    let hasHolidayRules: Bool
    let isAlwaysOpen: Bool

    // MARK: - Parsing

    static func parse(_ value: String) -> OpeningHours? {
        let raw = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if raw == "24/7" {
            return OpeningHours(raw: raw, rules: [], hasHolidayRules: false, isAlwaysOpen: true)
        }
        let lowered = raw.lowercased()
        for unsupported in ["sunrise", "sunset", "dawn", "dusk", "week ", "easter", "||", "unknown"] where lowered.contains(unsupported) {
            return nil
        }

        // Extract quoted comments.
        var text = ""
        var comments: [String] = []
        var inQuote = false
        var currentComment = ""
        for ch in raw {
            if ch == "\"" {
                if inQuote { comments.append(currentComment); currentComment = "" }
                inQuote.toggle()
                if !inQuote { text.append("\u{1}") }
                continue
            }
            if inQuote { currentComment.append(ch) } else { text.append(ch) }
        }
        guard !inQuote else { return nil }

        var rules: [Rule] = []
        var hasHoliday = false
        var commentIndex = 0
        for (ruleText, isAdditional) in splitRules(text) {
            var ruleString = ruleText.trimmingCharacters(in: .whitespaces)
            var comment: String?
            if ruleString.contains("\u{1}") {
                comment = commentIndex < comments.count ? comments[commentIndex] : nil
                commentIndex += 1
                ruleString = ruleString.replacingOccurrences(of: "\u{1}", with: " ")
                    .trimmingCharacters(in: .whitespaces)
            }
            if ruleString.isEmpty { continue }
            guard var rule = parseRule(ruleString, isAdditional: isAdditional) else { return nil }
            rule.comment = comment
            if rule.mentionsHoliday { hasHoliday = true }
            if rule.isHolidayOnly { continue }
            rules.append(rule)
        }
        guard !rules.isEmpty else { return nil }
        let alwaysOpen = rules.count == 1 && rules[0].weekdays == nil && rules[0].dateSelectors.isEmpty
            && rules[0].year == nil && rules[0].spans == [TimeSpan(start: 0, end: 1440)]
        return OpeningHours(raw: raw, rules: rules, hasHolidayRules: hasHoliday, isAlwaysOpen: alwaysOpen)
    }

    /// Splits on `;` (normal rules) and on `,` followed by a new selector
    /// (additional rules). Commas between time spans or weekdays stay inside
    /// the rule.
    private static func splitRules(_ text: String) -> [(String, Bool)] {
        var result: [(String, Bool)] = []
        for part in text.split(separator: ";", omittingEmptySubsequences: true) {
            let pieces = part.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            var current = ""
            var currentIsAdditional = false
            for piece in pieces {
                let trimmed = piece.trimmingCharacters(in: .whitespaces)
                if current.isEmpty {
                    current = trimmed
                    continue
                }
                // A piece that starts a new selector *and* has its own time/off
                // part is an additional rule ("Mo-Fr 10:00-18:00, Sa 10:00-14:00").
                if startsWithSelector(trimmed) && containsTimeOrState(trimmed) && containsTimeOrState(current) {
                    result.append((current, currentIsAdditional))
                    current = trimmed
                    currentIsAdditional = true
                } else {
                    current += "," + trimmed
                }
            }
            if !current.isEmpty { result.append((current, currentIsAdditional)) }
        }
        return result
    }

    private static let weekdayTokens = ["mo": 1, "tu": 2, "we": 3, "th": 4, "fr": 5, "sa": 6, "su": 7]
    private static let monthTokens = ["jan": 1, "feb": 2, "mar": 3, "apr": 4, "may": 5, "jun": 6,
                                      "jul": 7, "aug": 8, "sep": 9, "oct": 10, "nov": 11, "dec": 12]

    private static func startsWithSelector(_ s: String) -> Bool {
        let lower = s.lowercased()
        let prefix2 = String(lower.prefix(2))
        let prefix3 = String(lower.prefix(3))
        return weekdayTokens[prefix2] != nil || monthTokens[prefix3] != nil
            || prefix2 == "ph" || prefix2 == "sh" || lower.first.map(\.isNumber) == true && lower.count >= 4
            && Int(lower.prefix(4)) != nil && !lower.prefix(5).contains(":")
    }

    private static func containsTimeOrState(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower.contains(":") || lower.contains("off") || lower.contains("closed") || lower.contains("open")
    }

    private static func parseRule(_ text: String, isAdditional: Bool) -> Rule? {
        var tokens = tokenize(text)
        var rule = Rule(year: nil, weekdays: nil, nthOccurrences: nil, spans: [], isOff: false,
                        isAdditional: isAdditional, isHolidayOnly: false, comment: nil)
        var sawWeekday = false
        var sawHoliday = false

        // Year
        if let first = tokens.first, first.count == 4, let year = Int(first), (1900...2100).contains(year) {
            rule.year = year
            tokens.removeFirst()
        }

        // Date / month selectors (comma separated), e.g. "Apr-Oct", "Dec 24-26", "Jan 01-Mar 15".
        while let first = tokens.first, let month = monthTokens[first.lowercased()] {
            tokens.removeFirst()
            var startDay: Int?
            if let next = tokens.first, let day = Int(next), (1...31).contains(day) {
                startDay = day
                tokens.removeFirst()
            }
            var selector: DateSelector
            if tokens.first == "-" {
                tokens.removeFirst()
                guard let next = tokens.first else { return nil }
                if let endMonth = monthTokens[next.lowercased()] {
                    tokens.removeFirst()
                    if let startDay {
                        guard let dayToken = tokens.first, let endDay = Int(dayToken) else { return nil }
                        tokens.removeFirst()
                        selector = .dates(MonthDay(month: month, day: startDay), MonthDay(month: endMonth, day: endDay))
                    } else if let dayToken = tokens.first, let endDay = Int(dayToken), (1...31).contains(endDay) {
                        // "Jan-Mar 15" is unusual; treat as unsupported.
                        _ = endDay
                        return nil
                    } else {
                        selector = .months(month, endMonth)
                    }
                } else if let endDay = Int(next), let startDay {
                    tokens.removeFirst()
                    selector = .dates(MonthDay(month: month, day: startDay), MonthDay(month: month, day: endDay))
                } else {
                    return nil
                }
            } else if let startDay {
                selector = .dates(MonthDay(month: month, day: startDay), MonthDay(month: month, day: startDay))
            } else {
                selector = .months(month, month)
            }
            rule.dateSelectors.append(selector)
            if tokens.first == "," { tokens.removeFirst() } else { break }
        }
        if tokens.first == ":" { tokens.removeFirst() }

        // Weekday / holiday selectors.
        var weekdays = Set<Int>()
        while let first = tokens.first {
            let lower = first.lowercased()
            if lower == "ph" || lower == "sh" {
                sawHoliday = true
                tokens.removeFirst()
            } else if let day = weekdayTokens[lower] {
                sawWeekday = true
                tokens.removeFirst()
                if tokens.first == "-", tokens.count >= 2, let endDay = weekdayTokens[tokens[1].lowercased()] {
                    tokens.removeFirst(2)
                    var d = day
                    weekdays.insert(d)
                    while d != endDay {
                        d = d % 7 + 1
                        weekdays.insert(d)
                    }
                } else {
                    weekdays.insert(day)
                }
                if tokens.first == "[" {
                    tokens.removeFirst()
                    var nths = Set<Int>()
                    var previous: String? = nil
                    var lastValue: Int? = nil
                    while let token = tokens.first, token != "]" {
                        tokens.removeFirst()
                        defer { previous = token }
                        if token == "," { continue }
                        if token == "-" {
                            guard let next = tokens.first, let value = Int(next), (1...5).contains(value) else { return nil }
                            tokens.removeFirst()
                            // "-1" means "last"; "1-3" is a range.
                            if let start = lastValue, previous != nil, previous != "," {
                                for v in start...max(start, value) { nths.insert(v) }
                            } else {
                                nths.insert(-value)
                            }
                            lastValue = nil
                            continue
                        }
                        guard let value = Int(token), (1...5).contains(value) else { return nil }
                        nths.insert(value)
                        lastValue = value
                    }
                    guard tokens.first == "]" else { return nil }
                    tokens.removeFirst()
                    rule.nthOccurrences = (rule.nthOccurrences ?? []).union(nths)
                }
            } else {
                break
            }
            if tokens.first == "," { tokens.removeFirst() } else { break }
        }
        if tokens.first == ":" { tokens.removeFirst() }

        rule.mentionsHoliday = sawHoliday
        if sawHoliday && !sawWeekday {
            rule.isHolidayOnly = true
            return rule
        }
        if sawWeekday { rule.weekdays = weekdays }

        // Times or state.
        if tokens.isEmpty {
            // Selector without time, e.g. "Mo-Fr" alone, means open all day in
            // the spec, but in practice it is usually an error — unsupported.
            return nil
        }
        let remaining = tokens.joined()
        let lowerRemaining = remaining.lowercased()
        if lowerRemaining == "off" || lowerRemaining == "closed" {
            rule.isOff = true
            return rule
        }
        if lowerRemaining == "open" {
            rule.spans = [TimeSpan(start: 0, end: 1440)]
            return rule
        }
        var spans: [TimeSpan] = []
        for spanText in remaining.split(separator: ",") {
            guard let span = parseSpan(String(spanText)) else { return nil }
            spans.append(span)
        }
        guard !spans.isEmpty else { return nil }
        rule.spans = spans
        return rule
    }

    private static func parseSpan(_ text: String) -> TimeSpan? {
        var s = text.trimmingCharacters(in: .whitespaces)
        var openEnd = false
        if s.hasSuffix("+") {
            openEnd = true
            s.removeLast()
        }
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 1, openEnd, let start = parseTime(String(parts[0])) {
            return TimeSpan(start: start, end: 1440, openEnd: true)
        }
        guard parts.count == 2, let start = parseTime(String(parts[0])), var end = parseTime(String(parts[1])) else {
            return nil
        }
        guard start < 1440 else { return nil }
        if end <= start { end += 1440 }
        guard end <= 2880 else { return nil }
        return TimeSpan(start: start, end: end, openEnd: openEnd)
    }

    private static func parseTime(_ text: String) -> Int? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count == 2, parts[1].count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0...48).contains(h), (0...59).contains(m) else { return nil }
        let minutes = h * 60 + m
        return minutes <= 2880 ? minutes : nil
    }

    /// Splits into tokens: words, numbers, times ("10:00"), and punctuation.
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { tokens.append(current); current = "" }
        }
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == " " || ch == "\t" {
                flush()
            } else if ch == "," || ch == "[" || ch == "]" {
                flush(); tokens.append(String(ch))
            } else if ch == "-" {
                // Keep "-" inside time spans ("10:00-18:00") as part of the time token.
                let prevIsTime = current.contains(":")
                if prevIsTime {
                    current.append(ch)
                } else {
                    flush(); tokens.append("-")
                }
            } else if ch == ":" {
                // A colon directly after a selector word ("Apr-Oct:") is a separator,
                // a colon after digits is part of a time.
                if let last = current.last, last.isNumber {
                    current.append(ch)
                } else {
                    flush(); tokens.append(":")
                }
            } else {
                current.append(ch)
            }
            i += 1
        }
        flush()
        // Re-join tokens of a time list: "10:00-12:00", ",", "13:00-18:00" stays split
        // by commas, which parseRule handles via `joined()`.
        return tokens
    }

    // MARK: - Evaluation

    private static func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        return calendar
    }

    /// ISO weekday (1 = Monday … 7 = Sunday).
    private static func isoWeekday(_ date: Date, calendar: Calendar) -> Int {
        let weekday = calendar.component(.weekday, from: date) // 1 = Sunday
        return weekday == 1 ? 7 : weekday - 1
    }

    private func matches(_ rule: Rule, day: Date, calendar: Calendar) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day], from: day)
        guard let year = comps.year, let month = comps.month, let dayOfMonth = comps.day else { return false }
        if let ruleYear = rule.year, ruleYear != year { return false }
        if !rule.dateSelectors.isEmpty {
            let inAny = rule.dateSelectors.contains { selector in
                switch selector {
                case let .months(start, end):
                    return start <= end ? (start...end).contains(month) : (month >= start || month <= end)
                case let .dates(start, end):
                    let value = month * 100 + dayOfMonth
                    let s = start.month * 100 + start.day
                    let e = end.month * 100 + end.day
                    return s <= e ? (s...e).contains(value) : (value >= s || value <= e)
                }
            }
            if !inAny { return false }
        }
        if let weekdays = rule.weekdays {
            let weekday = Self.isoWeekday(day, calendar: calendar)
            guard weekdays.contains(weekday) else { return false }
            if let nths = rule.nthOccurrences, !nths.isEmpty {
                let occurrence = (dayOfMonth - 1) / 7 + 1
                let daysInMonth = calendar.range(of: .day, in: .month, for: day)?.count ?? 31
                let reverseOccurrence = -((daysInMonth - dayOfMonth) / 7 + 1)
                guard nths.contains(occurrence) || nths.contains(reverseOccurrence) else { return false }
            }
        }
        return true
    }

    /// The spans that *start* on the given day (minutes from that midnight).
    func spansStarting(on day: Date, timeZone: TimeZone) -> [TimeSpan] {
        if isAlwaysOpen { return [TimeSpan(start: 0, end: 1440)] }
        let calendar = Self.calendar(in: timeZone)
        var spans: [TimeSpan]? = nil
        for rule in rules where matches(rule, day: day, calendar: calendar) {
            if rule.isAdditional {
                spans = (spans ?? []) + (rule.isOff ? [] : rule.spans)
            } else {
                spans = rule.isOff ? [] : rule.spans
            }
        }
        return spans ?? []
    }

    /// Absolute open intervals overlapping the given day (includes spill-over
    /// from the previous day's late spans).
    func intervals(around date: Date, timeZone: TimeZone, daysBefore: Int = 1, daysAfter: Int = 7) -> [(start: Date, end: Date, openEnd: Bool)] {
        let calendar = Self.calendar(in: timeZone)
        let startOfDay = calendar.startOfDay(for: date)
        var result: [(Date, Date, Bool)] = []
        for offset in -daysBefore...daysAfter {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            for span in spansStarting(on: day, timeZone: timeZone) {
                let s = day.addingTimeInterval(TimeInterval(span.start * 60))
                let e = day.addingTimeInterval(TimeInterval(span.end * 60))
                result.append((s, e, span.openEnd))
            }
        }
        // Merge touching/overlapping intervals (e.g. 24/7 day by day, or 22:00-24:00 + 00:00-04:00).
        let sorted = result.sorted { $0.0 < $1.0 }
        var merged: [(start: Date, end: Date, openEnd: Bool)] = []
        for interval in sorted {
            if let last = merged.last, interval.0 <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.1)
                merged[merged.count - 1].openEnd = last.openEnd || interval.2
            } else {
                merged.append((interval.0, interval.1, interval.2))
            }
        }
        return merged
    }

    /// Open/closed status at a moment in the given time zone.
    func status(at date: Date, timeZone: TimeZone) -> Status {
        if isAlwaysOpen { return .open(closesAt: nil) }
        let intervals = intervals(around: date, timeZone: timeZone)
        if let current = intervals.first(where: { $0.start <= date && date < $0.end }) {
            if current.openEnd { return .open(closesAt: nil) }
            // A span that runs to the end of the evaluated window is effectively continuous.
            if current.end.timeIntervalSince(date) > 6 * 24 * 3600 { return .open(closesAt: nil) }
            return .open(closesAt: current.end)
        }
        let next = intervals.first(where: { $0.start > date })
        return .closed(opensAt: next?.start)
    }

    /// Upcoming open intervals starting within `days` days (for recurring events).
    func upcomingIntervals(from date: Date, timeZone: TimeZone, days: Int) -> [(start: Date, end: Date)] {
        intervals(around: date, timeZone: timeZone, daysBefore: 0, daysAfter: days)
            .filter { $0.end > date }
            .map { ($0.start, $0.end) }
    }

    /// Display rows for Monday…Sunday of the week containing `date`.
    func weeklySchedule(containing date: Date, timeZone: TimeZone) -> [(weekday: Int, text: String)] {
        let calendar = Self.calendar(in: timeZone)
        let today = calendar.startOfDay(for: date)
        let isoToday = Self.isoWeekday(today, calendar: calendar)
        var rows: [(Int, String)] = []
        for iso in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: iso - isoToday, to: today) else { continue }
            let spans = spansStarting(on: day, timeZone: timeZone)
            let text = spans.isEmpty ? "Closed" : spans.map(Self.format).joined(separator: ", ")
            rows.append((iso, text))
        }
        return rows
    }

    static func format(_ span: TimeSpan) -> String {
        func hm(_ minutes: Int) -> String {
            if minutes == 1440 { return "24:00" }
            let m = minutes % 1440
            let h = m / 60, mm = m % 60
            return (h < 10 ? "0" : "") + String(h) + ":" + (mm < 10 ? "0" : "") + String(mm)
        }
        if span.openEnd && span.end == 1440 { return "from " + hm(span.start) }
        if span.start == 0 && span.end == 1440 { return "Open 24 hours" }
        return hm(span.start) + "–" + hm(span.end)
    }

    /// True when the place is open late (any span ending after 23:00).
    var isLateNight: Bool {
        if isAlwaysOpen { return true }
        return rules.contains { rule in
            rule.spans.contains { $0.end >= 23 * 60 || $0.openEnd }
        }
    }

    static func weekdayName(_ iso: Int) -> String {
        ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(0, min(6, iso - 1))]
    }
}
