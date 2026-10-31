import XCTest
@testable import LuminaCore

final class BrightnessPeriodTests: XCTestCase {
    private func period(_ start: Int, _ end: Int, id: UUID = UUID()) -> BrightnessPeriod {
        BrightnessPeriod(id: id, name: "Evening", startHour: start / 60, startMinute: start % 60,
                         endHour: end / 60, endMinute: end % 60, brightness: 0.5)
    }

    func testNormalSlotIncludesStartAndExcludesEnd() {
        let slot = period(9 * 60, 11 * 60)
        XCTAssertFalse(slot.contains(minuteOfDay: 539))
        XCTAssertTrue(slot.contains(minuteOfDay: 540))
        XCTAssertTrue(slot.contains(minuteOfDay: 659))
        XCTAssertFalse(slot.contains(minuteOfDay: 660))
        XCTAssertFalse(slot.contains(minuteOfDay: -1))
        XCTAssertFalse(slot.contains(minuteOfDay: 1440))
    }

    func testOvernightSlotIncludesBothSidesOfMidnight() {
        let slot = period(22 * 60, 6 * 60)
        for minute in [1320, 1439, 0, 359] { XCTAssertTrue(slot.contains(minuteOfDay: minute)) }
        for minute in [360, 720, 1319] { XCTAssertFalse(slot.contains(minuteOfDay: minute)) }
    }

    func testAdjacentSlotsDoNotOverlap() {
        XCTAssertFalse(period(540, 660).overlaps(period(660, 720)))
        XCTAssertFalse(period(1320, 360).overlaps(period(360, 1320)))
    }

    func testOverlapsAcrossMidnight() {
        let night = period(1320, 360)
        XCTAssertTrue(night.overlaps(period(300, 420)))
        XCTAssertTrue(night.overlaps(period(1380, 60)))
        XCTAssertTrue(night.overlaps(period(1260, 1380)))
        XCTAssertFalse(night.overlaps(period(720, 780)))
    }

    func testEmptyRangeIsInvalid() {
        let slot = period(600, 600)
        XCTAssertFalse(slot.isValid)
        XCTAssertTrue(slot.intervals.isEmpty)
    }

    func testInvalidClockFieldsCannotOverflow() {
        var slot = period(540, 660)
        slot.startHour = .max
        XCTAssertFalse(slot.isValid)
        XCTAssertEqual(slot.startMinutes, -1)
        XCTAssertFalse(slot.contains(minuteOfDay: 600))
        XCTAssertFalse(slot.overlaps(period(540, 660)))
    }

    func testRejectsUnsafeBrightnessAndTimeouts() {
        for value in [Double.nan, .infinity, -.infinity, -0.1, 1.1] {
            var slot = period(540, 660)
            slot.brightness = value
            XCTAssertFalse(slot.isValid)
        }
        var slot = period(540, 660)
        slot.timeoutMinutes = .max
        XCTAssertFalse(slot.isValid)
        slot.timeoutMinutes = 0
        slot.timeoutSeconds = 60
        XCTAssertFalse(slot.isValid)
    }

    func testRejectsBlankAndUnboundedNames() {
        var slot = period(540, 660)
        slot.name = " \n "
        XCTAssertFalse(slot.isValid)
        slot.name = String(repeating: "a", count: 81)
        XCTAssertFalse(slot.isValid)
    }

    func testLegacyPeriodDecodesWithSafeDefaults() throws {
        let data = Data(#"{"name":"Legacy","startHour":20,"startMinute":0,"endHour":23,"endMinute":0,"brightness":0.4}"#.utf8)
        let slot = try JSONDecoder().decode(BrightnessPeriod.self, from: data)
        XCTAssertTrue(slot.isValid)
        XCTAssertFalse(slot.useAmbient)
        XCTAssertEqual(slot.timeoutMinutes, 0)
        XCTAssertEqual(slot.timeoutSeconds, 0)
        XCTAssertEqual(try JSONDecoder().decode(BrightnessPeriod.self, from: JSONEncoder().encode(slot)), slot)
    }
}
