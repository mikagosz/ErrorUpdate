import Testing
@testable import ErrorUpdate
import Foundation

/// The first launch of a newer version is reported once, whatever installed it.
@MainActor
@Suite struct CompletedUpdateTests {

    private let janitor = DefaultsJanitor()

    // MARK: Store

    @Test func firstLaunchEver_isNotAnUpdate() {
        let store = LaunchVersionStore(defaults: janitor.make("LaunchVersion"))
        #expect(store.recordLaunch("1.0.0", installedInApp: false) == nil)
        #expect(store.lastLaunchedVersion == "1.0.0")
    }

    @Test func newerVersion_isReportedOnce() {
        let store = LaunchVersionStore(defaults: janitor.make("LaunchVersion"))
        _ = store.recordLaunch("1.0.0", installedInApp: false)
        #expect(store.recordLaunch("1.0.1", installedInApp: true)
                == CompletedUpdate(previousVersion: "1.0.0", currentVersion: "1.0.1", installedInApp: true))
        #expect(store.recordLaunch("1.0.1", installedInApp: false) == nil, "Same version again is not an update")
    }

    @Test func downgrade_isRecordedNotReported() {
        let store = LaunchVersionStore(defaults: janitor.make("LaunchVersion"))
        _ = store.recordLaunch("2.0.0", installedInApp: false)
        #expect(store.recordLaunch("1.9.0", installedInApp: false) == nil)
        #expect(store.lastLaunchedVersion == "1.9.0")
    }

    // MARK: Manager

    private final class Listener: ErrorUpdateDelegate {
        var received: [CompletedUpdate] = []
        func updateDidComplete(_ update: CompletedUpdate) { received.append(update) }
    }

    private func launch(version: String, defaults: UserDefaults, delegate: Listener? = nil) -> ErrorUpdateManager {
        let manager = ErrorUpdateManager()
        manager.bundleVersionOverride = version
        manager.delegate = delegate
        manager.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!, allowUnsignedUpdates: true),
            session: nil, userDefaults: defaults)
        return manager
    }

    @Test func manager_publishesAndTellsDelegate_onFirstLaunchOfNewVersion() {
        let defaults = janitor.make("CompletedUpdateManager")
        _ = launch(version: "1.2.0", defaults: defaults)

        let listener = Listener()
        let updated = launch(version: "1.2.1", defaults: defaults, delegate: listener)
        let expected = CompletedUpdate(previousVersion: "1.2.0", currentVersion: "1.2.1", installedInApp: false)
        #expect(updated.completedUpdate == expected)
        #expect(listener.received == [expected])

        let again = launch(version: "1.2.1", defaults: defaults)
        #expect(again.completedUpdate == nil, "Only the first launch of the new version reports it")
    }

    @Test func eraseAllStoredData_clearsTheEvent() {
        let defaults = janitor.make("CompletedUpdateErase")
        _ = launch(version: "1.0.0", defaults: defaults)
        let manager = launch(version: "1.1.0", defaults: defaults)
        #expect(manager.completedUpdate != nil)
        _ = manager.eraseAllStoredData()
        #expect(manager.completedUpdate == nil)
    }
}
