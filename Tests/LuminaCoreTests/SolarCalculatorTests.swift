import XCTest
@testable import LuminaCore

final class SolarCalculatorTests: XCTestCase {
    private func date(_ text: String, zone: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.timeZone = TimeZone(identifier: zone)!
        return formatter.date(from: text)!
    }

    private func events(lat: Double, lon: Double, day: String, zone: String) throws -> SolarEvents {
        try XCTUnwrap(SolarCalculator.calculateSunriseSunset(latitude: lat, longitude: lon,
                    date: date(day + " 12:00", zone: zone), timeZone: TimeZone(identifier: zone)!))
    }

    func testBerlinSummerSolsticeAgainstReferenceTimes() throws {
        // Rounded civil sunrise/sunset reference values; allow 10 minutes for the
        // approximate NOAA model, atmospheric refraction, and coordinate rounding.
        let result = try events(lat: 52.52, lon: 13.405, day: "2026-06-21", zone: "Europe/Berlin")
        XCTAssertEqual(result.condition, .normal)
        XCTAssertEqual(try XCTUnwrap(result.sunrise).timeIntervalSince(date("2026-06-21 04:43", zone: "Europe/Berlin")), 0, accuracy: 600)
        XCTAssertEqual(try XCTUnwrap(result.sunset).timeIntervalSince(date("2026-06-21 21:33", zone: "Europe/Berlin")), 0, accuracy: 600)
    }

    func testSouthernSummerAndPreviousUTCDay() throws {
        let result = try events(lat: -33.87, lon: 151.21, day: "2026-12-21", zone: "Australia/Sydney")
        XCTAssertEqual(try XCTUnwrap(result.sunrise).timeIntervalSince(date("2026-12-21 05:41", zone: "Australia/Sydney")), 0, accuracy: 600)
        XCTAssertEqual(try XCTUnwrap(result.sunset).timeIntervalSince(date("2026-12-21 20:05", zone: "Australia/Sydney")), 0, accuracy: 600)
    }

    func testEquinoxNearEquatorHasAboutTwelveHoursOfDaylight() throws {
        let result = try events(lat: 0, lon: 0, day: "2026-03-20", zone: "UTC")
        let length = try XCTUnwrap(result.sunset).timeIntervalSince(XCTUnwrap(result.sunrise))
        XCTAssertEqual(length, 12 * 3600, accuracy: 15 * 60)
    }

    func testPolarDayAndNightNeverInventSixAMSunrise() throws {
        for latitude in [69.65, 90] {
            let summer = try events(lat: latitude, lon: 18.96, day: "2026-06-21", zone: "Europe/Oslo")
            XCTAssertEqual(summer.condition, .polarDay)
            XCTAssertNil(summer.sunrise)
            XCTAssertNil(summer.sunset)
            XCTAssertFalse(summer.isNight(at: Date()))
            let winter = try events(lat: latitude, lon: 18.96, day: "2026-12-21", zone: "Europe/Oslo")
            XCTAssertEqual(winter.condition, .polarNight)
            XCTAssertTrue(winter.isNight(at: Date()))
        }
    }

    func testSouthernPoleHasOppositeSeasons() throws {
        XCTAssertEqual(try events(lat: -89, lon: 0, day: "2026-06-21", zone: "UTC").condition, .polarNight)
        XCTAssertEqual(try events(lat: -89, lon: 0, day: "2026-12-21", zone: "UTC").condition, .polarDay)
    }

    func testSunriseIsInclusiveAndSunsetIsExclusive() throws {
        let result = try events(lat: 52.5, lon: 13.4, day: "2026-10-23", zone: "Europe/Berlin")
        let rise = try XCTUnwrap(result.sunrise)
        let set = try XCTUnwrap(result.sunset)
        XCTAssertTrue(result.isNight(at: rise.addingTimeInterval(-1)))
        XCTAssertFalse(result.isNight(at: rise))
        XCTAssertFalse(result.isNight(at: set.addingTimeInterval(-1)))
        XCTAssertTrue(result.isNight(at: set))
    }

    func testRequestedTimezoneDeterminesCalendarDay() throws {
        // The same instant is still December 31 in Honolulu and January 1 in Tokyo.
        let instant = date("2026-01-01 01:00", zone: "Asia/Tokyo")
        let result = try XCTUnwrap(SolarCalculator.calculateSunriseSunset(latitude: 21.3, longitude: -157.8,
                                   date: instant, timeZone: TimeZone(identifier: "Pacific/Honolulu")!))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Pacific/Honolulu")!
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result.sunrise), inSameDayAs: instant))
    }

    func testDateLineAndExtremeTimezoneKeepSolarNoonOnRequestedDay() throws {
        let zone = "Pacific/Kiritimati"
        let result = try events(lat: 1.87, lon: -157.4, day: "2026-06-21", zone: zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        let midday = date("2026-06-21 12:00", zone: zone)
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result.sunrise), inSameDayAs: midday))
        XCTAssertTrue(calendar.isDate(try XCTUnwrap(result.sunset), inSameDayAs: midday))
        XCTAssertFalse(result.isNight(at: midday))
        XCTAssertTrue(result.isNight(at: date("2026-06-21 00:00", zone: zone)))
    }

    func testDaylightThatCrossesLocalMidnight() throws {
        // Manually entered coordinates may be far from the Mac's own timezone.
        let result = try events(lat: 35.7, lon: 139.7, day: "2026-06-21", zone: "America/Los_Angeles")
        XCTAssertFalse(result.isNight(at: date("2026-06-21 00:00", zone: "America/Los_Angeles")))
        XCTAssertTrue(result.isNight(at: date("2026-06-21 08:00", zone: "America/Los_Angeles")))
    }

    func testDSTTransitionsAndLeapDayProduceFiniteOrderedEvents() throws {
        for day in ["2026-03-29", "2026-10-25", "2024-02-29"] {
            let result = try events(lat: 52.5, lon: 13.4, day: day, zone: "Europe/Berlin")
            XCTAssertLessThan(try XCTUnwrap(result.sunrise), try XCTUnwrap(result.sunset))
            XCTAssertFalse(result.isNight(at: date(day + " 12:00", zone: "Europe/Berlin")))
        }
    }

    func testInvalidCoordinatesReturnNoEvents() {
        for (lat, lon) in [(Double.nan, 0.0), (0, .infinity), (91, 0), (0, -181)] {
            XCTAssertNil(SolarCalculator.calculateSunriseSunset(latitude: lat, longitude: lon))
        }
    }
}
