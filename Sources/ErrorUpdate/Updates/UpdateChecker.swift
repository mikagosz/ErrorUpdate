//
//  UpdateChecker.swift
//  ErrorUpdate
//

import Foundation

/// Outcome of a version check.
///
/// The distinction that matters is `notChecked` vs `noUpdate`: the first one
/// carries no knowledge about the server at all, so a caller must not use it to
/// clear an update it already found. Collapsing both into `nil` made the
/// periodic scheduler erase an update the user had just been shown.
enum UpdateCheckResult: Equatable {
    /// The check did not run — the cached result is still fresh (`force: false`).
    case notChecked
    /// The server answered and there is nothing to offer: the release is not
    /// available yet, is not newer, or the user skipped it.
    case noUpdate
    /// A newer version is available.
    case available(UpdateInfo)
    /// The server still offers a version that was already installed once
    /// without taking effect. Not something to announce again on its own —
    /// see ``InstalledVersionStore``.
    case ineffective(UpdateInfo)

    /// The update info, or `nil` when there is none to show.
    var info: UpdateInfo? {
        if case .available(let info) = self { return info }
        return nil
    }
}

/// Checks the server for available updates and compares with the current app version.
final class UpdateChecker: @unchecked Sendable {

    private let serverClient: ServerClient
    private let currentVersion: String
    private let userDefaults: UserDefaults
    private let skippedVersions: SkippedVersionStore
    private let installedVersions: InstalledVersionStore

    private let cacheInterval: TimeInterval = 3600 // 1 hour
    private let lastCheckKey = "ErrorUpdate_LastUpdateCheckDate"

    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2

    init(serverClient: ServerClient, currentVersion: String, userDefaults: UserDefaults = .standard) {
        self.serverClient = serverClient
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
        self.skippedVersions = SkippedVersionStore(defaults: userDefaults)
        self.installedVersions = InstalledVersionStore(defaults: userDefaults)
    }

    /// Checks for updates.
    ///
    /// - Returns: `.available` with a newer version, `.noUpdate` when the server
    ///   answered and has nothing to offer, or `.notChecked` when the cache was
    ///   still fresh and no request was made. See ``UpdateCheckResult`` for why
    ///   the last two are not the same answer.
    ///
    /// - Parameter force: When `false`, the check is skipped if one already ran within
    ///   the last hour (used by the periodic scheduler), and a version the user
    ///   dismissed with "Never Ask Again" is not reported. Manual, user-initiated
    ///   checks should pass `true`: someone who asks for a check wants the answer.
    ///
    /// Network failures are retried up to 3 times with exponential backoff (2s, 4s, 8s).
    func checkForUpdates(force: Bool = false) async throws -> UpdateCheckResult {
        if !force,
           let lastCheck = userDefaults.object(forKey: lastCheckKey) as? Date,
           Date().timeIntervalSince(lastCheck) < cacheInterval {
            return .notChecked
        }

        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                let info = try await serverClient.fetchVersionInfo()
                userDefaults.set(Date(), forKey: lastCheckKey)

                // The server can publish a version without offering it yet
                // (staged rollout, a release pulled back). Unlike a version the
                // user skipped, this is not something a forced check overrides.
                guard info.available else { return .noUpdate }

                guard Self.isVersion(info.latestVersion, greaterThan: currentVersion) else {
                    return .noUpdate
                }
                // A version the user dismissed stays dismissed until a newer
                // one shows up — but never for a check the user asked for.
                if !force, skippedVersions.shouldSuppress(info.latestVersion) {
                    return .noUpdate
                }
                // A version that already installed without changing anything is
                // not offered again by itself: that is the loop this whole
                // bookkeeping exists to break. A check the user asked for still
                // shows it — the release may have been rebuilt in the meantime.
                if !force, installedVersions.isKnownIneffective(info.latestVersion) {
                    return .ineffective(info)
                }
                return .available(info)
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
