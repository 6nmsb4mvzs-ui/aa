import Foundation

/// User-facing formatting helpers.
enum Format {
    static func distance(_ meters: Double, metric: Bool) -> String {
        if metric {
            if meters < 950 { return "\(Int((meters / 10).rounded()) * 10) m" }
            return String(format: meters < 9_950 ? "%.1f km" : "%.0f km", meters / 1000)
        }
        let miles = meters / 1609.344
        if miles < 0.19 { return "\(Int((meters * 3.28084 / 50).rounded()) * 50) ft" }
        return String(format: miles < 9.95 ? "%.1f mi" : "%.0f mi", miles)
    }

    static func radius(_ meters: Double, metric: Bool) -> String {
        if metric {
            return meters < 1000 ? "\(Int(meters.rounded())) m" : String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.1f mi", meters / 1609.344)
    }

    static func time(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func eventDate(_ event: DiscoveryEvent, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(event.isAllDay ? "EEE d MMM" : "EEE d MMM HH:mm")
        var text = formatter.string(from: event.start)
        if let end = event.end {
            let calendar = Calendar.current
            var tzCalendar = calendar
            tzCalendar.timeZone = timeZone
            if tzCalendar.isDate(end, inSameDayAs: event.start) {
                if !event.isAllDay { text += "–" + time(end, timeZone: timeZone) }
            } else {
                let endFormatter = DateFormatter()
                endFormatter.timeZone = timeZone
                endFormatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
                text += " – " + endFormatter.string(from: end)
            }
        }
        return text
    }

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func bytes(_ count: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// Short open/closed text for a place, or nil when hours are unknown.
    static func openStatus(_ place: Place, timeZone: TimeZone, now: Date = Date()) -> (text: String, isOpen: Bool)? {
        guard let raw = place.openingHoursRaw, let hours = OpeningHours.parse(raw) else { return nil }
        switch hours.status(at: now, timeZone: timeZone) {
        case .open(let closes):
            if let closes { return ("Open · until \(time(closes, timeZone: timeZone))", true) }
            return ("Open now", true)
        case .closed(let opens):
            guard let opens else { return ("Closed", false) }
            var calendar = Calendar.current
            calendar.timeZone = timeZone
            if calendar.isDate(opens, inSameDayAs: now) { return ("Closed · opens \(time(opens, timeZone: timeZone))", false) }
            let formatter = DateFormatter()
            formatter.timeZone = timeZone
            formatter.setLocalizedDateFormatFromTemplate("EEE HH:mm")
            return ("Closed · opens \(formatter.string(from: opens))", false)
        case .unknown:
            return nil
        }
    }
}
