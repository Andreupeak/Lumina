import Foundation

private final class LocationRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

enum LocationLookupClient {
    static func fetchCoordinates(configuration: URLSessionConfiguration = .ephemeral) async throws -> LocationCoordinate {
        try Task.checkCancellation()
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: LocationRedirectBlocker(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let url = URL(string: "https://ipapi.co/json/")!
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 12
        request.setValue("Lumina", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocationLookupError.serviceUnavailable
        }
        guard response.expectedContentLength <= LocationResponseParser.maximumResponseBytes else {
            throw LocationLookupError.responseTooLarge
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < LocationResponseParser.maximumResponseBytes else {
                throw LocationLookupError.responseTooLarge
            }
            data.append(byte)
        }
        return try LocationResponseParser.parse(data, statusCode: http.statusCode)
    }
}
