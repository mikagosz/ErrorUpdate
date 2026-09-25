import Foundation

/// Hands out throwaway `UserDefaults` suites that never land in `~/Library/Preferences`.
///
/// Every suite used to stay behind there as a file — 14 of them after one
/// `swift test` (measured 2026-09-24). Removing the domain afterwards is not
/// enough: cfprefsd empties it and then writes a 42-byte `{}` file back on its
/// own schedule, after the test is long gone. A suite named by an absolute path
/// is stored at that path instead, so these live in `$TMPDIR`, which the system
/// clears; the janitor still removes each one when its test is over.
///
/// A test suite is a struct created anew for each test, so a janitor stored in
/// it goes away with the test and its `deinit` runs however the test ended.
final class DefaultsJanitor: @unchecked Sendable {
    private let lock = NSLock()
    private var names: [String] = []

    func make(_ prefix: String) -> UserDefaults {
        let name = NSTemporaryDirectory() + "\(prefix)-\(UUID().uuidString)"
        lock.lock(); names.append(name); lock.unlock()
        return UserDefaults(suiteName: name)!
    }

    deinit {
        for name in names {
            UserDefaults(suiteName: name)?.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(atPath: name + ".plist")
        }
    }
}
