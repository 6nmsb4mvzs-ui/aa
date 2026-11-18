import XCTest
#if SWIFT_PACKAGE
@testable import SidestreetCore
#else
@testable import Sidestreet
#endif

final class OpeningHoursTests: XCTestCase {
    let berlin = TimeZone(identifier: "Europe/Berlin")!

    func status(_ rule: String, at date: String) -> OpeningHours.Status? {
        OpeningHours.parse(rule)?.status(at: Fixture.date(date), timeZone: berlin)
    }

    func isOpen(_ rule: String, at date: String) -> Bool? {
        guard let s = status(rule, at: date) else { return nil }
        if case .open = s { return true }
        return false
    }

    // 2026-11-16 is a Monday.
    func testSimpleWeekdayRange() {
        let rule = "Mo-Fr 10:00-18:00; Sa 10:00-14:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 12:00"), true)   // Wed
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 18:00"), false)  // closing time is exclusive
        XCTAssertEqual(isOpen(rule, at: "2026-11-21 13:59"), true)   // Sat
        XCTAssertEqual(isOpen(rule, at: "2026-11-22 12:00"), false)  // Sun
    }

    func testClosingTimeAndNextOpening() {
        guard case .open(let closes)? = status("Mo-Fr 10:00-18:00", at: "2026-11-18 12:00") else {
            return XCTFail("expected open")
        }
        XCTAssertEqual(closes, Fixture.date("2026-11-18 18:00"))
        guard case .closed(let opens)? = status("Mo-Fr 10:00-18:00", at: "2026-11-20 19:00") else {
            return XCTFail("expected closed")
        }
        XCTAssertEqual(opens, Fixture.date("2026-11-23 10:00"), "Friday evening → opens Monday")
    }

    func testSpanPastMidnight() {
        let rule = "Fr,Sa 22:00-05:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-21 02:00"), true, "Saturday 02:00 belongs to Friday's span")
        XCTAssertEqual(isOpen(rule, at: "2026-11-23 02:00"), false)
        XCTAssertTrue(OpeningHours.parse(rule)!.isLateNight)
    }

    func testAlwaysOpen() {
        XCTAssertEqual(isOpen("24/7", at: "2026-11-18 03:00"), true)
        XCTAssertTrue(OpeningHours.parse("24/7")!.isAlwaysOpen)
    }

    func testOffOverridesEarlierRule() {
        let rule = "Mo-Su 08:00-20:00; We off"
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 12:00"), false)
        XCTAssertEqual(isOpen(rule, at: "2026-11-19 12:00"), true)
    }

    func testMultipleSpansAndAdditionalRule() {
        let rule = "Mo-Fr 08:00-12:00,13:00-17:30, Sa 09:00-12:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 12:30"), false)
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 13:30"), true)
        XCTAssertEqual(isOpen(rule, at: "2026-11-21 10:00"), true)
    }

    func testWeekdayList() {
        let rule = "Tu,Th 10:00-12:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-17 11:00"), true)
        XCTAssertEqual(isOpen(rule, at: "2026-11-18 11:00"), false)
    }

    func testNthWeekdayOfMonth() {
        // First Sunday of December 2026 is Dec 6; last Saturday of November 2026 is Nov 28.
        XCTAssertEqual(isOpen("Su[1] 08:00-14:00", at: "2026-12-06 10:00"), true)
        XCTAssertEqual(isOpen("Su[1] 08:00-14:00", at: "2026-12-13 10:00"), false)
        XCTAssertEqual(isOpen("Sa[-1] 09:00-15:00", at: "2026-11-28 10:00"), true)
        XCTAssertEqual(isOpen("Sa[-1] 09:00-15:00", at: "2026-11-21 10:00"), false)
    }

    func testMonthRanges() {
        let rule = "Apr-Oct: Sa 08:00-16:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-21 10:00"), false)
        XCTAssertEqual(isOpen(rule, at: "2026-10-31 10:00"), true)
    }

    func testSpecificDate() {
        let rule = "2026 Nov 21 09:00-15:00"
        XCTAssertEqual(isOpen(rule, at: "2026-11-21 10:00"), true)
        XCTAssertEqual(isOpen(rule, at: "2026-11-28 10:00"), false)
    }

    func testHolidayRulesAreSkippedAndFlagged() {
        let hours = OpeningHours.parse("Mo-Sa 10:00-19:00; PH off")
        XCTAssertNotNil(hours)
        XCTAssertTrue(hours!.hasHolidayRules)
    }

    func testOpenEnd() {
        guard case .open(let closes)? = status("Fr 22:00+", at: "2026-11-20 23:00") else { return XCTFail() }
        XCTAssertNil(closes, "open-ended spans have no known closing time")
    }

    func testCommentsAreIgnored() {
        XCTAssertEqual(isOpen("Mo-Fr 10:00-18:00 \"by appointment on weekends\"", at: "2026-11-18 12:00"), true)
    }

    func testUnsupportedSyntaxReturnsNilInsteadOfGuessing() {
        XCTAssertNil(OpeningHours.parse("sunrise-sunset"))
        XCTAssertNil(OpeningHours.parse("week 1-53/2 Fr 09:00-12:00"))
        XCTAssertNil(OpeningHours.parse("Mo-Fr 08:00-18:00 || \"on appointment\""))
        XCTAssertNil(OpeningHours.parse("by appointment"))
        XCTAssertNil(OpeningHours.parse("Mo-Fr"))
        XCTAssertNil(OpeningHours.parse(""))
        XCTAssertNil(OpeningHours.parse("Mo-Fr 25:99-30:00"))
    }

    func testWeeklySchedule() {
        let hours = OpeningHours.parse("Mo-Fr 09:00-17:00; Sa 10:00-14:00")!
        let rows = hours.weeklySchedule(containing: Fixture.date("2026-11-18 12:00"), timeZone: berlin)
        XCTAssertEqual(rows.count, 7)
        XCTAssertEqual(rows[0].text, "09:00–17:00")
        XCTAssertEqual(rows[5].text, "10:00–14:00")
        XCTAssertEqual(rows[6].text, "Closed")
    }

    func testTimeZoneMatters() {
        // 12:00 UTC is 21:00 in Tokyo.
        let hours = OpeningHours.parse("Mo-Su 10:00-20:00")!
        let noonUTC = Fixture.date("2026-11-18 12:00", timeZone: "UTC")
        guard case .closed = hours.status(at: noonUTC, timeZone: TimeZone(identifier: "Asia/Tokyo")!) else {
            return XCTFail("should be closed in Tokyo")
        }
        guard case .open = hours.status(at: noonUTC, timeZone: berlin) else { return XCTFail("should be open in Berlin") }
    }

    func testUpcomingIntervalsForRecurringMarket() {
        let hours = OpeningHours.parse("Sa 08:00-15:00")!
        let upcoming = hours.upcomingIntervals(from: Fixture.date("2026-11-18 12:00"), timeZone: berlin, days: 14)
        XCTAssertEqual(upcoming.first?.start, Fixture.date("2026-11-21 08:00"))
        XCTAssertEqual(upcoming.count, 2)
    }
}
