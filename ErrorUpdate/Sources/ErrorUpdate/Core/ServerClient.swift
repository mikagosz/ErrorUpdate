//
//  ServerClient.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// Handles communication with the remote server for version checking and error reporting.
internal class ServerClient {
    
    private let serverURL: URL
    private let appID: String
    private let apiKey: String
    private let currentVersion: String
    private let session: URLSession

    /// Custom errors for the ServerClient.
    enum ServerError: Error {
        case invalidResponse
        case networkError(Error)
        case httpError(statusCode: Int)
        case dataEncodingError
    }

    init(serverURL: URL, appID: String, apiKey: String, currentVersion: String) {
        self.serverURL = serverURL
        self.appID = appID
        self.apiKey = apiKey
        self.currentVersion = currentVersion
        
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: configuration)
    }

    /// Prepares a URLRequest with the necessary headers.
    private func createRequest(path: String, httpMethod: String) -> URLRequest {
        let url = serverURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        request.setValue(appID, forHTTPHeaderField: "X-App-ID")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(currentVersion, forHTTPHeaderField: "X-Current-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// Fetches the latest version information from the server.
    /// - Parameter completion: A closure to be called with the result.
    func fetchVersionInfo(completion: @escaping (Result<UpdateInfo, Error>) -> Void) {
        let request = createRequest(path: "/api/error-update/version-check", httpMethod: "GET")

        // Note: Retry logic will be added here later.
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(ServerError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ServerError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(ServerError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            guard let data = data else {
                completion(.failure(ServerError.invalidResponse))
                return
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let updateInfo = try decoder.decode(UpdateInfo.self, from: data)
                completion(.success(updateInfo))
            } catch {
                completion(.failure(error))
            }
        }
        task.resume()
    }

    /// Submits an error report to the server.
    /// - Parameters:
    ///   - report: The `ErrorReport` to submit.
    ///   - completion: A closure to be called with the result.
    func submitErrorReport(_ report: ErrorReport, completion: @escaping (Result<Void, Error>) -> Void) {
        var request = createRequest(path: "/api/error-update/report", httpMethod: "POST")
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(report)
        } catch {
            completion(.failure(ServerError.dataEncodingError))
            return
        }

        // Note: Retry logic will be added here later.
        let task = session.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(ServerError.networkError(error)))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(ServerError.invalidResponse))
                return
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                completion(.failure(ServerError.httpError(statusCode: httpResponse.statusCode)))
                return
            }

            completion(.success(()))
        }
        task.resume()
    }
}
