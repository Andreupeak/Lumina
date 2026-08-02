import SwiftUI
import CoreLocation
import Combine
import AppKit
import os.log

// MARK: - 1. DYNAMIC SYSTEM HARDWARE INTEGRATION
class KeyboardBacklightManager {
    static let shared = KeyboardBacklightManager()

    private var client: NSObject?
    private var keyboardID: UInt64 = 0
    private var isLoaded = false
    private var loadAttempted = false
    private(set) var isAvailable: Bool = false

    private let setBrightnessSel       = NSSelectorFromString("setBrightness:forKeyboard:")
    private let getBrightnessSel       = NSSelectorFromString("brightnessForKeyboard:")
    private let getKeyboardIDsSel      = NSSelectorFromString("copyKeyboardBacklightIDs")
    private let isSaturatedSel         = NSSelectorFromString("isBacklightSaturatedOnKeyboard:")
    private let isAutoBrightnessSel    = NSSelectorFromString("isAutoBrightnessEnabledForKeyboard:")
    private let setAutoBrightnessSel   = NSSelectorFromString("enableAutoBrightness:forKeyboard:")

    private static let msgSend: UnsafeMutableRawPointer = {
        dlsym(dlopen(nil, RTLD_NOW), "objc_msgSend")!
    }()

    private init() {}

    @discardableResult
    func load() -> Bool {
        guard !loadAttempted else { return isLoaded }
        loadAttempted = true

        guard let bundle = Bundle(
            path: "/System/Library/PrivateFrameworks/CoreBrightness.framework"
        ), bundle.load() else {
            return false
        }

        guard let clientClass = NSClassFromString("KeyboardBrightnessClient")
                as? NSObject.Type else {
            return false
        }

        let instance = clientClass.init()

        guard instance.responds(to: getKeyboardIDsSel),
              let ids = instance.perform(getKeyboardIDsSel)?
                .takeUnretainedValue() as? [NSNumber],
              let firstID = ids.first else {
            return false
        }

        client = instance
        keyboardID = firstID.uint64Value
        isLoaded = true
        isAvailable = true
        return true
    }

    var currentBrightness: Float? {
        guard isLoaded, let client, client.responds(to: getBrightnessSel) else {
            return nil
        }
        typealias GetFunc = @convention(c) (AnyObject, Selector, UInt64) -> Float
        let fn = unsafeBitCast(Self.msgSend, to: GetFunc.self)
        return fn(client, getBrightnessSel, keyboardID)
    }

    @discardableResult
    func setBrightness(_ level: Float) -> Bool {
        if !isLoaded {
            guard load() else { return false }
        }
        guard let client, client.responds(to: setBrightnessSel) else {
            return false
        }
        let clamped = min(max(level, 0.0), 1.0)
        typealias SetFunc = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool
        let fn = unsafeBitCast(Self.msgSend, to: SetFunc.self)
        return fn(client, setBrightnessSel, clamped, keyboardID)
    }

    @discardableResult
    func setAutoBrightnessEnabled(_ enabled: Bool) -> Bool {
        if !isLoaded {
            guard load() else { return false }
        }
        guard let client, client.responds(to: setAutoBrightnessSel) else {
            return false
        }
        typealias SetAutoFunc = @convention(c) (AnyObject, Selector, Bool, UInt64) -> Bool
        let fn = unsafeBitCast(Self.msgSend, to: SetAutoFunc.self)
        return fn(client, setAutoBrightnessSel, enabled, keyboardID)
    }
}

// MARK: - 2. PERSISTENT STORAGE & PERIOD MODELS
struct BrightnessPeriod: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var brightness: Double
    var useAmbient: Bool = false
    var timeoutMinutes: Int = 0
    var timeoutSeconds: Int = 0

    enum CodingKeys: String, CodingKey {
        case id, name, startHour, startMinute, endHour, endMinute, brightness, useAmbient, timeoutMinutes, timeoutSeconds
    }

    init(
        id: UUID = UUID(),
        name: String,
        startHour: Int,
        startMinute: Int,
        endHour: Int,
        endMinute: Int,
        brightness: Double,
        useAmbient: Bool = false,
        timeoutMinutes: Int = 0,
        timeoutSeconds: Int = 0
    ) {
        self.id = id
        self.name = name
        self.startHour = startHour
        self.startMinute = startMinute
        self.endHour = endHour
        self.endMinute = endMinute
        self.brightness = brightness
        self.useAmbient = useAmbient
        self.timeoutMinutes = timeoutMinutes
        self.timeoutSeconds = timeoutSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        startHour = try container.decode(Int.self, forKey: .startHour)
        startMinute = try container.decode(Int.self, forKey: .startMinute)
        endHour = try container.decode(Int.self, forKey: .endHour)
        endMinute = try container.decode(Int.self, forKey: .endMinute)
        brightness = try container.decode(Double.self, forKey: .brightness)
        useAmbient = try container.decodeIfPresent(Bool.self, forKey: .useAmbient) ?? false
        timeoutMinutes = try container.decodeIfPresent(Int.self, forKey: .timeoutMinutes) ?? 0
        timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 0
    }

    static func == (lhs: BrightnessPeriod, rhs: BrightnessPeriod) -> Bool {
        lhs.id == rhs.id &&
        lhs.name == rhs.name &&
        lhs.startHour == rhs.startHour &&
        lhs.startMinute == rhs.startMinute &&
        lhs.endHour == rhs.endHour &&
        lhs.endMinute == rhs.endMinute &&
        lhs.brightness == rhs.brightness &&
        lhs.useAmbient == rhs.useAmbient &&
        lhs.timeoutMinutes == rhs.timeoutMinutes &&
        lhs.timeoutSeconds == rhs.timeoutSeconds
    }

    var startMinutes: Int { startHour * 60 + startMinute }
    var endMinutes: Int { endHour * 60 + endMinute }

    var intervals: [(Int, Int)] {
        let s = startMinutes
        let e = endMinutes
        if s == e { return [] }
        if s < e { return [(s, e)] }
        return [(s, 1440), (0, e)]
    }

    func contains(minuteOfDay m: Int) -> Bool {
        intervals.contains { m >= $0.0 && m < $0.1 }
    }

    func overlaps(_ other: BrightnessPeriod) -> Bool {
        for a in intervals {
            for b in other.intervals where a.0 < b.1 && b.0 < a.1 {
                return true
            }
        }
        return false
    }
}

enum SolarLocationSource: String {
    case precise
    case approximate
    case manual
}

