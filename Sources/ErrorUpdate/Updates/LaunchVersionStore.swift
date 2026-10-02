//
//  LaunchVersionStore.swift
//  ErrorUpdate
//

import Foundation

/// Remembers the version of the previous launch, so the first launch of a new
/// version can be told apart from every other one.
///
/// Measured on Change-Boot 2026-10-02: a privileged helper registered by the
/// old bundle stays bound to it after the bundle is replaced, and the app had
/// no moment at which to react. The answer has to cover every way a new
/// version arrives — the in-app install, a `.pkg`, a manual drag — so it is
/// based on the version itself, not on the install path.
///
/// `@unchecked` for the same `UserDefaults` reason as the other stores.
struct LaunchVersionStore: @unchecked Sendable {

    static let lastLaunchedVersionKey = "ErrorUpdate_LastLaunchedVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastLaunchedVersion: String? {
        defaults.string(forKey: Self.lastLaunchedVersionKey)
    }

    /// Records `current` as this launch's version and returns the update it
    /// completes, if any.
    ///
    /// - The very first launch (nothing recorded yet) is not an update.
    /// - The same version again is not an update.
    /// - A lower version (a downgrade) is recorded but not reported.
    func recordLaunch(_ current: String, installedInApp: Bool) -> CompletedUpdate? {
        let previous = lastLaunchedVersion
        defaults.set(current, forKey: Self.lastLaunchedVersionKey)
        guard let previous,
              UpdateChecker.isVersion(current, greaterThan: previous) else { return nil }
        return CompletedUpdate(previousVersion: previous, currentVersion: current,
                               installedInApp: installedInApp)
    }
}
