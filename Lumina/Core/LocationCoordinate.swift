import Foundation

struct LocationCoordinate: Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude
        self.longitude = longitude
    }

    // Solar scheduling needs a region, not a street address. About 11 km of latitude.
    var roundedForStorage: LocationCoordinate {
        LocationCoordinate(latitude: (latitude * 10).rounded() / 10,
                           longitude: (longitude * 10).rounded() / 10)!
    }
}

enum LocationStartupAction: Equatable {
    case cachedCoordinates
    case refreshAuthorizedMacLocation

    static func resolve(source: SolarLocationSource, isAuthorized: Bool) -> Self {
        source == .precise && isAuthorized ? .refreshAuthorizedMacLocation : .cachedCoordinates
    }
}

enum LocationLookupError: Error, Equatable, LocalizedError {
    case invalidResponse
    case serviceUnavailable
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "The location service returned invalid coordinates. Try manual location."
        case .serviceUnavailable: return "The location service is unavailable. Try again later or use manual location."
        case .responseTooLarge: return "The location service returned an unexpected response. Try manual location."
        }
    }
}

enum LocationResponseParser {
    static let maximumResponseBytes = 16_384

    private struct Response: Decodable {
        let latitude: Double?
        let longitude: Double?
        let error: Bool?
    }

    static func parse(_ data: Data, statusCode: Int) throws -> LocationCoordinate {
        guard statusCode == 200 else { throw LocationLookupError.serviceUnavailable }
        guard data.count <= maximumResponseBytes else { throw LocationLookupError.responseTooLarge }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              response.error != true,
              let latitude = response.latitude, let longitude = response.longitude,
              let coordinate = LocationCoordinate(latitude: latitude, longitude: longitude) else {
            throw LocationLookupError.invalidResponse
        }
        return coordinate.roundedForStorage
    }
}