class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let periodsKey = "customPeriods_v3"
    private let solarLocationSourceKey = "solarLocationSource"

    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: "hasCompletedOnboarding") }
    }

    @Published var defaultStartupBrightness: Double {
        didSet { defaults.set(defaultStartupBrightness, forKey: "defaultStartupBrightness") }
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

    @Published var latitude: Double {
        didSet { defaults.set(latitude, forKey: "latitude") }
    }

    @Published var longitude: Double {
        didSet { defaults.set(longitude, forKey: "longitude") }
    }

    @Published var useCoreLocation: Bool {
        didSet { defaults.set(useCoreLocation, forKey: "useCoreLocation") }
    }

    @Published var solarLocationSourceRaw: String {
        didSet { defaults.set(solarLocationSourceRaw, forKey: solarLocationSourceKey) }
    }

    @Published var solarEnabled: Bool {
        didSet { defaults.set(solarEnabled, forKey: "solarEnabled") }
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

    @Published var customPeriods: [BrightnessPeriod] {
        didSet {
            if let data = try? JSONEncoder().encode(customPeriods) {
                defaults.set(data, forKey: periodsKey)
            }
        }
    }

    private init() {
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
        defaultStartupBrightness = defaults.object(forKey: "defaultStartupBrightness") as? Double ?? 0.5
        overrideEnabled = defaults.object(forKey: "overrideEnabled") as? Bool ?? false
        manualBrightness = defaults.object(forKey: "manualBrightness") as? Double ?? 0.0
        manualAutoBrightness = defaults.object(forKey: "manualAutoBrightness") as? Bool ?? false
        automationTab = defaults.object(forKey: "automationTab") as? Int ?? 0
        solarNightBrightness = defaults.object(forKey: "solarNightBrightness") as? Double ?? 0.5
        solarAutoBrightness = defaults.object(forKey: "solarAutoBrightness") as? Bool ?? false
        latitude = defaults.object(forKey: "latitude") as? Double ?? 37.3318
        longitude = defaults.object(forKey: "longitude") as? Double ?? -122.0308
        let savedUseCoreLocation = defaults.object(forKey: "useCoreLocation") as? Bool ?? false
        useCoreLocation = savedUseCoreLocation
        solarLocationSourceRaw = defaults.string(forKey: solarLocationSourceKey)
            ?? (savedUseCoreLocation ? SolarLocationSource.precise.rawValue : SolarLocationSource.manual.rawValue)
        solarEnabled = defaults.object(forKey: "solarEnabled") as? Bool ?? true

        inactivityTimeoutEnabled = defaults.object(forKey: "inactivityTimeoutEnabled") as? Bool ?? false
        inactivityTimeoutMinutes = defaults.object(forKey: "inactivityTimeoutMinutes") as? Int ?? 0
        inactivityTimeoutSeconds = defaults.object(forKey: "inactivityTimeoutSeconds") as? Int ?? 30

        if let data = defaults.data(forKey: periodsKey),
           let decoded = try? JSONDecoder().decode([BrightnessPeriod].self, from: data) {
            customPeriods = decoded
        } else {
            customPeriods = []
        }
    }

    var solarLocationSource: SolarLocationSource {
        get { SolarLocationSource(rawValue: solarLocationSourceRaw) ?? .manual }
        set { solarLocationSourceRaw = newValue.rawValue }
    }

    func overlappingPeriod(with candidate: BrightnessPeriod,
                           ignoringID: UUID? = nil) -> BrightnessPeriod? {
        customPeriods.first {
            $0.id != ignoringID && $0.overlaps(candidate)
        }
    }

    @discardableResult
    func addPeriod(_ period: BrightnessPeriod) -> Bool {
        guard customPeriods.count < 3 else { return false }
        guard overlappingPeriod(with: period) == nil else { return false }
        customPeriods.append(period)
        sortPeriods()
        return true
    }

    func removePeriod(id: UUID) {
        customPeriods.removeAll { $0.id == id }
    }

    @discardableResult
    func updatePeriod(_ period: BrightnessPeriod) -> Bool {
        guard overlappingPeriod(with: period, ignoringID: period.id) == nil else {
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

// MARK: - 3. STANDALONE SOLAR TRANSIT MATHEMATICS (100% OFFLINE)
struct SolarCalculator {
    static func calculateSunriseSunset(latitude: Double, longitude: Double, date: Date = Date(), timeZone: TimeZone = .current) -> (sunrise: Date, sunset: Date) {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        
        let year = components.year ?? 2026
        let month = components.month ?? 1
        let day = components.day ?? 1
        
        let N1 = floor(275.0 * Double(month) / 9.0)
        let N2 = floor((Double(month) + 9.0) / 12.0)
        let N3 = (1.0 + floor((Double(year) - 4.0 * floor(Double(year) / 4.0) + 2.0) / 3.0))
        let N = N1 - (N2 * N3) + Double(day) - 30.0
        
        let lngHour = longitude / 15.0
        let t_rise = N + ((6.0 - lngHour) / 24.0)
        let t_set = N + ((18.0 - lngHour) / 24.0)
        
        let sunriseUTC = computeSunTime(t: t_rise, latitude: latitude, longitude: longitude, isSunrise: true)
        let sunsetUTC = computeSunTime(t: t_set, latitude: latitude, longitude: longitude, isSunrise: false)
        
        let sunriseHourUTC = sunriseUTC ?? 6.0
        let sunsetHourUTC = sunsetUTC ?? 18.0
        
        let offset = Double(timeZone.secondsFromGMT(for: date)) / 3600.0
        
        var localSunrise = sunriseHourUTC + offset
        var localSunset = sunsetHourUTC + offset
        
        if localSunrise < 0 { localSunrise += 24 }
        if localSunrise >= 24 { localSunrise -= 24 }
        if localSunset < 0 { localSunset += 24 }
        if localSunset >= 24 { localSunset -= 24 }
        
        let sunMinutes = Int((localSunrise - floor(localSunrise)) * 60)
        let sunHours = Int(floor(localSunrise))
        
        let setHours = Int(floor(localSunset))
        let setMinutes = Int((localSunset - floor(localSunset)) * 60)
        
        var riseComponents = DateComponents()
        riseComponents.year = year
        riseComponents.month = month
        riseComponents.day = day
        riseComponents.hour = sunHours
        riseComponents.minute = sunMinutes
        riseComponents.timeZone = timeZone
        
        var setComponents = DateComponents()
        setComponents.year = year
        setComponents.month = month
        setComponents.day = day
        setComponents.hour = setHours
        setComponents.minute = setMinutes
        setComponents.timeZone = timeZone
        
        let riseDate = calendar.date(from: riseComponents) ?? date
        let setDate = calendar.date(from: setComponents) ?? date
        
        return (riseDate, setDate)
    }
    
    private static func computeSunTime(t: Double, latitude: Double, longitude: Double, isSunrise: Bool) -> Double? {
        let L1 = 280.460
        let L2 = 0.9856474
        let g1 = 357.528
        let g2 = 0.9856003
        
        let M = g1 + g2 * t
        let M_rad = M * .pi / 180.0
        
        var L = L1 + L2 * t + 1.915 * sin(M_rad) + 0.020 * sin(2.0 * M_rad)
        if L < 0 { L += 360.0 * (floor(abs(L) / 360.0) + 1.0) }
        if L >= 360 { L = L.truncatingRemainder(dividingBy: 360.0) }
        
        var RA = atan(0.91764 * tan(L * .pi / 180.0)) * 180.0 / .pi
        if RA < 0 { RA += 360.0 * (floor(abs(RA) / 360.0) + 1.0) }
        if RA >= 360 { RA = RA.truncatingRemainder(dividingBy: 360.0) }
        
        let Lquadrant = floor(L / 90.0) * 90.0
        let RAquadrant = floor(RA / 90.0) * 90.0
        RA = RA + (Lquadrant - RAquadrant)
        RA = RA / 15.0
        
        let sinDec = 0.39782 * sin(L * .pi / 180.0)
        let cosDec = cos(asin(sinDec))
        
        let zenith = 90.833
        let cosH = (cos(zenith * .pi / 180.0) - (sinDec * sin(latitude * .pi / 180.0))) / (cosDec * cos(latitude * .pi / 180.0))
        
        if cosH > 1.0 || cosH < -1.0 { return nil }
        
        var H = acos(cosH) * 180.0 / .pi
        if isSunrise { H = 360.0 - H }
        H = H / 15.0
        
        let T = H + RA - (0.06571 * t) - 6.622
        var UT = T - (longitude / 15.0)
        if UT < 0 { UT += 24 }
        if UT >= 24 { UT -= 24 }
        
        return UT
    }
}

// MARK: - 4. LOCAL SUN CALCULATOR & GPS MANAGEMENT
class SunScheduleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SunScheduleManager()

    private struct IPGeolocationResponse: Decodable {
        let latitude: Double?
        let longitude: Double?
        let city: String?
        let region: String?
        let countryName: String?
        let error: Bool?
        let reason: String?

        enum CodingKeys: String, CodingKey {
            case latitude
            case longitude
            case city
            case region
            case countryName = "country_name"
            case error
            case reason
        }
    }

    private let locationManager = CLLocationManager()
    private var locationTimeoutWorkItem: DispatchWorkItem?
    private var shouldFallbackToApproximate = false
    private var lastSolarRefreshDay: Date?

    private let acceptableCachedLocationAge: TimeInterval = 5 * 60

    @Published var isAuthorized: Bool = false
    @Published var lastError: String?
    @Published var isLocating: Bool = false
    @Published var isFetchingApproximateLocation: Bool = false

    @Published var sunrise: Date?
    @Published var sunset: Date?

    private var hasFreshCoordinates: Bool {
        Preferences.shared.useCoreLocation && sunrise != nil && sunset != nil
    }

    var isNighttime: Bool? {
        let currentSunrise: Date
        let currentSunset: Date

        if let sunrise, let sunset {
            currentSunrise = sunrise
            currentSunset = sunset
        } else {
            let lat = Preferences.shared.latitude
            let lon = Preferences.shared.longitude
            let fallback = SolarCalculator.calculateSunriseSunset(latitude: lat, longitude: lon)
            currentSunrise = fallback.sunrise
            currentSunset = fallback.sunset
        }

        let calendar = Calendar.current
        let now = Date()
        let currentMinute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let sunriseMinute = calendar.component(.hour, from: currentSunrise) * 60 + calendar.component(.minute, from: currentSunrise)
        let sunsetMinute = calendar.component(.hour, from: currentSunset) * 60 + calendar.component(.minute, from: currentSunset)

        // The night window crosses midnight in normal cases:
        // from today's sunset through tomorrow's sunrise.
        if sunsetMinute > sunriseMinute {
            return currentMinute >= sunsetMinute || currentMinute < sunriseMinute
        }

        // Fallback for edge cases where the computed solar window does not cross midnight.
        return currentMinute >= sunsetMinute && currentMinute < sunriseMinute
    }

    var sunriseLabel: String { formatTime(sunrise) }
    var sunsetLabel: String { formatTime(sunset) }
    var activeWindowLabel: String {
        if Preferences.shared.useCoreLocation && isLocating {
            return "Locating current sunset and sunrise…"
        }
        if isFetchingApproximateLocation {
            return "Estimating location from internet connection…"
        }
        if Preferences.shared.useCoreLocation && !hasFreshCoordinates {
            return "Waiting for your Mac's location…"
        }
        guard let sunrise, let sunset else { return "Calculating…" }
        return "\(formatTime(sunset)) - \(formatTime(sunrise))"
    }

    var locationLabel: String {
        if Preferences.shared.useCoreLocation {
            return String(format: "%.2f, %.2f", Preferences.shared.latitude, Preferences.shared.longitude)
        }
        return "Manual Setup"
    }

    var needsSettings: Bool {
        if !CLLocationManager.locationServicesEnabled() { return true }
        let status = locationManager.authorizationStatus
        return status == .denied || status == .restricted
    }

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.distanceFilter = kCLDistanceFilterNone
        let status = locationManager.authorizationStatus
        isAuthorized = status == .authorizedAlways || status == .authorized

        refreshSolarTimes()
    }

    func requestAuthorization() {
        locationManager.requestWhenInUseAuthorization()
    }

    func refreshLocationOnceAtStartup() {
        guard Preferences.shared.solarLocationSource != .manual else {
            refreshSolarTimesIfNeeded(force: true)
            return
        }

        Preferences.shared.useCoreLocation = true
        Preferences.shared.solarLocationSource = .precise
        requestLocation(fallbackToApproximate: true)
    }

    func requestLocation(fallbackToApproximate: Bool = false) {
        if isLocating { return }
        shouldFallbackToApproximate = fallbackToApproximate

        guard CLLocationManager.locationServicesEnabled() else {
            cancelLocationRequest()
            isLocating = false
            lastError = "Location Services are turned off in System Settings."
            fallbackToApproximateIfNeeded()
            return
        }

        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways, .authorized:
            lastError = nil
            isLocating = true
            if let cachedLocation = locationManager.location,
               abs(cachedLocation.timestamp.timeIntervalSinceNow) <= acceptableCachedLocationAge {
                applyLocation(cachedLocation)
                return
            }
            beginLocationTimeout()
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
        case .notDetermined:
            isLocating = true
            requestAuthorization()
        case .denied, .restricted:
            cancelLocationRequest()
            isLocating = false
            lastError = "Lumina does not currently have location access."
            fallbackToApproximateIfNeeded()
        @unknown default:
            cancelLocationRequest()
            isLocating = false
            lastError = "Location access is unavailable right now."
            fallbackToApproximateIfNeeded()
        }
    }

    func refreshPreciseLocationFromUserAction() {
        guard Preferences.shared.useCoreLocation else { return }
        guard !needsSettings else { return }
        guard !isLocating else { return }

        requestLocation()
    }

    func setAutomaticLocationEnabled(_ enabled: Bool) {
        Preferences.shared.useCoreLocation = enabled
        if enabled {
            Preferences.shared.solarLocationSource = .precise
            requestLocation(fallbackToApproximate: true)
        } else {
            cancelLocationRequest()
            isLocating = false
            lastError = nil
            locationManager.stopUpdatingLocation()
        }
    }

    func useManualCoordinates() {
        Preferences.shared.useCoreLocation = false
        Preferences.shared.solarLocationSource = .manual
        cancelLocationRequest()
        isLocating = false
        isFetchingApproximateLocation = false
        lastError = nil
        refreshSolarTimes()
        AutoBacklightController.shared.evaluateAndApply()
    }

    func beginManualEntry() {
        Preferences.shared.useCoreLocation = false
        Preferences.shared.solarLocationSource = .manual
        cancelLocationRequest()
        isLocating = false
        isFetchingApproximateLocation = false
        lastError = nil
        refreshSolarTimesIfNeeded(force: true)
        AutoBacklightController.shared.evaluateAndApply()
    }

    func requestApproximateLocationFromInternet() {
        Preferences.shared.useCoreLocation = false
        Preferences.shared.solarLocationSource = .approximate
        cancelLocationRequest()
        isLocating = false
        isFetchingApproximateLocation = true
        lastError = nil

        guard let url = URL(string: "https://ipapi.co/json/") else {
            isFetchingApproximateLocation = false
            lastError = "Could not build the approximate location request."
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Lumina/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isFetchingApproximateLocation = false

                if let error {
                    self.lastError = "Approximate location failed: \(error.localizedDescription)"
                    return
                }

                guard let data else {
                    self.lastError = "Approximate location failed because no data was returned."
                    return
                }

                do {
                    let response = try JSONDecoder().decode(IPGeolocationResponse.self, from: data)
                    if response.error == true {
                        self.lastError = response.reason ?? "Approximate location lookup failed."
                        return
                    }

                    guard let latitude = response.latitude, let longitude = response.longitude else {
                        self.lastError = "Approximate location lookup returned no coordinates."
                        return
                    }

                    self.applyLocation(CLLocation(latitude: latitude, longitude: longitude))
                } catch {
                    self.lastError = "Approximate location response could not be read."
                }
            }
        }.resume()
    }

    func enableLocationTapped() {
        switch locationManager.authorizationStatus {
        case .notDetermined:
            requestAuthorization()
        case .denied, .restricted:
            openLocationSettings()
        default:
            requestLocation(fallbackToApproximate: true)
        }
    }

    func openLocationSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        ]

        for value in urls {
            if let url = URL(string: value), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
    }

    func handleLocationButtonTap() {
        if Preferences.shared.useCoreLocation {
            if needsSettings || !isAuthorized {
                openLocationSettings()
            } else {
                refreshPreciseLocationFromUserAction()
            }
        } else {
            Preferences.shared.solarLocationSource = .precise
            setAutomaticLocationEnabled(true)
        }
    }

    func refreshSolarTimes() {
        let lat = Preferences.shared.latitude
        let lon = Preferences.shared.longitude
        let times = SolarCalculator.calculateSunriseSunset(latitude: lat, longitude: lon)
        sunrise = times.sunrise
        sunset = times.sunset
        lastSolarRefreshDay = Calendar.current.startOfDay(for: Date())
    }

    func refreshSolarTimesIfNeeded(force: Bool = false) {
        let today = Calendar.current.startOfDay(for: Date())
        if force || lastSolarRefreshDay != today {
            refreshSolarTimes()
        }
    }

    private func beginLocationTimeout() {
        locationTimeoutWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isLocating else { return }
            self.locationManager.stopUpdatingLocation()
            self.isLocating = false
            self.lastError = "macOS granted permission, but did not return a location. This usually means the Mac has no current location fix yet."
            self.fallbackToApproximateIfNeeded()
        }
        locationTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: workItem)
    }

    private func cancelLocationRequest() {
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
    }

    private lazy var timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func formatTime(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        return timeFormatter.string(from: date)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let authorized = manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorized
        isAuthorized = authorized
        if authorized {
            isLocating = false
            requestLocation(fallbackToApproximate: shouldFallbackToApproximate)
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            cancelLocationRequest()
            isLocating = false
            lastError = "Lumina does not currently have location access."
            fallbackToApproximateIfNeeded()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        applyLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        if nsError.domain == kCLErrorDomain, nsError.code == CLError.locationUnknown.rawValue {
            lastError = "Your Mac has permission, but Core Location still doesn't know where it is yet."
            fallbackToApproximateIfNeeded()
            return
        }
        cancelLocationRequest()
        isLocating = false
        if nsError.domain == kCLErrorDomain,
           nsError.code == CLError.network.rawValue {
            lastError = "Core Location could not resolve your Mac's position. Check Wi-Fi and Location Services."
        } else {
            lastError = error.localizedDescription
        }
        fallbackToApproximateIfNeeded()
    }

    private func fallbackToApproximateIfNeeded() {
        guard shouldFallbackToApproximate else { return }
        shouldFallbackToApproximate = false
        requestApproximateLocationFromInternet()
    }

    private func applyLocation(_ location: CLLocation) {
        Preferences.shared.latitude = location.coordinate.latitude
        Preferences.shared.longitude = location.coordinate.longitude

        cancelLocationRequest()
        isLocating = false
        isFetchingApproximateLocation = false
        lastError = nil
        shouldFallbackToApproximate = false
        refreshSolarTimes()
        AutoBacklightController.shared.evaluateAndApply()

        locationManager.stopUpdatingLocation()
    }
}

