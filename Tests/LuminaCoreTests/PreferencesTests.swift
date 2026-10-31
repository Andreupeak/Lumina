import XCTest
@testable import LuminaCore

final class PreferencesTests: XCTestCase {
    @MainActor
    func testLegacyStartupBrightnessIsUsedOnlyWithoutAManualSetting() async throws {
        withDefaults { defaults in
            defaults.set(0.7, forKey: "defaultStartupBrightness")
            XCTAssertEqual(Preferences(defaults: defaults).manualBrightness, 0.7)
            defaults.set(0.2, forKey: "manualBrightness")
            XCTAssertEqual(Preferences(defaults: defaults).manualBrightness, 0.2)
        }
    }
    @MainActor
    private func withDefaults(_ body: (UserDefaults) throws -> Void) rethrows {
        let suite = "Lumina.Tests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func slot(hour: Int, id: UUID = UUID()) -> BrightnessPeriod {
        BrightnessPeriod(id: id, name: "Slot", startHour: hour, startMinute: 0,
                         endHour: hour + 1, endMinute: 0, brightness: 0.5)
    }

    @MainActor
    func testFreshInstallDoesNotAssumeACaliforniaLocation() async throws {
        withDefaults { defaults in
            let prefs = Preferences(defaults: defaults)
            XCTAssertFalse(prefs.hasSavedLocation)
            XCTAssertEqual(prefs.solarLocationSource, .manual)
            XCTAssertFalse(prefs.hasCompletedOnboarding)
        }
    }

    @MainActor
    func testLegacyPreferencesMigrateWithoutLosingSolarSetup() async throws {
        withDefaults { defaults in
            defaults.set(true, forKey: "isOverridden")
            defaults.set(0.7, forKey: "sunsetBrightness")
            defaults.set(true, forKey: "sunsetUseAmbient")
            defaults.set(true, forKey: "manualUseAmbient")
            let prefs = Preferences(defaults: defaults)
            XCTAssertTrue(prefs.overrideEnabled)
            XCTAssertEqual(prefs.solarNightBrightness, 0.7)
            XCTAssertTrue(prefs.solarAutoBrightness)
            XCTAssertTrue(prefs.manualAutoBrightness)
            XCTAssertTrue(prefs.hasCompletedOnboarding)
            XCTAssertEqual(prefs.automationTab, 0)
        }
    }

    @MainActor
    func testMigrationDoesNotOverwriteNewPreferences() async throws {
        withDefaults { defaults in
            defaults.set(true, forKey: "isOverridden")
            defaults.set(false, forKey: "overrideEnabled")
            defaults.set(0.2, forKey: "solarNightBrightness")
            defaults.set(0.9, forKey: "sunsetBrightness")
            let prefs = Preferences(defaults: defaults)
            XCTAssertFalse(prefs.overrideEnabled)
            XCTAssertEqual(prefs.solarNightBrightness, 0.2)
        }
    }

    @MainActor
    func testCorruptSavedScalarsAreBounded() async throws {
        withDefaults { defaults in
            defaults.set(99.0, forKey: "manualBrightness")
            defaults.set(-2.0, forKey: "solarNightBrightness")
            defaults.set(73, forKey: "automationTab")
            defaults.set(Int.max, forKey: "inactivityTimeoutMinutes")
            defaults.set(-1, forKey: "inactivityTimeoutSeconds")
            let prefs = Preferences(defaults: defaults)
            XCTAssertEqual(prefs.manualBrightness, 1)
            XCTAssertEqual(prefs.solarNightBrightness, 0)
            XCTAssertEqual(prefs.automationTab, 0)
            XCTAssertEqual(prefs.inactivityTimeoutMinutes, 59)
            XCTAssertEqual(prefs.inactivityTimeoutSeconds, 0)
        }
    }

    @MainActor
    func testLocationPrecisionIsReducedForExistingAndNewSettings() async throws {
        withDefaults { defaults in
            defaults.set(52.520008, forKey: "latitude")
            defaults.set(13.404954, forKey: "longitude")
            let prefs = Preferences(defaults: defaults)
            XCTAssertTrue(prefs.hasSavedLocation)
            XCTAssertEqual(prefs.latitude, 52.5)
            XCTAssertEqual(defaults.double(forKey: "latitude"), 52.5)
            XCTAssertTrue(prefs.setCoordinates(latitude: -33.8688, longitude: 151.2093))
            XCTAssertEqual(prefs.latitude, -33.9)
            XCTAssertEqual(prefs.longitude, 151.2)
            let reloaded = Preferences(defaults: defaults)
            XCTAssertTrue(reloaded.hasSavedLocation)
            XCTAssertEqual(reloaded.latitude, -33.9)
        }
    }

