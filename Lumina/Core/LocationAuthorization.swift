import CoreLocation

enum LocationAuthorization {
    static func isAuthorized(_ status: CLAuthorizationStatus) -> Bool {
        // Native macOS has one granted state. The old .authorized spelling is
        // an alias of .authorizedAlways; .authorizedWhenInUse is iOS-only.
        status == .authorizedAlways
    }
}
