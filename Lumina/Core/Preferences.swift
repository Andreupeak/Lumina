import Foundation
import Combine

@MainActor
final class Preferences: ObservableObject {
    static let shared: Preferences = {
        if AppRuntime.isUITesting {
            // Each UI test launch gets a fresh domain; never read the user's settings.
            let defaults = UserDefaults(suiteName: "Lumina.UITesting")!
            defaults.removePersistentDomain(forName: "Lumina.UITesting")
            return Preferences(defaults: defaults)
        }
        return Preferences()
    }()

    private let defaults: UserDefaults
    private let periodsKey = "customPeriods_v3"
    private let solarLocationSourceKey = "solarLocationSource"

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published var overrideEnabled: Bool {
        didSet { defaults.set(overrideEnabled, forKey: "overrideEnabled") }
    }

    @Published var manualBrightness: Double {
        didSet { defaults.set(manualBrightness, forKey: "manualBrightness") }
    }

    @Published var manualAutoBrightness: Bool {
        didSet { defaults.set(manualAutoBrightness, forKey: "manualAutoBrightness") }
    }

    @Published var automationTab: Int {
        didSet { defaults.set(automationTab, forKey: "automationTab") }
    }

    @Published var solarNightBrightness: Double {
        didSet { defaults.set(solarNightBrightness, forKey: "solarNightBrightness") }
    }

    @Published var solarAutoBrightness: Bool {
        didSet { defaults.set(solarAutoBrightness, forKey: "solarAutoBrightness") }
    }

    @Published private(set) var latitude: Double {
        didSet { defaults.set(latitude, forKey: "latitude") }
    }

    @Published private(set) var longitude: Double {
        didSet { defaults.set(longitude, forKey: "longitude") }
    }

    @Published private(set) var hasSavedLocation: Bool {
        didSet { defaults.set(hasSavedLocation, forKey: "hasSavedLocation") }
    }

    @Published var solarLocationSourceRaw: String {
        didSet { defaults.set(solarLocationSourceRaw, forKey: solarLocationSourceKey) }
    }

    @Published var inactivityTimeoutEnabled: Bool {
        didSet { defaults.set(inactivityTimeoutEnabled, forKey: "inactivityTimeoutEnabled") }
    }
    @Published var inactivityTimeoutMinutes: Int {
        didSet { defaults.set(inactivityTimeoutMinutes, forKey: "inactivityTimeoutMinutes") }
    }
    @Published var inactivityTimeoutSeconds: Int {
        didSet { defaults.set(inactivityTimeoutSeconds, forKey: "inactivityTimeoutSeconds") }
    }