// MARK: - 5. COHERENT BRIGHTNESS MANAGER (BRAIN & FAST IDLE POLLER)
class AutoBacklightController: ObservableObject {
    static let shared = AutoBacklightController()

    private let keyboard = KeyboardBacklightManager.shared
    private let sun = SunScheduleManager.shared
    private let prefs = Preferences.shared

    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()

    @Published var currentStatus: String = "Starting…"
    @Published var isNightMode: Bool = false
    @Published var keyboardAvailable: Bool = false
    @Published var activePeriodName: String?

    private var launchTime = Date()
    private var lastAppliedSignature: String?

    private init() {
        observeChanges()
    }

    func startMonitoring() {
        keyboardAvailable = keyboard.load()

        if keyboardAvailable {
            let startupLevel = prefs.defaultStartupBrightness
            keyboard.setAutoBrightnessEnabled(false)
            keyboard.setBrightness(Float(startupLevel))
        }

        timer?.invalidate()
        // Fast 100ms timer loop to track idle-state and execute instant wake-ups
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        tick()
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        currentStatus = "Stopped"
        activePeriodName = nil
    }

    private var lastTickMinutes = -1
    private var wasInactivityOff = false

    func tick() {
        guard keyboardAvailable else { return }

        let now = Date()
        let cal = Calendar.current
        let curMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        sun.refreshSolarTimesIfNeeded()

        let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let maxIdleSeconds = activeIdleTimeoutSeconds

        let isGracePeriod = Date().timeIntervalSince(launchTime) < 10.0
        let isIdle = maxIdleSeconds.map { idleSeconds >= $0 && !isGracePeriod } ?? false
        // True only when the user has provided input within the last second. This lets us
        // distinguish a genuine wake-up from the idle-timeout source simply disappearing
        // (a time slot ending, or the inactivity timeout being turned off) while the user
        // is still away — in that case the backlight must stay off rather than lighting up
        // an unattended keyboard.
        let userJustActed = idleSeconds < 1.0 && !isGracePeriod

        if isIdle {
            if !wasInactivityOff {
                wasInactivityOff = true
                applyIdleTimeout()
            }
        } else if wasInactivityOff {
            // We previously dimmed for inactivity. Only restore brightness once the user
            // actually interacts again; otherwise stay dimmed even if the active timeout
            // source changed underneath us (e.g. the time slot just ended).
            if userJustActed {
                wasInactivityOff = false
                lastTickMinutes = curMin
                evaluateAndApply()
            }
        } else if curMin != lastTickMinutes {
            // Background update path (throttled to minute changes to prevent CPU cycle spam)
            lastTickMinutes = curMin
            evaluateAndApply()
        }
    }

