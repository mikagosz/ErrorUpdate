//
//  UpdateChecker.swift
//  ErrorUpdate
//

import Foundation

/// Checks the server for available updates and compares with the current app version.
final class UpdateChecker: @unchecked Sendable {

    private let serverClient: ServerClient
    private let currentVersion: String
    private let userDefaults: UserDefaults

    private let cacheInterval: TimeInterval = 3600 // 1 hour
    private let lastCheckKey = "ErrorUpdate_LastUpdateCheckDate"

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2

    init(serverClient: ServerClient, currentVersion: String, userDefaults: UserDefaults = .standard) {
        self.serverClient = serverClient
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
    }

    /// Checks for updates. Returns `UpdateInfo` when a newer version is available, `nil` otherwise.
    ///
    /// - Parameter force: When `false`, the check is skipped if one already ran within
    ///   the last hour (used by the periodic scheduler). Manual, user-initiated checks
    ///   should pass `true`.
    ///
    /// Network failures are retried up to 3 times with exponential backoff (2s, 4s, 8s).
    func checkForUpdates(force: Bool = false) async throws -> UpdateInfo? {
        if !force,
           let lastCheck = userDefaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            return nil
        }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let info = try await serverClient.fetchVersionInfo()
                userDefaults.set(Date(), forKey: lastCheckKey)

                if Self.isVersion(info.latestVersion, greaterThan: currentVersion) {
                    return info
                }
                return nil
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? ServerClient.ServerError.invalidResponse
    }

    /// Compares two semver-style strings (`1.2.3`, optionally with a pre-release
    /// suffix like `1.2.3-beta`). Returns `true` if `newVersion` > `oldVersion`.
    static func isVersion(_ newVersion: String, greaterThan oldVersion: String) -> Bool {
        let (newCore, newPrerelease) = split(newVersion)
        let (oldCore, oldPrerelease) = split(oldVersion)

        let count = max(newCore.count, oldCore.count)
        for i in 0..<count {
            let newComponent = i < newCore.count ? newCore[i] : 0
            let oldComponent = i < oldCore.count ? oldCore[i] : 0
            if newComponent > oldComponent { return true }
            if newComponent < oldComponent { return false }
        }

        // Same numeric core: a release version is newer than its pre-release
        // (1.2.0 > 1.2.0-beta); two pre-releases compare lexically.
        switch (newPrerelease.isEmpty, oldPrerelease.isEmpty) {
        case (true, false): return true
        case (false, true): return false
        case (true, true): return false
        case (false, false): return newPrerelease > oldPrerelease
        }
    }

    private static func split(_ version: String) -> (core: [Int], prerelease: String) {
        let parts = version.split(separator: "-", maxSplits: 1)
        let core = (parts.first ?? "").split(separator: ".").compactMap { Int($0) }
        let prerelease = parts.count > 1 ? String(parts[1]) : ""
        return (core, prerelease)
    }
}