    @Published private(set) var customPeriods: [BrightnessPeriod] {
        didSet {
            if let data = try? JSONEncoder().encode(customPeriods) {
                defaults.set(data, forKey: periodsKey)
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // One-time upgrade path. Earlier Lumina builds stored settings under different
        // UserDefaults keys (`isOverridden`, `sunsetBrightness`, `sunsetUseAmbient`,
        // `manualUseAmbient`). When the keys were renamed there was no migration, so
        // upgraders silently lost their Auto/Solar setup and landed in System Control
        // with the backlight stuck on. Inline here (before stored properties are set)
        // because Swift forbids calling instance methods on `self` this early in init.
        if defaults.object(forKey: "overrideEnabled") == nil,
           defaults.object(forKey: "isOverridden") != nil {
            if let v = defaults.object(forKey: "isOverridden") as? Bool {
                defaults.set(v, forKey: "overrideEnabled")
            }
            if let v = defaults.object(forKey: "sunsetBrightness") as? Double {
                defaults.set(v, forKey: "solarNightBrightness")
            }
            if let v = defaults.object(forKey: "sunsetUseAmbient") as? Bool {
                defaults.set(v, forKey: "solarAutoBrightness")
            }
            if let v = defaults.object(forKey: "manualUseAmbient") as? Bool {
                defaults.set(v, forKey: "manualAutoBrightness")
            }
            // The legacy app only had the solar ("sunset") automation, so land upgraders
            // on the Sun Cycle tab where their restored night brightness actually applies.
            defaults.set(0, forKey: "automationTab")
            defaults.set(true, forKey: "solarEnabled")
            // They already configured Lumina before — don't force them through onboarding again.
            defaults.set(true, forKey: "hasCompletedOnboarding")
        }

        hasCompletedOnboarding = defaults.object(forKey: "hasCompletedOnboarding") as? Bool ?? false
        overrideEnabled = defaults.object(forKey: "overrideEnabled") as? Bool ?? false
        manualBrightness = AutomationPolicy.clampBrightness(
            defaults.object(forKey: "manualBrightness") as? Double
                ?? defaults.object(forKey: "defaultStartupBrightness") as? Double ?? 0.5,
            fallback: 0.5)
        manualAutoBrightness = defaults.object(forKey: "manualAutoBrightness") as? Bool ?? false
        automationTab = defaults.integer(forKey: "automationTab") == 1 ? 1 : 0
        solarNightBrightness = AutomationPolicy.clampBrightness(defaults.object(forKey: "solarNightBrightness") as? Double ?? 0.5, fallback: 0.5)
        solarAutoBrightness = defaults.object(forKey: "solarAutoBrightness") as? Bool ?? false
        let coordinate: LocationCoordinate?
        if let lat = defaults.object(forKey: "latitude") as? Double,
           let lon = defaults.object(forKey: "longitude") as? Double {
            coordinate = LocationCoordinate(latitude: lat, longitude: lon)?.roundedForStorage
        } else {
            coordinate = nil
        }
        latitude = coordinate?.latitude ?? 0
        longitude = coordinate?.longitude ?? 0
        hasSavedLocation = coordinate != nil && (defaults.object(forKey: "hasSavedLocation") as? Bool ?? true)
        let savedUseCoreLocation = defaults.bool(forKey: "useCoreLocation")
        let source = defaults.string(forKey: solarLocationSourceKey)
            .flatMap(SolarLocationSource.init(rawValue:))
            ?? (savedUseCoreLocation ? .precise : .manual)
        solarLocationSourceRaw = source.rawValue

        inactivityTimeoutEnabled = defaults.object(forKey: "inactivityTimeoutEnabled") as? Bool ?? false
        inactivityTimeoutMinutes = min(max(defaults.integer(forKey: "inactivityTimeoutMinutes"), 0), 59)
        inactivityTimeoutSeconds = min(max(defaults.object(forKey: "inactivityTimeoutSeconds") as? Int ?? 30, 0), 59)

        if let data = defaults.data(forKey: periodsKey),
           let decoded = try? JSONDecoder().decode([BrightnessPeriod].self, from: data) {
            var accepted: [BrightnessPeriod] = []
            for period in decoded where period.isValid {
                guard accepted.count < 3, !accepted.contains(where: { $0.id == period.id || $0.overlaps(period) }) else { continue }
                accepted.append(period)
            }
            customPeriods = accepted.sorted { $0.startMinutes < $1.startMinutes }
        } else {
            customPeriods = []
        }
        // Reduce precision of coordinates saved by older versions as well.
        if hasSavedLocation {
            defaults.set(latitude, forKey: "latitude")
            defaults.set(longitude, forKey: "longitude")
        } else {
            defaults.removeObject(forKey: "latitude")
            defaults.removeObject(forKey: "longitude")
        }

    }

    var solarLocationSource: SolarLocationSource {
        get { SolarLocationSource(rawValue: solarLocationSourceRaw) ?? .manual }
        set { solarLocationSourceRaw = newValue.rawValue }
    }

    @discardableResult
    func setCoordinates(latitude: Double, longitude: Double) -> Bool {
        guard let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude)?.roundedForStorage else { return false }
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        hasSavedLocation = true
        return true
    }

    func clearLocation() {
        latitude = 0
        longitude = 0
        hasSavedLocation = false
        solarLocationSource = .manual
        defaults.removeObject(forKey: "latitude")
        defaults.removeObject(forKey: "longitude")
        defaults.removeObject(forKey: "useCoreLocation")
    }

    var automationSettings: AutomationSettings {
        AutomationSettings(periodic: overrideEnabled, tab: automationTab,
                           manualBrightness: manualBrightness, manualAmbient: manualAutoBrightness,
                           nightBrightness: solarNightBrightness, nightAmbient: solarAutoBrightness,
                           inactivityEnabled: inactivityTimeoutEnabled,
                           inactivityMinutes: inactivityTimeoutMinutes, inactivitySeconds: inactivityTimeoutSeconds,
                           periods: customPeriods)
    }

    func overlappingPeriod(with candidate: BrightnessPeriod,
                           ignoringID: UUID? = nil) -> BrightnessPeriod? {
        customPeriods.first {
            $0.id != ignoringID && $0.overlaps(candidate)
        }
    }

    @discardableResult
    func addPeriod(_ period: BrightnessPeriod) -> Bool {
        guard period.isValid, customPeriods.count < 3 else { return false }
        guard !customPeriods.contains(where: { $0.id == period.id }),
              overlappingPeriod(with: period) == nil else { return false }
        customPeriods.append(period)
        sortPeriods()
        return true
    }

    func removePeriod(id: UUID) {
        customPeriods.removeAll { $0.id == id }
    }

    @discardableResult
    func updatePeriod(_ period: BrightnessPeriod) -> Bool {
        guard period.isValid, overlappingPeriod(with: period, ignoringID: period.id) == nil else {
            return false
        }
        if let idx = customPeriods.firstIndex(where: { $0.id == period.id }) {
            customPeriods[idx] = period
            sortPeriods()
            return true
        }
        return false
    }

    private func sortPeriods() {
        customPeriods.sort { $0.startMinutes < $1.startMinutes }
    }
}