    func evaluateAndApply() {
        guard keyboardAvailable else {
            currentStatus = "No keyboard backlight"
            activePeriodName = nil
            return
        }

        if let until = previewUntil, until > Date() { return }

        if let maxIdleSeconds = activeIdleTimeoutSeconds {
            let idleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
            let isGracePeriod = Date().timeIntervalSince(launchTime) < 10.0
            if idleSeconds >= maxIdleSeconds && !isGracePeriod {
                applyIdleTimeout()
                return
            }
        }

        if !prefs.overrideEnabled {
            applyManual()
        } else {
            if prefs.automationTab == 0 {
                applySolar()
            } else {
                if let period = firstMatchingCustomPeriod() {
                    applyPeriodic(period)
                } else {
                    // Outside every defined time slot the backlight should be off, not
                    // left at the System/manual brightness. This mirrors the Solar tab,
                    // which turns off during the day outside its night period — and it
                    // matches the expectation that a slot defines "when the backlight is
                    // on"; everything else is off.
                    applyOffSchedule()
                }
            }
        }
    }

    private var previewUntil: Date?

    private var activeIdleTimeoutSeconds: Double? {
        if prefs.overrideEnabled, prefs.automationTab == 1, let period = firstMatchingCustomPeriod() {
            // A per-slot timeout of 00:00 means "no idle dimming for this slot": fall
            // through to the global inactivity setting instead of clamping to 1 second.
            let slotTotal = period.timeoutMinutes * 60 + period.timeoutSeconds
            if slotTotal > 0 { return Double(slotTotal) }
        }

        guard prefs.inactivityTimeoutEnabled else { return nil }
        let globalTotal = prefs.inactivityTimeoutMinutes * 60 + prefs.inactivityTimeoutSeconds
        guard globalTotal > 0 else { return nil }
        return Double(globalTotal)
    }

    private func applyIdleTimeout() {
        let intended = intendedStatusForCurrentMode()
        apply(
            brightness: 0.0,
            useAmbient: false,
            label: "Idle Timeout",
            periodName: intended.periodName,
            night: intended.night,
            statusOverride: intended.status
        )
    }

    private func intendedStatusForCurrentMode() -> (status: String, periodName: String?, night: Bool) {
        if !prefs.overrideEnabled {
            return (
                statusText(label: "System", brightness: prefs.manualBrightness, useAmbient: prefs.manualAutoBrightness),
                nil,
                false
            )
        }

        if prefs.automationTab == 0 {
            let isNight = sun.isNighttime ?? isNightMode
            if isNight {
                return (
                    statusText(label: "Night", brightness: prefs.solarNightBrightness, useAmbient: prefs.solarAutoBrightness),
                    "Night",
                    true
                )
            }
            return (statusText(label: "Day", brightness: 0.0, useAmbient: false), nil, false)
        }

        if let period = firstMatchingCustomPeriod() {
            return (
                statusText(label: period.name, brightness: period.brightness, useAmbient: period.useAmbient),
                period.name,
                sun.isNighttime ?? isNightMode
            )
        }

        // Outside every defined time slot the backlight is off (see evaluateAndApply).
        return (
            "Off • Outside schedule",
            nil,
            false
        )
    }

    func previewBrightness(_ value: Double) {
        guard keyboardAvailable else { return }
        lastAppliedSignature = nil
        previewUntil = Date().addingTimeInterval(3)
        keyboard.setAutoBrightnessEnabled(false)
        let clamped = min(max(value, 0.0), 1.0)
        keyboard.setBrightness(Float(clamped))
        currentStatus = "Preview • " + (clamped == 0 ? "Off" : "\(Int((clamped * 100).rounded()))%")

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1) { [weak self] in
            guard let self else { return }
            if let until = self.previewUntil, until <= Date() {
                self.previewUntil = nil
                self.evaluateAndApply()
            }
        }
    }

    private func applyManual() {
        apply(brightness: prefs.manualBrightness,
              useAmbient: prefs.manualAutoBrightness,
              label: "System",
              periodName: nil,
              night: false)
    }

    /// Backlight off because the current time is outside every defined custom slot.
    private func applyOffSchedule() {
        apply(brightness: 0.0,
              useAmbient: false,
              label: "Off",
              periodName: nil,
              night: false,
              statusOverride: "Off • Outside schedule")
    }

    private func applySolar() {
        guard let isNight = sun.isNighttime else {
            currentStatus = "Waiting for coordinates…"
            activePeriodName = nil
            return
        }

        if isNight {
            apply(brightness: prefs.solarNightBrightness,
                  useAmbient: prefs.solarAutoBrightness,
                  label: "Night",
                  periodName: "Night",
                  night: true)
        } else {
            apply(brightness: 0.0,
                  useAmbient: false,
                  label: "Day",
                  periodName: nil,
                  night: false)
        }
    }

    private func applyPeriodic(_ period: BrightnessPeriod) {
        apply(brightness: period.brightness,
              useAmbient: period.useAmbient,
              label: period.name,
              periodName: period.name,
              night: sun.isNighttime ?? isNightMode)
    }

    private func firstMatchingCustomPeriod() -> BrightnessPeriod? {
        let now = Date()
        let cal = Calendar.current
        let curMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
        return prefs.customPeriods.first { $0.contains(minuteOfDay: curMin) }
    }

    private func apply(brightness: Double,
                       useAmbient: Bool,
                       label: String,
                       periodName: String?,
                       night: Bool,
                       statusOverride: String? = nil) {
        let clamped = min(max(brightness, 0.0), 1.0)
        let signature = "\(label)|\(periodName ?? "-")|\(useAmbient)|\(night)|\(String(format: "%.3f", clamped))|\(statusOverride ?? "-")"

        if signature != lastAppliedSignature {
            if useAmbient {
                // Seed a visible brightness before returning control to the ambient sensor.
                // Without this, waking from an idle timeout can leave the keyboard stuck at 0.
                let seedBrightness = Float(max(clamped, 0.08))
                keyboard.setAutoBrightnessEnabled(false)
                keyboard.setBrightness(seedBrightness)
                keyboard.setAutoBrightnessEnabled(true)
            } else {
                keyboard.setAutoBrightnessEnabled(false)
                keyboard.setBrightness(Float(clamped))
            }
            lastAppliedSignature = signature
        }

        activePeriodName = periodName
        isNightMode = night

        currentStatus = statusOverride ?? statusText(label: label, brightness: clamped, useAmbient: useAmbient)
    }

    private func statusText(label: String, brightness: Double, useAmbient: Bool) -> String {
        let clamped = min(max(brightness, 0.0), 1.0)
        let detail: String
        if useAmbient {
            detail = "Auto"
        } else {
            detail = clamped == 0 ? "Off" : "\(Int((clamped * 100).rounded()))%"
        }
        return "\(label) • \(detail)"
    }

    private func observeChanges() {
        prefs.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateAndApply() }
            .store(in: &cancellables)

        prefs.$latitude
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateAndApply() }
            .store(in: &cancellables)

        prefs.$longitude
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.evaluateAndApply() }
            .store(in: &cancellables)
    }

    deinit {
        timer?.invalidate()
    }
}

// MARK: - 6. LUMINA USER INTERFACE VIEWS
private enum LuminaText {
    static let muted = Color.white.opacity(0.72)
    static let soft = Color.white.opacity(0.58)
    static let faint = Color.white.opacity(0.44)
}

struct ContentView: View {
    @ObservedObject private var prefs = Preferences.shared
    @ObservedObject private var controller = AutoBacklightController.shared
    @ObservedObject private var sun = SunScheduleManager.shared

    // Onboarding Wizard Navigation
    @State private var onboardingPage = 0

    // Custom-period editing state
    @State private var editingID: UUID? = nil
    @State private var draft: BrightnessPeriod? = nil
    @State private var isAddingNew = false
    @State private var overlapWarning = false
    @State private var showManualLocationEditor = false
    @State private var showLocationControls = false

    private let locationSourceButtonRowWidth: CGFloat = 142
    private let locationControlTrayWidth: CGFloat = 162

    private var systemActive: Bool { !prefs.overrideEnabled }
    private var customActive: Bool { prefs.overrideEnabled }

