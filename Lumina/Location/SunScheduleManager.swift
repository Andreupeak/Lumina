import AppKit
import CoreLocation
import Combine

@MainActor
final class SunScheduleManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SunScheduleManager()

    private let locationManager = CLLocationManager()
    private var locationTimeoutWorkItem: DispatchWorkItem?
    private var approximateTask: Task<Void, Never>?
    private var approximateRequestID: UUID?
    private var lastSolarRefreshKey: String?
    private var events: SolarEvents?

    @Published private(set) var isAuthorized = false
    @Published private(set) var lastError: String?
    @Published private(set) var isLocating = false
    @Published private(set) var isFetchingApproximateLocation = false
    @Published private(set) var sunrise: Date?
    @Published private(set) var sunset: Date?
    @Published private(set) var solarCondition: SolarEvents.Condition?

    var isNighttime: Bool? { events?.isNight(at: Date()) }
    var sunriseLabel: String { formatTime(sunrise) }
    var sunsetLabel: String { formatTime(sunset) }

    var activeWindowLabel: String {
        if isLocating { return "Finding Mac location…" }
        if isFetchingApproximateLocation { return "Looking up IP location…" }
        switch solarCondition {
        case .polarDay: return "Daylight all day"
        case .polarNight: return "Night all day"
        case .normal: return "\(sunsetLabel) – \(sunriseLabel)"
        case nil: return "Choose a location"
        }
    }

    var locationLabel: String {
        guard Preferences.shared.hasSavedLocation else { return "No saved location" }
        switch Preferences.shared.solarLocationSource {
        case .precise: return "Mac location"
        case .approximate: return "IP estimate (saved)"
        case .manual: return "Manual location"
        }
    }

    var needsSettings: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    override private init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        updateAuthorization()
        refreshSolarTimes()
    }

    func refreshLocationOnceAtStartup() {
        updateAuthorization()
        let action = LocationStartupAction.resolve(source: Preferences.shared.solarLocationSource,
                                                    isAuthorized: isAuthorized)
        if Preferences.shared.hasCompletedOnboarding, action == .refreshAuthorizedMacLocation {
            requestMacLocation()
        } else {
            refreshSolarTimesIfNeeded(force: true)
        }
    }

    func requestMacLocation() {
        cancelPendingRequests()
        Preferences.shared.solarLocationSource = .precise
        lastError = nil
        guard !AppRuntime.isUITesting || AppRuntime.testsRealMacLocation else {
            lastError = "Mac location is simulated in UI test mode. Use manual coordinates."
            return
        }
        // Read the delegate-backed authorization status. Synchronous
        // locationServicesEnabled() queries can block the UI's main thread.
        switch locationManager.authorizationStatus {
        case .authorizedAlways:
            isLocating = true
            if let cached = locationManager.location,
               cached.horizontalAccuracy >= 0, abs(cached.timestamp.timeIntervalSinceNow) <= 300 {
                applyMacLocation(cached)
                return
            }
            beginLocationTimeout()
            locationManager.requestLocation()
        case .notDetermined:
            isLocating = true
            beginLocationTimeout(waitingForAuthorization: true)
            // A menu-bar app may be inactive when its button is pressed. Bring
            // it forward so macOS can present the authorization request.
            NSApp.activate()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isLocating,
                      Preferences.shared.solarLocationSource == .precise else { return }
                self.locationManager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            lastError = "Location access is denied. Open System Settings or enter coordinates manually."
        @unknown default:
            lastError = "Mac location is unavailable. Enter coordinates manually."
        }
    }

    @discardableResult
    func useManualCoordinates(latitude: Double, longitude: Double) -> Bool {
        guard LocationCoordinate(latitude: latitude, longitude: longitude) != nil else {
            lastError = "Latitude must be −90 to 90 and longitude −180 to 180."
            return false
        }
        cancelPendingRequests()
        Preferences.shared.solarLocationSource = .manual
        Preferences.shared.setCoordinates(latitude: latitude, longitude: longitude)
        lastError = nil
        refreshSolarTimes()
        AutoBacklightController.shared.evaluateAndApply()
        return true
    }

    func beginManualEntry() {
        cancelPendingRequests()
        Preferences.shared.solarLocationSource = .manual
        lastError = nil
    }

    // Called only by the user's explicit IP lookup confirmation. Never a fallback.
    func requestApproximateLocationFromInternet() {
        cancelPendingRequests()
        Preferences.shared.solarLocationSource = .approximate
        isFetchingApproximateLocation = true
        lastError = nil
        if AppRuntime.isUITesting {
            Preferences.shared.setCoordinates(latitude: 52.5, longitude: 13.4)
            isFetchingApproximateLocation = false
            refreshSolarTimes()
            AutoBacklightController.shared.evaluateAndApply()
            return
        }
        let requestID = UUID()
        approximateRequestID = requestID
        approximateTask = Task { [weak self] in
            do {
                let coordinate = try await LocationLookupClient.fetchCoordinates()
                guard let self, !Task.isCancelled, self.approximateRequestID == requestID,
                      Preferences.shared.solarLocationSource == .approximate else { return }
                self.isFetchingApproximateLocation = false
                self.approximateRequestID = nil
                self.approximateTask = nil
                Preferences.shared.setCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
                self.refreshSolarTimes()
                AutoBacklightController.shared.evaluateAndApply()
            } catch {
                guard let self, !Task.isCancelled, self.approximateRequestID == requestID else { return }
                self.isFetchingApproximateLocation = false
                self.approximateRequestID = nil
                self.approximateTask = nil
                self.lastError = (error as? LocationLookupError)?.errorDescription
                    ?? "IP lookup failed. Check your connection or enter coordinates manually."
            }
        }
    }

    func clearSavedLocation() {
        cancelPendingRequests()
        Preferences.shared.clearLocation()
        lastError = nil
        refreshSolarTimes()
        AutoBacklightController.shared.evaluateAndApply()
    }

    func cancelPendingRequests() {
        approximateRequestID = nil
        approximateTask?.cancel()
        approximateTask = nil
        locationTimeoutWorkItem?.cancel()
        locationTimeoutWorkItem = nil
        locationManager.stopUpdatingLocation()
        isLocating = false
        isFetchingApproximateLocation = false
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }

    func refreshSolarTimes() {
        let prefs = Preferences.shared
        events = prefs.hasSavedLocation
            ? SolarCalculator.calculateSunriseSunset(latitude: prefs.latitude, longitude: prefs.longitude) : nil
        sunrise = events?.sunrise
        sunset = events?.sunset
        solarCondition = events?.condition
        lastSolarRefreshKey = refreshKey
    }

    private var refreshKey: String {
        "\(Calendar.current.startOfDay(for: Date()).timeIntervalSince1970)|\(TimeZone.current.identifier)|\(TimeZone.current.secondsFromGMT())"
    }

    func refreshSolarTimesIfNeeded(force: Bool = false) {
        if force || lastSolarRefreshKey != refreshKey { refreshSolarTimes() }
    }

    private func beginLocationTimeout(waitingForAuthorization: Bool = false) {
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.isLocating else { return }
            self.cancelPendingRequests()
            self.lastError = waitingForAuthorization
                ? "Location permission is still pending. Bring Lumina to the front and try Mac Location again, or enter coordinates manually."
                : "Your Mac did not return a location. Try again or enter coordinates manually."
        }
        locationTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + (waitingForAuthorization ? 60 : 15), execute: workItem)
    }

    private func formatTime(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }

    private func updateAuthorization() {
        isAuthorized = LocationAuthorization.isAuthorized(locationManager.authorizationStatus)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorization()
        // Initial delegate callbacks and later permission changes must not select a
        // source or start a request unless the user is waiting for this request.
        guard isLocating, Preferences.shared.solarLocationSource == .precise else { return }
        if isAuthorized {
            requestMacLocation()
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            cancelPendingRequests()
            lastError = "Location access is denied. Use System Settings or manual coordinates."
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isLocating, Preferences.shared.solarLocationSource == .precise,
              let location = locations.last, location.horizontalAccuracy >= 0,
              abs(location.timestamp.timeIntervalSinceNow) <= 300 else { return }
        applyMacLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard isLocating, Preferences.shared.solarLocationSource == .precise else { return }
        cancelPendingRequests()
        lastError = "Mac location could not be determined. Try again or enter coordinates manually."
    }

    private func applyMacLocation(_ location: CLLocation) {
        guard Preferences.shared.setCoordinates(latitude: location.coordinate.latitude,
                                                longitude: location.coordinate.longitude) else { return }
        cancelPendingRequests()
        lastError = nil
        refreshSolarTimes()
        AutoBacklightController.shared.evaluateAndApply()
    }
}