    @MainActor
    func testInvalidLocationIsRejectedWithoutOverwritingSavedLocation() async throws {
        withDefaults { defaults in
            let prefs = Preferences(defaults: defaults)
            XCTAssertTrue(prefs.setCoordinates(latitude: 0, longitude: 0))
            XCTAssertTrue(prefs.hasSavedLocation)
            XCTAssertFalse(prefs.setCoordinates(latitude: .nan, longitude: 0))
            XCTAssertEqual(prefs.latitude, 0)
            XCTAssertTrue(prefs.hasSavedLocation)
        }
    }

    @MainActor
    func testForgetLocationRemovesCoordinatesAndLegacyModeKey() async throws {
        withDefaults { defaults in
            defaults.set(true, forKey: "useCoreLocation")
            let prefs = Preferences(defaults: defaults)
            prefs.setCoordinates(latitude: 52.5, longitude: 13.4)
            prefs.clearLocation()
            XCTAssertFalse(prefs.hasSavedLocation)
            XCTAssertEqual(prefs.solarLocationSource, .manual)
            for key in ["latitude", "longitude", "useCoreLocation"] { XCTAssertNil(defaults.object(forKey: key)) }
            XCTAssertFalse(Preferences(defaults: defaults).hasSavedLocation)
        }
    }

    @MainActor
    func testInvalidStoredLocationIsRemoved() async throws {
        withDefaults { defaults in
            defaults.set(900.0, forKey: "latitude")
            defaults.set(13.0, forKey: "longitude")
            let prefs = Preferences(defaults: defaults)
            XCTAssertFalse(prefs.hasSavedLocation)
            XCTAssertNil(defaults.object(forKey: "latitude"))
            XCTAssertNil(defaults.object(forKey: "longitude"))
        }
    }

    @MainActor
    func testAddingSlotsEnforcesLimitOverlapAndIdentity() async throws {
        withDefaults { defaults in
            let prefs = Preferences(defaults: defaults)
            let first = slot(hour: 9)
            XCTAssertTrue(prefs.addPeriod(first))
            XCTAssertFalse(prefs.addPeriod(first))
            XCTAssertFalse(prefs.addPeriod(slot(hour: 9)))
            XCTAssertTrue(prefs.addPeriod(slot(hour: 12)))
            XCTAssertTrue(prefs.addPeriod(slot(hour: 15)))
            XCTAssertFalse(prefs.addPeriod(slot(hour: 18)))
            XCTAssertEqual(prefs.customPeriods.count, 3)
        }
    }

    @MainActor
    func testEditingAllowsOwnRangeButRejectsOverlapAndEmptyRange() async throws {
        withDefaults { defaults in
            let prefs = Preferences(defaults: defaults)
            var first = slot(hour: 9)
            prefs.addPeriod(first)
            prefs.addPeriod(slot(hour: 12))
            first.name = "Renamed"
            XCTAssertTrue(prefs.updatePeriod(first))
            first.endHour = 13
            XCTAssertFalse(prefs.updatePeriod(first))
            first.endHour = first.startHour
            XCTAssertFalse(prefs.updatePeriod(first))
            XCTAssertEqual(prefs.customPeriods.first?.name, "Renamed")
        }
    }

    @MainActor
    func testSlotPersistenceAndDeletion() async throws {
        withDefaults { defaults in
            let prefs = Preferences(defaults: defaults)
            let first = slot(hour: 9)
            prefs.addPeriod(slot(hour: 15))
            prefs.addPeriod(first)
            XCTAssertEqual(Preferences(defaults: defaults).customPeriods.map(\.startHour), [9, 15])
            prefs.removePeriod(id: first.id)
            XCTAssertEqual(Preferences(defaults: defaults).customPeriods.map(\.startHour), [15])
        }
    }

    @MainActor
    func testStoredSlotsDiscardInvalidDuplicateOverlappingAndExcessEntries() async throws {
        try withDefaults { defaults in
            var invalid = slot(hour: 3)
            invalid.startHour = .max
            let first = slot(hour: 9)
            let slots = [invalid, first, first, slot(hour: 9), slot(hour: 12), slot(hour: 15), slot(hour: 18)]
            defaults.set(try JSONEncoder().encode(slots), forKey: "customPeriods_v3")
            XCTAssertEqual(Preferences(defaults: defaults).customPeriods.map(\.startHour), [9, 12, 15])
        }
    }

    @MainActor
    func testMalformedStoredJSONDoesNotCrash() async throws {
        withDefaults { defaults in
            defaults.set(Data("not json".utf8), forKey: "customPeriods_v3")
            XCTAssertTrue(Preferences(defaults: defaults).customPeriods.isEmpty)
        }
    }
}