    var body: some View {
        ZStack {
            if !prefs.hasCompletedOnboarding {
                onboardingPanel
                    .transition(.asymmetric(
                        insertion: .opacity,
                        removal: .move(edge: .bottom).combined(with: .opacity)))
            } else {
                mainPanel
                    .transition(.opacity)
            }
        }
        .frame(width: 380)
        .background(BackdropGradient(isNight: controller.isNightMode))
        .animation(Motion.smooth, value: prefs.hasCompletedOnboarding)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            collapseLocationControls()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            collapseLocationControls()
        }
    }

    private func collapseLocationControls() {
        guard showLocationControls || showManualLocationEditor else { return }
        withAnimation(Motion.smooth) {
            showLocationControls = false
            showManualLocationEditor = false
        }
    }

    // MARK: - Main Panel Layout
    private var mainPanel: some View {
        VStack(spacing: 0) {
            header

            if controller.keyboardAvailable {
                VStack(spacing: 14) {
                    if systemActive {
                        systemCard
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .move(edge: .trailing).combined(with: .opacity)))
                    } else {
                        customCard
                            .transition(.asymmetric(
                                insertion: .move(edge: .leading).combined(with: .opacity),
                                removal: .move(edge: .leading).combined(with: .opacity)))
                    }

                    // Global Power Saving Card
                    inactivityCard
                }
                .padding(14)
                .animation(Motion.smooth, value: prefs.overrideEnabled)
            } else {
                unavailableView
            }

            if !controller.keyboardAvailable {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text("App Sandbox active? Private hardware framework blocked.")
                        .font(.caption2.weight(.medium))
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }

            Divider()
            footer
        }
    }

    // MARK: - Header
    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle()
                    .fill((controller.isNightMode ? Color.indigo : Color.orange)
                        .opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: controller.isNightMode ? "moon.stars.fill" : "sun.max.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle((controller.isNightMode ? Color.indigo : Color.orange).gradient)
                    .symbolRenderingMode(.hierarchical)
                    .transition(.scale.combined(with: .opacity))
                    .id(controller.isNightMode)
            }
            .animation(Motion.bouncy, value: controller.isNightMode)

            VStack(alignment: .leading, spacing: 2) {
                Text("Lumina").font(.headline)
                HStack(spacing: 5) {
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(controller.currentStatus)
                        .font(.caption2).foregroundStyle(LuminaText.muted)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.snappy, value: controller.currentStatus)
                }
            }

            Spacer()
            ModeSwitch(isAuto: $prefs.overrideEnabled)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var statusColor: Color {
        if !controller.keyboardAvailable { return .gray }
        if controller.activePeriodName != nil { return .indigo }
        return .orange
    }

    private var locationModeTitle: String {
        controller.isNightMode ? "Nighttime" : "Daytime"
    }

    private var locationPillTint: Color {
        controller.isNightMode ? .indigo : .orange
    }

    private var locationPillAccent: Color {
        controller.isNightMode ? .blue : .yellow
    }

    private var locationPillIcon: String {
        return controller.isNightMode ? "moon.stars.fill" : "sun.max.fill"
    }

    // MARK: - Compact System Control View
    private var systemCard: some View {
        Card {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "laptopcomputer")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .frame(width: 20)
                    Text("System Control").font(.callout.weight(.semibold))
                    Spacer()
                }

                VStack(spacing: 14) {
                    BrightnessRow(
                        title: "Brightness",
                        value: $prefs.manualBrightness,
                        tint: .orange,
                        subtitle: prefs.manualAutoBrightness ? "Overridden by ambient sensor" : "Fixed level in 2% steps",
                        onEditing: { controller.previewBrightness($0) }
                    )
                    .disabled(prefs.manualAutoBrightness)
                    .opacity(prefs.manualAutoBrightness ? 0.45 : 1)

                    ToggleRow(
                        systemImage: "rays",
                        title: "Auto-Brightness",
                        subtitle: "Adjust to room lighting",
                        isOn: $prefs.manualAutoBrightness,
                        tint: .orange
                    )
                }
            }
        }
    }

    // MARK: - Expanded Custom Automations View
    private var customCard: some View {
        Card {
            VStack(spacing: 14) {
                SegmentedTabs(
                    selection: $prefs.automationTab,
                    items: [
                        (value: 0, label: "Sun Cycle", icon: "sun.horizon.fill"),
                        (value: 1, label: "Time Slots", icon: "clock.fill")
                    ],
                    tint: .indigo
                )

                Divider().opacity(0.5)

                if prefs.automationTab == 0 {
                    solarSection
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    customSection
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(Motion.smooth, value: prefs.automationTab)
        }
    }

    // MARK: - Inactivity Timer Card
    private var inactivityCard: some View {
        Card {
            VStack(spacing: 10) {
                ToggleRow(
                    systemImage: "timer",
                    title: "Inactivity Timeout",
                    subtitle: "Turn off backlight when idle",
                    isOn: $prefs.inactivityTimeoutEnabled,
                    tint: .red
                )

                if prefs.inactivityTimeoutEnabled {
                    Divider().opacity(0.5)

                    HStack {
                        Text("Timeout duration")
                            .font(.callout)
                            .foregroundColor(LuminaText.muted)
                        Spacer()
                        
                        // Custom Interactive-Hover Duration Picker!
                        TactileDurationPicker(
                            minutes: $prefs.inactivityTimeoutMinutes,
                            seconds: $prefs.inactivityTimeoutSeconds
                        )
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(Motion.smooth, value: prefs.inactivityTimeoutEnabled)
        }
    }

    // MARK: - Sun Cycle Panel
    private var solarSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Active window")
                        .font(.caption2)
                        .foregroundColor(LuminaText.muted)
                    Text(sun.activeWindowLabel)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(Motion.smooth, value: sun.activeWindowLabel)
                    Text("Backlight automation runs nightly from sunset to sunrise.")
                        .font(.caption2)
                        .foregroundColor(LuminaText.soft)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Button {
                        withAnimation(Motion.smooth) {
                            showLocationControls.toggle()
                            if !showLocationControls {
                                showManualLocationEditor = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: locationPillIcon)
                                .font(.caption.weight(.bold))
                            Text(locationModeTitle)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                                .rotationEffect(.degrees(showLocationControls ? 180 : 0))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(width: showLocationControls ? locationControlTrayWidth : nil, alignment: .leading)
                        .background(
                            Capsule()
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            locationPillTint.opacity(showLocationControls ? 0.92 : 0.84),
                                            locationPillAccent.opacity(showLocationControls ? 0.78 : 0.62)
                                        ],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 0.8)
                                )
                        )
                        .shadow(color: locationPillTint.opacity(showLocationControls ? 0.28 : 0.16), radius: 14, x: 0, y: 7)
                    }
                    .buttonStyle(.plain)

                    if showLocationControls {
                        VStack(alignment: .trailing, spacing: 8) {
                            HStack(spacing: 8) {
                                SourcePill(
                                    title: sun.needsSettings ? "Settings" : "GPS",
                                    systemImage: sun.needsSettings ? "gearshape.fill" : "location.fill",
                                    isActive: prefs.solarLocationSource == .precise,
                                    tint: .indigo
                                ) {
                                    withAnimation(Motion.bouncy) {
                                        showManualLocationEditor = false
                                        showLocationControls = false
                                    }
                                    sun.handleLocationButtonTap()
                                }

                                SourcePill(
                                    title: "Approximate",
                                    systemImage: "network",
                                    isActive: prefs.solarLocationSource == .approximate,
                                    tint: .cyan
                                ) {
                                    withAnimation(Motion.bouncy) {
                                        showManualLocationEditor = false
                                        showLocationControls = false
                                    }
                                    sun.requestApproximateLocationFromInternet()
                                }

                                SourcePill(
                                    title: "Manual",
                                    systemImage: "slider.horizontal.below.rectangle",
                                    isActive: prefs.solarLocationSource == .manual,
                                    tint: .orange
                                ) {
                                    withAnimation(Motion.bouncy) {
                                        sun.beginManualEntry()
                                        showManualLocationEditor.toggle()
                                    }
                                }
                            }
                            .frame(width: locationSourceButtonRowWidth, alignment: .trailing)
                        }
                        .padding(10)
                        .frame(width: locationControlTrayWidth, alignment: .trailing)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Color.primary.opacity(0.04))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(locationPillTint.opacity(0.14), lineWidth: 0.8)
                                )
                        )
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .topTrailing)),
                            removal: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.96, anchor: .topTrailing))
                        ))
                    }
                }
            }

            if showLocationControls && showManualLocationEditor {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        ElegantNumberField(title: "Latitude", value: $prefs.latitude)
                        ElegantNumberField(title: "Longitude", value: $prefs.longitude)
                    }

                    HStack(spacing: 10) {
                        Button("Use Manual Location") {
                            sun.useManualCoordinates()
                            withAnimation(Motion.bouncy) {
                                showManualLocationEditor = false
                                showLocationControls = false
                            }
                        }
                        .buttonStyle(TactileButtonStyle())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule()
                                .fill(Color.orange.gradient)
                                .shadow(color: Color.orange.opacity(0.22), radius: 10, x: 0, y: 4)
                        )
                        .foregroundStyle(.white)

                        Text("Reliable offline fallback")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(LuminaText.muted)
                            .lineLimit(1)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.primary.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Color.orange.opacity(0.12), lineWidth: 0.8)
                        )
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let lastError = sun.lastError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(lastError)
                        .font(.caption2)
                        .foregroundColor(LuminaText.muted)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Image(systemName: "sunrise.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Sunrise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(LuminaText.muted)
                        Text(sun.sunriseLabel)
                            .font(.subheadline)
                            .bold()
                            .opacity(sun.isLocating ? 0.55 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                HStack(spacing: 6) {
                    Image(systemName: "sunset.fill")
                        .foregroundColor(.indigo)
                    VStack(alignment: .leading) {
                        Text("Sunset")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(LuminaText.muted)
                        Text(sun.sunsetLabel)
                            .font(.subheadline)
                            .bold()
                            .opacity(sun.isLocating ? 0.55 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.04),
                                Color.white.opacity(0.015)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("NIGHTTIME BRIGHTNESS")
                    .font(.caption2)
                    .fontWeight(.black)
                    .foregroundColor(LuminaText.muted)

                BrightnessRow(
                    title: "Brightness",
                    value: $prefs.solarNightBrightness,
                    tint: .indigo,
                    subtitle: prefs.solarAutoBrightness ? "Overridden by ambient sensor" : "Applied from sunset to sunrise",
                    onEditing: { controller.previewBrightness($0) }
                )
                .disabled(prefs.solarAutoBrightness)
                .opacity(prefs.solarAutoBrightness ? 0.45 : 1)

                ToggleRow(
                    systemImage: "rays",
                    title: "Auto-Brightness",
                    subtitle: "Auto brightness at night",
                    isOn: $prefs.solarAutoBrightness,
                    tint: .indigo
                )
            }
        }
    }

    // MARK: - Custom Slots Panel
    private var customSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.callout).foregroundStyle(.indigo).frame(width: 22)
                Text("Time slots").font(.callout.weight(.semibold))
                Spacer()
                if !prefs.customPeriods.isEmpty {
                    Text("\(prefs.customPeriods.count)/3")
                        .font(.caption2.weight(.bold)).foregroundStyle(LuminaText.muted)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.primary.opacity(0.08), in: Capsule())
                }
            }

            if !prefs.customPeriods.isEmpty || isAddingNew {
                VStack(spacing: 10) {
                    ForEach(prefs.customPeriods) { period in
                        if editingID == period.id, draft != nil {
                            periodEditor(isNew: false)
                                .transition(.scale(scale: 0.96).combined(with: .opacity))
                        } else {
                            periodRow(period)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }

                    if isAddingNew, draft != nil {
                        periodEditor(isNew: true)
                            .transition(.scale(scale: 0.96).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
            }

            if !isAddingNew && editingID == nil && prefs.customPeriods.count < 3 {
                Button(action: beginAdd) {
                    ZStack {
                        Circle()
                            .fill(Color.indigo.gradient)
                            .frame(width: 38, height: 38)
                            .shadow(color: .indigo.opacity(0.4), radius: 5, x: 0, y: 2)
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(PressableStyle(scale: 0.85))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .help("Add a time slot")
            }
        }
        .animation(Motion.smooth, value: prefs.customPeriods)
        .animation(Motion.smooth, value: editingID)
        .animation(Motion.smooth, value: isAddingNew)
    }

    // MARK: - Row Layout
    private func periodRow(_ period: BrightnessPeriod) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.indigo.opacity(0.18)).frame(width: 34, height: 34)
                Image(systemName: period.useAmbient ? "rays" : "moon.fill")
                    .font(.caption).foregroundStyle(Color.indigo.opacity(0.95))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(period.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(timeStr(period.startHour, period.startMinute))
                    Image(systemName: "arrow.right").font(.system(size: 8))
                    Text(timeStr(period.endHour, period.endMinute))
                }
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(LuminaText.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            Text(period.useAmbient ? "Auto" : "\(Int((period.brightness * 100).rounded()))%")
                .font(.caption.weight(.bold)).monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Color.indigo.opacity(period.useAmbient ? 0.34 : 0.22))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.7))
                )

            Button { beginEdit(period) } label: {
                Image(systemName: "pencil").font(.caption).foregroundStyle(LuminaText.muted)
                    .frame(width: 26, height: 26)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(PressableStyle())

            Button { delete(period) } label: {
                Image(systemName: "trash").font(.caption).foregroundStyle(.red)
                    .frame(width: 26, height: 26)
                    .background(Color.red.opacity(0.1), in: Circle())
            }
            .buttonStyle(PressableStyle())
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.055))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.055), lineWidth: 0.7)
                )
        )
    }

    // MARK: - Custom Period Editor View
    private func periodEditor(isNew: Bool) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(isNew ? "New slot" : "Edit slot")
                    .font(.caption.weight(.semibold)).foregroundStyle(LuminaText.muted)
                Spacer()
                TextField("Name", text: Binding(
                    get: { draft?.name ?? "" },
                    set: { draft?.name = $0 }
                ))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.callout.weight(.medium))
                .frame(width: 150)
            }

            Divider().opacity(0.5)

            HStack(spacing: 6) {
                timeColumn(title: "Start",
                           hour: Binding(get: { draft?.startHour ?? 0 }, set: { draft?.startHour = $0 }),
                           minute: Binding(get: { draft?.startMinute ?? 0 }, set: { draft?.startMinute = $0 }))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(LuminaText.faint)
                timeColumn(title: "End",
                           hour: Binding(get: { draft?.endHour ?? 0 }, set: { draft?.endHour = $0 }),
                           minute: Binding(get: { draft?.endMinute ?? 0 }, set: { draft?.endMinute = $0 }))
            }

            BrightnessRow(
                title: "Brightness",
                value: Binding(get: { draft?.brightness ?? 0 }, set: { draft?.brightness = $0 }),
                tint: .indigo,
                onEditing: { controller.previewBrightness($0) }
            )
            .disabled(draft?.useAmbient ?? false)
            .opacity((draft?.useAmbient ?? false) ? 0.45 : 1)

            ToggleRow(
                systemImage: "rays",
                title: "Auto-Brightness",
                subtitle: "Auto brightness in this slot",
                isOn: Binding(get: { draft?.useAmbient ?? false }, set: { draft?.useAmbient = $0 }),
                tint: .indigo
            )

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Idle Timeout")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    Text("00:00 keeps backlight always on in this slot")
                        .font(.caption2)
                        .foregroundStyle(LuminaText.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                TactileDurationPicker(
                    minutes: Binding(get: { draft?.timeoutMinutes ?? 0 }, set: { draft?.timeoutMinutes = $0 }),
                    seconds: Binding(get: { draft?.timeoutSeconds ?? 0 }, set: { draft?.timeoutSeconds = $0 })
                )
            }

            if overlapWarning {
                Label(editingLimitReached ? "You can add up to 3 slots" : "This time range overlaps another slot", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                Button("Cancel", action: cancelEdit)
                    .buttonStyle(PressableStyle())
                Spacer()
                Button(action: saveEdit) {
                    Text("Save")
                        .font(.callout.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Color.indigo.gradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.indigo.opacity(0.4), lineWidth: 1)
        )
    }

    private func timeColumn(title: String, hour: Binding<Int>, minute: Binding<Int>) -> some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(LuminaText.muted)
            HStack(spacing: 2) {
                Picker("", selection: hour) {
                    ForEach(0..<24, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 54)
                Text(":").foregroundStyle(LuminaText.muted)
                Picker("", selection: minute) {
                    ForEach(0..<60, id: \.self) { Text(String(format: "%02d", $0)).tag($0) }
                }
                .labelsHidden().frame(width: 54)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions
    private func beginAdd() {
        guard prefs.customPeriods.count < 3 else {
            withAnimation(Motion.snappy) { overlapWarning = true }
            return
        }
        let candidate = suggestedNewPeriod()
        draft = candidate
        overlapWarning = false
        withAnimation(Motion.smooth) {
            editingID = nil
            isAddingNew = true
        }
    }

    private func beginEdit(_ period: BrightnessPeriod) {
        draft = period
        overlapWarning = false
        withAnimation(Motion.smooth) {
            isAddingNew = false
            editingID = period.id
        }
    }

    private func saveEdit() {
        guard let d = draft else { return }
        let success: Bool = isAddingNew ? prefs.addPeriod(d) : prefs.updatePeriod(d)
        if success {
            withAnimation(Motion.smooth) {
                editingID = nil
                isAddingNew = false
                draft = nil
                overlapWarning = false
            }
        } else {
            withAnimation(Motion.snappy) { overlapWarning = true }
        }
    }

    private func cancelEdit() {
        withAnimation(Motion.smooth) {
            editingID = nil
            isAddingNew = false
            draft = nil
            overlapWarning = false
        }
    }

    private func delete(_ period: BrightnessPeriod) {
        withAnimation(Motion.smooth) { prefs.removePeriod(id: period.id) }
    }

    private var editingLimitReached: Bool {
        isAddingNew && prefs.customPeriods.count >= 3
    }

    private func suggestedNewPeriod() -> BrightnessPeriod {
        let candidates = [(9, 11), (12, 14), (15, 17), (8, 9), (13, 14), (16, 17)]
        for (s, e) in candidates {
            let p = BrightnessPeriod(name: "Period", startHour: s, startMinute: 0,
                                     endHour: e, endMinute: 0, brightness: 0.5,
                                     timeoutMinutes: 0, timeoutSeconds: 0)
            if prefs.overlappingPeriod(with: p) == nil { return p }
        }
        return BrightnessPeriod(name: "Period", startHour: 9, startMinute: 0,
                                endHour: 11, endMinute: 0, brightness: 0.5,
                                timeoutMinutes: 0, timeoutSeconds: 0)
    }

    private var unavailableView: some View {
        VStack(spacing: 8) {
            Image(systemName: "keyboard.badge.exclamationmark")
                .font(.largeTitle).foregroundStyle(LuminaText.muted)
            Text("No keyboard backlight detected")
                .font(.callout.weight(.medium))
            Text("This Mac has no controllable keyboard backlight.")
                .font(.caption).foregroundStyle(LuminaText.muted)
                .multilineTextAlignment(.center)
        }
        .padding(28)
    }

    private var footer: some View {
        HStack {
            Button(action: { NSApplication.shared.terminate(nil) }) {
                Label("Quit", systemImage: "power")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.red.opacity(0.12), in: Capsule())
                    .foregroundStyle(.red)
            }
            .buttonStyle(PressableStyle())
            Spacer()
            
            HStack(spacing: 8) {
                // Tutorial Re-open Book Trigger
                Button(action: {
                    withAnimation(Motion.smooth) {
                        onboardingPage = 0
                        prefs.hasCompletedOnboarding = false
                    }
                }) {
                    Image(systemName: "book.closed.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(LuminaText.muted)
                        .frame(width: 22, height: 22)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(PressableStyle())
                .help("Reopen Setup Onboarding")
                
                Text("v4.0").font(.caption2).foregroundStyle(LuminaText.faint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func timeStr(_ h: Int, _ m: Int) -> String { String(format: "%02d:%02d", h, m) }

    private func timeoutStr(_ minutes: Int, _ seconds: Int) -> String {
        "\(String(format: "%02d", minutes))m \(String(format: "%02d", seconds))s"
    }

    // MARK: - 6.2 ONBOARDING INTERACTIVE WIZARD
    private var onboardingPanel: some View {
        VStack(spacing: 16) {
            // Header Branding
            HStack(spacing: 8) {
                Image(systemName: "keyboard.badge.ellipsis")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Lumina Setup")
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text("\(onboardingPage + 1) / 5")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(LuminaText.muted)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            Divider()

            // Dynamic Step Rendering with side transitions
            ZStack {
                if onboardingPage == 0 {
                    onboardingWelcomeStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 1 {
                    onboardingLocationStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 2 {
                    onboardingStartupBrightnessStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else if onboardingPage == 3 {
                    onboardingHardwareStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    onboardingPowerStep
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(height: 270)
            .padding(.horizontal, 18)
            .animation(Motion.smooth, value: onboardingPage)

            Divider()

            // Bottom Navigation Footer
            HStack {
                if onboardingPage > 0 {
                    Button("Back") {
                        withAnimation(Motion.smooth) { onboardingPage -= 1 }
                    }
                    .buttonStyle(PressableStyle())
                }
                
                Spacer()

                Button(action: nextOnboardingStep) {
                    Text(onboardingPage == 4 ? "Complete Setup" : "Next")
                        .fontWeight(.bold)
                        .padding(.horizontal, 18).padding(.vertical, 6)
                        .background(Color.indigo.gradient, in: Capsule())
                        .foregroundColor(.white)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 16)
        }
    }

    private func nextOnboardingStep() {
        if onboardingPage < 4 {
            withAnimation(Motion.smooth) {
                onboardingPage += 1
            }
        } else {
            // Write completed state to Preferences/UserDefaults
            withAnimation(Motion.smooth) {
                prefs.hasCompletedOnboarding = true
                controller.startMonitoring() // Recalibrate with fresh defaults
            }
        }
    }

    // Onboarding Step 1: Welcome
    private var onboardingWelcomeStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
                .symbolRenderingMode(.hierarchical)
                .padding(.top, 10)

            Text("Welcome to Lumina")
                .font(.title3.weight(.bold))

            Text("This utility allows you to automate your MacBook keyboard backlight, keeping it bright at night and fully off during the day to protect and extend its lifespan.")
                .font(.caption)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
    }

    // Onboarding Step 2: Location Configuration
    private var onboardingLocationStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 38))
                .foregroundColor(.indigo)

            Text("Sun Cycle Calibration")
                .font(.callout.weight(.bold))

            Text("Sunrise and sunset calculations run entirely offline. Tap below to authorize CoreLocation services so Lumina can use your current location.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            Button(action: {
                sun.setAutomaticLocationEnabled(true)
            }) {
                Label(sun.isAuthorized ? "Location Active" : "Authorize GPS",
                      systemImage: sun.isAuthorized ? "checkmark.circle.fill" : "location.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(sun.isAuthorized ? .green : .white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(sun.isAuthorized ? Color.green.opacity(0.12) : Color.indigo, in: Capsule())
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 4)
        }
    }

    // Onboarding Step 3: Default Startup Brightness
    private var onboardingStartupBrightnessStep: some View {
        VStack(spacing: 12) {
            Image(systemName: "keyboard.badge.ellipsis")
                .font(.system(size: 38))
                .foregroundColor(.orange)
                .padding(.top, 10)

            Text("Default Startup Brightness")
                .font(.callout.weight(.bold))

            Text("Choose the default brightness Lumina should apply to your keyboard immediately when the app starts.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            BrightnessRow(
                title: "Startup Level",
                value: $prefs.defaultStartupBrightness,
                tint: .orange,
                onEditing: { controller.previewBrightness($0) }
            )
            .padding(.top, 8)
        }
    }

    // Onboarding Step 4: Hardware Link Verification
    private var onboardingHardwareStep: some View {
        VStack(spacing: 12) {
            Image(systemName: controller.keyboardAvailable ? "keyboard.fill" : "keyboard.badge.exclamationmark")
                .font(.system(size: 38))
                .foregroundColor(controller.keyboardAvailable ? .green : .orange)

            Text("Private Hardware Interface")
                .font(.callout.weight(.bold))

            Text("Lumina uses macOS's private CoreBrightness framework to bypass standard sandbox locks. This allows direct hardware manipulation.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            // Diagnostic Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(controller.keyboardAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(controller.keyboardAvailable ? "Hardware Detected Successfully" : "Sandbox Lock - check capabilities")
                    .font(.caption2.weight(.bold))
                    .foregroundColor(controller.keyboardAvailable ? .green : .orange)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill((controller.keyboardAvailable ? Color.green : Color.orange).opacity(0.1)))
        }
    }

    // Onboarding Step 5: Power Saving Tutorial
    private var onboardingPowerStep: some View {
        VStack(spacing: 10) {
            Image(systemName: "hourglass.badge.plus")
                .font(.system(size: 38))
                .foregroundColor(.red)

            Text("Inactivity Power Saver")
                .font(.callout.weight(.bold))

            Text("Hover over the inactive readout pill to open the high-fidelity inertial scroll wheel, letting you choose exactly how many minutes or seconds to wait before shutting down.")
                .font(.caption2)
                .foregroundColor(LuminaText.muted)
                .multilineTextAlignment(.center)

            // Mini Interactive Demo
            HStack(spacing: 8) {
                Text("Timeout:")
                    .font(.caption2)
                    .foregroundColor(LuminaText.muted)
                TactileDurationPicker(
                    minutes: .constant(0),
                    seconds: .constant(30)
                )
            }
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
    }
}

// MARK: - 7. ACTIVE HOVER DURATION PICKER
struct TactileDurationPicker: View {
    @Binding var minutes: Int
    @Binding var seconds: Int
    
    @State private var isHovered = false
    
    var body: some View {
        HStack {
            Spacer()
            ZStack {
                if !isHovered {
                    // Static clean digital layout (XXm : XXs)
                    HStack(spacing: 4) {
                        Text(String(format: "%02dm", minutes))
                        Text(":")
                        Text(String(format: "%02ds", seconds))
                    }
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .transition(.scale.combined(with: .opacity))
                } else {
                    // Aligned cylindrical pickers with smooth spring expansion
                    HStack(spacing: 8) {
                        ScrollWheelPicker(selection: $minutes, range: 0...59, suffix: "m")
                        Text(":")
                            .font(.title2)
                            .foregroundColor(LuminaText.muted)
                        ScrollWheelPicker(selection: $seconds, range: 0...59, suffix: "s")
                    }
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
                }
            }
            .frame(height: isHovered ? 110 : 28)
            .animation(Motion.smooth, value: isHovered)
            .contentShape(Rectangle())
            .onHover { hovering in
                withAnimation(Motion.smooth) {
                    isHovered = hovering
                }
            }
        }
    }
}

// MARK: - 8. HIGH-FIDELITY SCROLL WHEEL PICKER (iPhone Timer Feel with Inertial Momentum)
struct ScrollWheelPicker: View {
    @Binding var selection: Int
    let range: ClosedRange<Int>
    var suffix: String

    private let itemHeight: CGFloat = 22
    private let visibleRows: Int = 5
    private let width: CGFloat = 55

    @State private var dragOffset: CGFloat = 0
    @State private var wheelNudge: CGFloat = 0
    @State private var isInteracting = false

    private var clampedSelection: Int {
        clamp(selection)
    }

    private var previewSelection: Int {
        clamp(clampedSelection + dragStep)
    }

    private var dragStep: Int {
        Int((-dragOffset / itemHeight).rounded())
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.05),
                            Color.black.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(isInteracting ? 0.11 : 0.07))
                .frame(height: itemHeight)
                .shadow(color: .white.opacity(isInteracting ? 0.08 : 0), radius: 8)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                ForEach((-2...2), id: \.self) { offset in
                    let value = previewSelection + offset
                    wheelRow(value: value, offset: offset)
                }
            }
            .offset(y: dragOffset - CGFloat(dragStep) * itemHeight + wheelNudge)
            .animation(Motion.tactile, value: previewSelection)
            .animation(Motion.tactile, value: wheelNudge)

            WheelEventCapture { delta in
                applyScroll(delta)
            } onDragChanged: { offset in
                isInteracting = true
                dragOffset = offset
            } onDragEnded: { offset in
                let step = Int((-offset / itemHeight).rounded())
                setSelection(clampedSelection + step)
                withAnimation(Motion.tactile) {
                    dragOffset = 0
                    wheelNudge = 0
                    isInteracting = false
                }
            }
        }
        .frame(width: width, height: itemHeight * CGFloat(visibleRows))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.8)
        )
        .scaleEffect(isInteracting ? 0.985 : 1)
        .animation(Motion.tactile, value: isInteracting)
        .onAppear {
            setSelection(selection)
        }
    }

    private func wheelRow(value: Int, offset: Int) -> some View {
        let isValid = range.contains(value)
        let isSelected = offset == 0 && isValid

        return Text(isValid ? "\(value)\(suffix)" : "")
            .font(.system(size: isSelected ? 14 : 11, weight: isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? .primary : .secondary)
            .opacity(isSelected ? 1.0 : (abs(offset) == 1 ? 0.65 : 0.25))
            .scaleEffect(isSelected ? 1.15 : (abs(offset) == 1 ? 0.9 : 0.75))
            .blur(radius: isSelected ? 0 : (abs(offset) == 1 ? 0.1 : 0.35))
            .monospacedDigit()
            .frame(width: width, height: itemHeight)
            .contentShape(Rectangle())
            .onTapGesture {
                if isValid {
                    setSelection(value)
                }
            }
    }

    private func applyScroll(_ delta: CGFloat) {
        let step = delta > 0 ? -1 : 1
        let nudge = delta > 0 ? itemHeight * 0.34 : -itemHeight * 0.34
        withAnimation(Motion.tactile) {
            isInteracting = true
            wheelNudge = nudge
        }
        setSelection(clampedSelection + step)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.11) {
            withAnimation(Motion.rebound) {
                wheelNudge = 0
                isInteracting = false
            }
        }
    }

    private func setSelection(_ value: Int) {
        let next = clamp(value)
        if selection != next {
            selection = next
        }
    }

    private func clamp(_ value: Int) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}

private struct WheelEventCapture: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void
    var onDragChanged: (CGFloat) -> Void
    var onDragEnded: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollCaptureView {
        let view = ScrollCaptureView()
        view.onScroll = onScroll
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: ScrollCaptureView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }

    final class ScrollCaptureView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        var onDragChanged: ((CGFloat) -> Void)?
        var onDragEnded: ((CGFloat) -> Void)?
        private var accumulatedDelta: CGFloat = 0
        private var dragStartY: CGFloat?
        private let threshold: CGFloat = 12

        override var acceptsFirstResponder: Bool { true }

        override func scrollWheel(with event: NSEvent) {
            accumulatedDelta += event.scrollingDeltaY

            while abs(accumulatedDelta) >= threshold {
                onScroll?(accumulatedDelta)
                accumulatedDelta -= threshold * (accumulatedDelta > 0 ? 1 : -1)
            }
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            dragStartY = convert(event.locationInWindow, from: nil).y
        }

        override func mouseDragged(with event: NSEvent) {
            guard let dragStartY else { return }
            let currentY = convert(event.locationInWindow, from: nil).y
            onDragChanged?(currentY - dragStartY)
        }

        override func mouseUp(with event: NSEvent) {
            guard let dragStartY else { return }
            let currentY = convert(event.locationInWindow, from: nil).y
            onDragEnded?(currentY - dragStartY)
            self.dragStartY = nil
        }
    }
}

// MARK: - 9. MOTION PHYSICS & ANIMATION PRESETS
enum Motion {
    static let bouncy = Animation.spring(response: 0.32, dampingFraction: 0.58)
    static let smooth = Animation.spring(response: 0.42, dampingFraction: 0.82)
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.68)
    static let tactile = Animation.interpolatingSpring(stiffness: 310, damping: 23)
    static let rebound = Animation.interpolatingSpring(stiffness: 220, damping: 16)
}

// MARK: - 10. ADDITIONAL CUSTOM UI WRAPPERS
struct BackdropGradient: View {
    var isNight: Bool
    var body: some View {
        LinearGradient(
            colors: isNight
                ? [Color.indigo.opacity(0.10), Color.clear]
                : [Color.orange.opacity(0.08), Color.clear],
            startPoint: .top, endPoint: .center
        )
        .ignoresSafeArea()
        .animation(Motion.smooth, value: isNight)
    }
}

struct PremiumToggle: View {
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    private let width: CGFloat = 44
    private let height: CGFloat = 26
    private let inset: CGFloat = 3

    var body: some View {
        let knob = height - inset * 2
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn
                      ? AnyShapeStyle(tint.gradient)
                      : AnyShapeStyle(Color.primary.opacity(0.14)))
                .overlay(
                    Capsule().strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )

            Circle()
                .fill(.white)
                .frame(width: knob, height: knob)
                .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
                .padding(inset)
        }
        .frame(width: width, height: height)
        .contentShape(Capsule())
        .onTapGesture {
            withAnimation(Motion.bouncy) { isOn.toggle() }
        }
        .animation(Motion.bouncy, value: isOn)
    }
}

