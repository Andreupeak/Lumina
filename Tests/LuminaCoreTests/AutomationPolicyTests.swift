import XCTest
@testable import LuminaCore

final class AutomationPolicyTests: XCTestCase {
    private var nightSlot: BrightnessPeriod {
        BrightnessPeriod(name: "Evening", startHour: 22, startMinute: 0, endHour: 6, endMinute: 0,
                         brightness: 0.6, timeoutMinutes: 1, timeoutSeconds: 5)
    }

    func testManualModeUsesManualSettingsRegardlessOfSolarState() {
        var settings = AutomationSettings()
        settings.manualBrightness = 0.42
        settings.manualAmbient = true
        let decision = AutomationPolicy.decision(settings: settings, minute: 60, isNight: nil)
        XCTAssertEqual(decision.brightness, 0.42)
        XCTAssertTrue(decision.ambient)
        XCTAssertEqual(decision.status, "System • Auto")
    }

    func testSolarModeTurnsOffDuringDayAndUsesNightSettings() {
        var settings = AutomationSettings(periodic: true)
        settings.nightBrightness = 0.72
        settings.nightAmbient = true
        let day = AutomationPolicy.decision(settings: settings, minute: 720, isNight: false)
        XCTAssertEqual(day.brightness, 0)
        XCTAssertFalse(day.ambient)
        let night = AutomationPolicy.decision(settings: settings, minute: 60, isNight: true)
        XCTAssertEqual(night.brightness, 0.72)
        XCTAssertTrue(night.ambient)
        XCTAssertTrue(night.night)
    }

    func testSolarModeWithoutLocationDoesNotInventASunrise() {
        let decision = AutomationPolicy.decision(settings: AutomationSettings(periodic: true), minute: 60, isNight: nil)
        XCTAssertEqual(decision.brightness, 0)
        XCTAssertEqual(decision.status, "Choose a location")
    }

    func testTimeSlotsTurnOffOutsideSchedule() {
        var settings = AutomationSettings(periodic: true, tab: 1)
        settings.periods = [nightSlot]
        XCTAssertEqual(AutomationPolicy.decision(settings: settings, minute: 0, isNight: true).brightness, 0.6)
        let outside = AutomationPolicy.decision(settings: settings, minute: 360, isNight: false)
        XCTAssertEqual(outside.brightness, 0)
        XCTAssertEqual(outside.status, "Off • Outside schedule")
    }

    func testPerSlotTimeoutTakesPriorityOverGlobal() {
        var settings = AutomationSettings(periodic: true, tab: 1)
        settings.periods = [nightSlot]
        settings.inactivityEnabled = true
        settings.inactivitySeconds = 30
        XCTAssertEqual(AutomationPolicy.idleTimeout(settings: settings, minute: 0), 65)
        XCTAssertEqual(AutomationPolicy.idleTimeout(settings: settings, minute: 720), 30)
    }

    func testZeroSlotTimeoutInheritsGlobalSetting() {
        var settings = AutomationSettings(periodic: true, tab: 1)
        var slot = nightSlot
        slot.timeoutMinutes = 0
        slot.timeoutSeconds = 0
        settings.periods = [slot]
        settings.inactivityEnabled = true
        XCTAssertEqual(AutomationPolicy.idleTimeout(settings: settings, minute: 0), 30)
        settings.inactivityEnabled = false
        XCTAssertNil(AutomationPolicy.idleTimeout(settings: settings, minute: 0))
    }

    func testManualModeIgnoresSlotTimeout() {
        var settings = AutomationSettings()
        settings.periods = [nightSlot]
        XCTAssertNil(AutomationPolicy.idleTimeout(settings: settings, minute: 0))
    }

    func testZeroAndInvalidGlobalDurationsDisableTimeout() {
        for (minutes, seconds) in [(0, 0), (-1, 30), (60, 0), (0, 60), (Int.max, Int.max)] {
            XCTAssertNil(AutomationPolicy.duration(minutes: minutes, seconds: seconds))
        }
        XCTAssertEqual(AutomationPolicy.duration(minutes: 59, seconds: 59), 3599)
    }

    func testBrightnessClampsAndRejectsNonfiniteValues() {
        XCTAssertEqual(AutomationPolicy.clampBrightness(-1), 0)
        XCTAssertEqual(AutomationPolicy.clampBrightness(2), 1)
        XCTAssertEqual(AutomationPolicy.clampBrightness(.nan), 0)
        XCTAssertEqual(AutomationPolicy.clampBrightness(.infinity, fallback: 0.5), 0.5)
    }

    func testInactivityRestoresOnlyAfterActualInput() {
        var state = InactivityState()
        state.update(idleSeconds: 31, timeout: 30, withinGracePeriod: false)
        XCTAssertTrue(state.isOff)
        // A slot ends or the global setting is disabled while the user is away.
        state.update(idleSeconds: 90, timeout: nil, withinGracePeriod: false)
        XCTAssertTrue(state.isOff)
        state.update(idleSeconds: 0.2, timeout: nil, withinGracePeriod: false)
        XCTAssertFalse(state.isOff)
    }

    func testStartupGraceDoesNotDimImmediately() {
        var state = InactivityState()
        state.update(idleSeconds: 120, timeout: 30, withinGracePeriod: true)
        XCTAssertFalse(state.isOff)
        state.update(idleSeconds: 120, timeout: 30, withinGracePeriod: false)
        XCTAssertTrue(state.isOff)
    }

    func testInvalidIdleCountersCannotWakeTheKeyboard() {
        var state = InactivityState()
        state.update(idleSeconds: 31, timeout: 30, withinGracePeriod: false)
        for idle in [Double.nan, .infinity, -1] {
            state.update(idleSeconds: idle, timeout: nil, withinGracePeriod: false)
            XCTAssertTrue(state.isOff)
        }
    }
}
