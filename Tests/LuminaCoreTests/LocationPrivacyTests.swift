import XCTest
import CoreLocation
@testable import LuminaCore

final class LocationPrivacyTests: XCTestCase {
    func testMacGrantedAuthorizationStateIsAccepted() {
        XCTAssertTrue(LocationAuthorization.isAuthorized(.authorizedAlways))
        XCTAssertTrue(LocationAuthorization.isAuthorized(.authorized))
    }

    func testUngrantedAuthorizationStatesAreRejected() {
        for status in [CLAuthorizationStatus.notDetermined, .denied, .restricted] {
            XCTAssertFalse(LocationAuthorization.isAuthorized(status))
        }
    }
    func testRejectsInvalidCoordinates() {
        for (lat, lon) in [(91.0, 0.0), (0, -181), (.nan, 0), (0, .infinity)] {
            XCTAssertNil(LocationCoordinate(latitude: lat, longitude: lon))
        }
        XCTAssertNotNil(LocationCoordinate(latitude: 90, longitude: 180))
        XCTAssertNotNil(LocationCoordinate(latitude: 0, longitude: 0))
    }

    func testStoredCoordinateIsRoundedToRegion() throws {
        let coordinate = try XCTUnwrap(LocationCoordinate(latitude: 52.520008, longitude: 13.404954))
        XCTAssertEqual(coordinate.roundedForStorage.latitude, 52.5)
        XCTAssertEqual(coordinate.roundedForStorage.longitude, 13.4)
    }

    func testStartupNeverRequestsIPLocationOrPromptsForPermission() {
        for source in [SolarLocationSource.manual, .approximate] {
            for authorized in [false, true] {
                XCTAssertEqual(LocationStartupAction.resolve(source: source, isAuthorized: authorized), .cachedCoordinates)
            }
        }
        XCTAssertEqual(LocationStartupAction.resolve(source: .precise, isAuthorized: false), .cachedCoordinates)
        XCTAssertEqual(LocationStartupAction.resolve(source: .precise, isAuthorized: true), .refreshAuthorizedMacLocation)
    }

    func testValidLookupResponseDiscardsUnneededFieldsAndRounds() throws {
        let data = Data(#"{"latitude":52.520008,"longitude":13.404954,"city":"Berlin","ip":"192.0.2.1"}"#.utf8)
        let coordinate = try LocationResponseParser.parse(data, statusCode: 200)
        XCTAssertEqual(coordinate.latitude, 52.5)
        XCTAssertEqual(coordinate.longitude, 13.4)
    }

    func testLookupRejectsBadStatusEvenWithValidCoordinates() {
        let data = Data(#"{"latitude":52.5,"longitude":13.4}"#.utf8)
        for status in [301, 403, 429, 500] {
            XCTAssertThrowsError(try LocationResponseParser.parse(data, statusCode: status)) {
                XCTAssertEqual($0 as? LocationLookupError, .serviceUnavailable)
            }
        }
    }

    func testLookupRejectsMalformedMissingAndOutOfRangeCoordinates() {
        for json in ["not json", "{}", #"{"latitude":52.5}"#,
                     #"{"latitude":91,"longitude":13}"#, #"{"latitude":"52.5","longitude":13}"#,
                     #"{"error":true,"latitude":52.5,"longitude":13}"#] {
            XCTAssertThrowsError(try LocationResponseParser.parse(Data(json.utf8), statusCode: 200))
        }
    }

    func testLookupRejectsOversizedResponses() {
        XCTAssertThrowsError(try LocationResponseParser.parse(Data(repeating: 32, count: 16_385), statusCode: 200)) {
            XCTAssertEqual($0 as? LocationLookupError, .responseTooLarge)
        }
    }
}