struct StatusOrb: View {
    var title: String
    var subtitle: String
    var tint: Color

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.caption2.weight(.medium))
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(tint.opacity(0.22), lineWidth: 0.8)
                )
        )
    }
}

struct SourcePill: View {
    var title: String
    var systemImage: String
    var isActive: Bool
    var tint: Color
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
            }
            .frame(width: 42, height: 34)
            .foregroundStyle(isActive ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .background(
                Capsule()
                    .fill(isActive ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(Color.white.opacity(0.04)))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isActive ? tint.opacity(0.18) : Color.white.opacity(0.05), lineWidth: 0.8)
            )
        }
        .buttonStyle(TactileButtonStyle())
    }
}

struct ElegantNumberField: View {
    var title: String
    @Binding var value: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(LuminaText.muted)
            TextField(title, value: $value, format: .number.precision(.fractionLength(4)))
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.035))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.8)
                        )
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BrightnessSlider: View {
    @Binding var value: Double
    var tint: Color
    var step: Double = 0.02
    var onEditing: ((Double) -> Void)? = nil

    @State private var dragging = false

    private let trackHeight: CGFloat = 7
    private let thumb: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumb, 1)
            let clamped = min(max(value, 0), 1)
            let x = CGFloat(clamped) * usable

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.12))
                    .frame(height: trackHeight)

                Capsule()
                    .fill(tint.gradient)
                    .frame(width: x + thumb / 2, height: trackHeight)

                Circle()
                    .fill(.white)
                    .frame(width: thumb, height: thumb)
                    .shadow(color: .black.opacity(0.28), radius: dragging ? 5 : 3, x: 0, y: 1)
                    .overlay(
                        Circle().fill(tint).frame(width: 7, height: 7)
                    )
                    .scaleEffect(dragging ? 1.22 : 1.0)
                    .offset(x: x)
            }
            .frame(height: thumb)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        if !dragging { withAnimation(Motion.snappy) { dragging = true } }
                        let raw = (g.location.x - thumb / 2) / usable
                        let snapped = (min(max(raw, 0), 1) / step).rounded() * step
                        if abs(snapped - value) > 0.0001 {
                            value = min(max(snapped, 0), 1)
                            onEditing?(value)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(Motion.bouncy) { dragging = false }
                    }
            )
        }
        .frame(height: thumb)
    }
}

