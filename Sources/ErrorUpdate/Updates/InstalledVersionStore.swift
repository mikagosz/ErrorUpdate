//
//  InstalledVersionStore.swift
//  ErrorUpdate
//

import Foundation

/// Remembers which version an install was supposed to produce, so the next
/// launch can tell whether it actually did.
///
/// An install can succeed at the file level and still change nothing: the
/// classic case is a release built without bumping `CFBundleShortVersionString`,
/// where the manifest promises 2.0 but the bundle inside the archive is still
/// 1.0. The app swaps, relaunches, reads its version — unchanged — and the next
/// check offers the very same update again, forever, without a single message.
///
/// `@unchecked` because `UserDefaults` is not marked `Sendable` even though it
/// is documented as thread-safe — the same reason `UpdateChecker` carries it.
struct InstalledVersionStore: @unchecked Sendable {

    /// The version the running install was expected to produce. Present only
    /// between `expect(_:)` and the verification on the next launch.
    static let expectedVersionKey = "ErrorUpdate_ExpectedVersionAfterInstall"
    /// A version that was installed and did not take effect.
    static let ineffectiveVersionKey = "ErrorUpdate_IneffectiveVersion"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Expectation

    var expectedVersion: String? {
        defaults.string(forKey: Self.expectedVersionKey)
    }

    func expect(_ version: String) {
        defaults.set(version, forKey: Self.expectedVersionKey)
        // The app is about to be replaced and relaunched, so the usual
        // "UserDefaults writes itself out eventually" does not apply: whatever
        // is not on disk when the process dies is the answer we lose.
        defaults.synchronize()
    }

    func clearExpectation() {
        defaults.removeObject(forKey: Self.expectedVersionKey)
    }

    // MARK: - Ineffective version

    var ineffectiveVersion: String? {
        defaults.string(forKey: Self.ineffectiveVersionKey)
    }

    func markIneffective(_ version: String) {
        defaults.set(version, forKey: Self.ineffectiveVersionKey)
    }

    func clearIneffective() {
        defaults.removeObject(forKey: Self.ineffectiveVersionKey)
    }

    /// `true` for exactly the version that already installed without taking effect.
    ///
    /// Deliberately an exact match, not "this or older": anything older is
    /// already rejected by the version comparison, and a newer release must
    /// never inherit the silence of a broken one.
    func isKnownIneffective(_ version: String) -> Bool {
        ineffectiveVersion == version
    }

    // MARK: - Verdict

    /// What an install turned out to be, judged by the version the app reports
    /// after it.
    enum Verdict: Equatable {
        /// The app runs the promised version (or a newer one — an install can
        /// be overtaken by a manual upgrade between the swap and the relaunch).
        case tookEffect
        /// The app still runs an older version than the install promised.
        case ineffective
    }

    /// Kept here, next to the stored values it is compared against, and free of
    /// any state so the rule itself can be tested on its own.
    static func verdict(expected: String, actual: String) -> Verdict {
        UpdateChecker.isVersion(expected, greaterThan: actual) ? .ineffective : .tookEffect
    }
}
