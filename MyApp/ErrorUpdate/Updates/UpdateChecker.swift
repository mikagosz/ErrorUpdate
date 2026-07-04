import Foundation

/// Checks the server for available updates and compares with the current app version.
public class UpdateChecker {

    private let config: ErrorUpdateConfig
    private let currentVersion: String
    private let userDefaults: UserDefaults
    private let cacheInterval: TimeInterval = 3600 // 1 hour
    private let lastCheckKey = "ErrorUpdate_LastUpdateCheckDate"

    /// Retry configuration for offline handling.
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2

    public init(config: ErrorUpdateConfig,
                currentVersion: String,
                userDefaults: UserDefaults = .standard) {
        self.config = config
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
    }

    /// Checks for updates. Returns `UpdateInfo` if a newer version is available, `nil` otherwise.
    ///
    /// Retries up to `maxRetries` times with exponential backoff (2s, 4s, 8s) if the request
    /// fails due to a network error.
    public func checkForUpdates() async throws -> UpdateInfo? {
        // Respect cache interval
        if let lastCheck = userDefaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            print("Update check skipped (checked within the last hour).")
            return nil
        }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let info = try await fetchUpdateInfo()

                // Update last check timestamp
                userDefaults.set(Date(), forKey: lastCheckKey)

                // Compare versions
                if isVersion(info.latestVersion, greaterThan: currentVersion) {
                    return info
                }
                return nil
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2, Double(attempt))
                    print("Update check attempt \(attempt + 1) failed (\(error)), retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? NSError(domain: "ErrorUpdate", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Update check failed after \(maxRetries) retries"])
    }

    private func fetchUpdateInfo() async throws -> UpdateInfo {
        let request = URLRequest(url: config.serverURL)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ErrorUpdate", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Server returned non-successful status"])
        }

        let info = try JSONDecoder().decode(UpdateInfo.self, from: data)
        return info
    }

    /// Compares two semver-style strings. Returns true if `newVersion` > `oldVersion`.
    private func isVersion(_ newVersion: String, greaterThan oldVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let oldComponents = oldVersion.split(separator: ".").compactMap { Int($0) }

        let comparisonCount = min(newComponents.count, oldComponents.count)
        for i in 0..<comparisonCount {
            if newComponents[i] > oldComponents[i] { return true }
            if newComponents[i] < oldComponents[i] { return false }
        }

        return newComponents.count > oldComponents.count
    }
}