struct BrightnessRow: View {
    var title: String
    @Binding var value: Double
    var tint: Color
    var subtitle: String? = nil
    var onEditing: ((Double) -> Void)? = nil

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(title).font(.callout.weight(.medium))
                Spacer()
                Text(value == 0 ? "Off" : "\(Int((value * 100).rounded()))%")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(value == 0 ? LuminaText.soft : .primary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(Motion.snappy, value: value)
            }
            HStack(spacing: 10) {
                Image(systemName: "sun.min")
                    .font(.caption2)
                    .foregroundStyle(LuminaText.faint)
                BrightnessSlider(value: $value, tint: tint, onEditing: onEditing)
                Image(systemName: "sun.max.fill")
                    .font(.caption2)
                    .foregroundStyle(LuminaText.faint)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(LuminaText.soft)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct ToggleRow: View {
    var systemImage: String
    var title: String
    var subtitle: String?
    @Binding var isOn: Bool
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(LuminaText.soft))
                .frame(width: 22)
                .animation(Motion.snappy, value: isOn)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(LuminaText.soft)
                }
            }
            Spacer(minLength: 8)
            PremiumToggle(isOn: $isOn, tint: tint)
        }
    }
}

struct SegmentedTabs<T: Hashable>: View {
    @Binding var selection: T
    var items: [(value: T, label: String, icon: String)]
    var tint: Color = .accentColor

