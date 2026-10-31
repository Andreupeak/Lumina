import XCTest
@testable import LuminaCore

private final class StubLocationProtocol: URLProtocol, @unchecked Sendable {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var response = (status: 200, data: Data(), headers: [String: String]())
        var request: URLRequest?
    }
    private static let state = State()

    static func configure(status: Int, data: Data, headers: [String: String]) {
        state.lock.lock()
        defer { state.lock.unlock() }
        state.response = (status, data, headers)
        state.request = nil
    }

    static var lastRequest: URLRequest? {
        state.lock.lock()
        defer { state.lock.unlock() }
        return state.request
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.state.lock.lock()
        Self.state.request = request
        let fixture = Self.state.response
        Self.state.lock.unlock()
        let response = HTTPURLResponse(url: request.url!, statusCode: fixture.status,
                                       httpVersion: "HTTP/1.1", headerFields: fixture.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: fixture.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

final class LocationLookupClientTests: XCTestCase {
    private func configuration(status: Int = 200, body: Data = Data(#"{"latitude":52.52,"longitude":13.405}"#.utf8),
                               headers: [String: String] = [:]) -> URLSessionConfiguration {
        StubLocationProtocol.configure(status: status, data: body, headers: headers)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubLocationProtocol.self]
        return configuration
    }

    func testTransportUsesFixedHTTPSURLAndGenericRequestMetadata() async throws {
        let coordinate = try await LocationLookupClient.fetchCoordinates(configuration: configuration())
        XCTAssertEqual(coordinate.latitude, 52.5)
        XCTAssertEqual(coordinate.longitude, 13.4)
        let request = try XCTUnwrap(StubLocationProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://ipapi.co/json/")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "Lumina")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.httpBody)
        XCTAssertEqual(request.timeoutInterval, 12)
    }

    func testTransportRejectsNonSuccessAndRedirectResponses() async {
        for status in [301, 302, 403, 429, 500] {
            do {
                _ = try await LocationLookupClient.fetchCoordinates(configuration: configuration(status: status))
                XCTFail("Accepted HTTP \(status)")
            } catch {
                XCTAssertEqual(error as? LocationLookupError, .serviceUnavailable)
            }
        }
    }

    func testTransportRejectsExcessContentLength() async {
        do {
            _ = try await LocationLookupClient.fetchCoordinates(configuration: configuration(headers: ["Content-Length": "20000"]))
            XCTFail("Accepted oversized Content-Length")
        } catch {
            XCTAssertEqual(error as? LocationLookupError, .responseTooLarge)
        }
    }

    func testTransportBoundsStreamWithoutContentLength() async {
        do {
            _ = try await LocationLookupClient.fetchCoordinates(configuration: configuration(body: Data(repeating: 32, count: 16_385)))
            XCTFail("Accepted oversized stream")
        } catch {
            XCTAssertEqual(error as? LocationLookupError, .responseTooLarge)
        }
    }

    func testTransportRejectsMalformedPayload() async {
        do {
            _ = try await LocationLookupClient.fetchCoordinates(configuration: configuration(body: Data("not json".utf8)))
            XCTFail("Accepted malformed JSON")
        } catch {
            XCTAssertEqual(error as? LocationLookupError, .invalidResponse)
        }
    }
}
