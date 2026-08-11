import XCTest
@testable import BookmarkX

final class BookmarkTimeGroupTests: XCTestCase {
    func testGroupsByPostRecency() {
        let calendar = Calendar(identifier: .gregorian)
        var components = DateComponents(year: 2026, month: 8, day: 11, hour: 12)
        let now = calendar.date(from: components)!

        XCTAssertEqual(BookmarkTimeGroup.group(for: now, now: now, calendar: calendar), .today)

        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        XCTAssertEqual(BookmarkTimeGroup.group(for: yesterday, now: now, calendar: calendar), .yesterday)

        let sixDays = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(BookmarkTimeGroup.group(for: sixDays, now: now, calendar: calendar), .last7Days)

        let tenDays = calendar.date(byAdding: .day, value: -10, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(BookmarkTimeGroup.group(for: tenDays, now: now, calendar: calendar), .last15Days)

        let twentyDays = calendar.date(byAdding: .day, value: -20, to: calendar.startOfDay(for: now))!
        XCTAssertEqual(BookmarkTimeGroup.group(for: twentyDays, now: now, calendar: calendar), .lastMonth)

        components.month = 2
        let earlierThisYear = calendar.date(from: components)!
        XCTAssertEqual(BookmarkTimeGroup.group(for: earlierThisYear, now: now, calendar: calendar), .thisYear)

        components.year = 2025
        let lastYear = calendar.date(from: components)!
        XCTAssertEqual(BookmarkTimeGroup.group(for: lastYear, now: now, calendar: calendar), .lastYear)

        components.year = 2023
        let older = calendar.date(from: components)!
        XCTAssertEqual(BookmarkTimeGroup.group(for: older, now: now, calendar: calendar), .year(2023))
    }
}