    @Namespace private var ns

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.value) { item in
                let selected = item.value == selection
                Button {
                    withAnimation(Motion.smooth) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: item.icon).font(.caption2)
                        Text(item.label).font(.caption.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(LuminaText.muted))
                    .background {
                        if selected {
                            Capsule()
                                .fill(tint.gradient)
                                .matchedGeometryEffect(id: "tab", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct ModeSwitch: View {
    @Binding var isAuto: Bool
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            segment(label: "System", icon: "laptopcomputer",
                    active: !isAuto, tint: .orange) {
                if isAuto { withAnimation(Motion.smooth) { isAuto = false } }
            }
            segment(label: "Periodic", icon: "slider.horizontal.3",
                    active: isAuto, tint: .indigo) {
                if !isAuto { withAnimation(Motion.smooth) { isAuto = true } }
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private func segment(label: String, icon: String, active: Bool,
                         tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(label).font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .foregroundStyle(active ? AnyShapeStyle(.white) : AnyShapeStyle(LuminaText.muted))
            .background {
                if active {
                    Capsule().fill(tint.gradient)
                        .matchedGeometryEffect(id: "modeseg", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct Card<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .padding(14)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 3)
    }
}

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.92
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

struct TactileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(Motion.bouncy, value: configuration.isPressed)
    }
}
