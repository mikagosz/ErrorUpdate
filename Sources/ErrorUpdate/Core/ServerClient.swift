//
//  ServerClient.swift
//  ErrorUpdate
//

import Foundation

/// Handles communication with the remote server for version checking and error reporting.
final class ServerClient: Sendable {

    enum ServerError: LocalizedError {
        case invalidResponse
        case httpError(statusCode: Int)

        var errorDescription: String? {
            switch self {
            case .invalidResponse:
                return "The server returned an invalid response."
            case .httpError(let statusCode):
                return "The server returned HTTP status \(statusCode)."
            }
        }
    }

    private let config: ErrorUpdateConfig
    private let currentVersion: String
    private let session: URLSession

    init(config: ErrorUpdateConfig, currentVersion: String, session: URLSession? = nil) {
        self.config = config
        self.currentVersion = currentVersion
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 120
            self.session = URLSession(configuration: configuration)
        }
    }

    private func makeRequest(
        path: String,
        httpMethod: String,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy
    ) -> URLRequest {
        var request = URLRequest(url: config.serverURL.appendingPathComponent(path))
        request.httpMethod = httpMethod
        request.cachePolicy = cachePolicy
        request.setValue(config.appID, forHTTPHeaderField: "X-App-ID")
        if let apiKey = config.apiKey {
            request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        }
        request.setValue(currentVersion, forHTTPHeaderField: "X-Current-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Fetches the latest version information from the server.
    ///
    /// The request **always goes to the network**: it asks about state, not about a
    /// resource, so a cached answer is worse than no answer.
    ///
    /// Measured 2026-08-12: with the default policy a check answered from `URLCache`
    /// without touching the server, so a release pulled back with `"available": false`
    /// kept being offered — and a *forced* check (the one a user asks for) found an
    /// update the server was not offering at all. The app's own one-hour cache is
    /// deliberate and `force` bypasses it; this second, invisible cache was neither.
    func fetchVersionInfo() async throws -> UpdateInfo {
        let request = makeRequest(
            path: "api/error-update/version-check",
            httpMethod: "GET",
            cachePolicy: .reloadIgnoringLocalCacheData
        )
        let (data, response) = try await session.data(for: request)
        try Self.validate(response)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(UpdateInfo.self, from: data)
    }

    /// Submits an error report to the server.
    func submitReport(_ report: ErrorReport) async throws {
        var request = makeRequest(path: "api/error-update/report", httpMethod: "POST")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        request.httpBody = try encoder.encode(report)

        let (_, response) = try await session.data(for: request)
        try Self.validate(response)
    }

    private static func validate(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ServerError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ServerError.httpError(statusCode: httpResponse.statusCode)
        }
    }
}
