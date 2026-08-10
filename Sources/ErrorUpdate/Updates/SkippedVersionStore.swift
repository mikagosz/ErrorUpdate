//
//  SkippedVersionStore.swift
//  ErrorUpdate
//

import Foundation

/// Remembers the version the user dismissed with "Never Ask Again".
///
/// Both the write (from the update dialog) and the read (from the update check)
/// go through here, so the two can never drift apart on the key or on the
/// comparison rule.
/// `@unchecked` because `UserDefaults` is not marked `Sendable` even though it
/// is documented as thread-safe — the same reason `UpdateChecker` carries it.
struct SkippedVersionStore: @unchecked Sendable {

    static let defaultsKey = "ErrorUpdate_SkippedVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var skippedVersion: String? {
        defaults.string(forKey: Self.defaultsKey)
    }

    func skip(_ version: String) {
        defaults.set(version, forKey: Self.defaultsKey)
    }

    func clear() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }

    /// `true` when the user asked not to be told about this version again.
    ///
    /// Only the dismissed version itself is silenced. Anything newer is
    /// announced normally — otherwise one click would mute updates forever.
    func shouldSuppress(_ version: String) -> Bool {
        guard let skippedVersion else { return false }
        return !UpdateChecker.isVersion(version, greaterThan: skippedVersion)
    }
}
