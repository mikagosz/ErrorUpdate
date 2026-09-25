import Testing
@testable import ErrorUpdate
import Foundation

/// The framework writes into the user's directories, so it has to be able to take that
/// back. Without it, reports carrying stack traces (`/Users/<name>/` paths, hardware
/// details) stay on disk long after the library is removed from a project — measured
/// 2026-08-10: 56 KB in one app, 16 KB in another.
///
/// Note the shape of these tests: `ErrorUpdateManager.shared` and the
/// `Application Support/<bundle id>/reports` directory are **shared by every suite**,
/// and suites run in parallel. An assertion of "the directory is empty after erasing"
/// was flaky because of it — another suite was adding a report mid-test. So directory
/// cleanup is checked on our own, temporary `ReportStore`, and the singleton is used
/// only for what is exclusively ours: crash files and prefixed defaults keys.
@MainActor
@Suite(.serialized) struct EraseStoredDataTests {

    // MARK: 1. The report store clears its own directory

    @Test func reportStore_eraseAll_removesEveryReport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        for i in 0..<3 {
            store.save(ErrorReport(errorMessage: "error number \(i)"))
        }
        _ = store.fetchAll()                       // settles the writes: fetchAll uses the same queue
        #expect(store.fetchAll().count == 3)

        try store.eraseAll()

        #expect(store.fetchAll().isEmpty, "The store must be empty once erased")
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.isEmpty, "No report may be left on disk")
    }

    // MARK: 2. The store stays usable

    @Test func reportStore_eraseAll_leavesStoreUsable() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        store.save(ErrorReport(errorMessage: "first"))
        _ = store.fetchAll()
        try store.eraseAll()

        store.save(ErrorReport(errorMessage: "after erasing"))
        #expect(store.fetchAll().count == 1, "Reporting must keep working after an erase")
    }

    // MARK: 3. Erasing does not overtake a write in flight

    /// `save(_:)` writes asynchronously. Erasing off the store's queue could overtake a
    /// write in progress, and the report came back moments after being removed.
    @Test func reportStore_eraseAll_doesNotLoseRaceWithPendingSave() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: directory)
        defer { try? FileManager.default.removeItem(at: directory) }

        for i in 0..<20 {
            store.save(ErrorReport(errorMessage: "write in flight \(i)"))
        }
        try store.eraseAll()                       // joins the same queue, so it waits for the writes

        #expect(store.fetchAll().isEmpty, "A write started before the erase must not survive it")
    }

    // MARK: 4. Crash files go away

    @Test func eraseAllStoredData_removesCrashFiles() throws {
        let manager = ErrorUpdateManager.shared
        let crashURL = CrashCatcher.crashReportURL()
        let quarantine = crashURL.appendingPathExtension("unreadable")

        try Data("signal\n11\n".utf8).write(to: crashURL)
        try Data("anything\n".utf8).write(to: quarantine)

        manager.eraseAllStoredData()

        #expect(FileManager.default.fileExists(atPath: crashURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: quarantine.path) == false)
    }

    // MARK: 5. Sweeps every prefixed key, including future ones

    @Test func eraseAllStoredData_sweepsPrefixedDefaults() {
        let manager = ErrorUpdateManager.shared
        let defaults = UserDefaults.standard

        defaults.set("9.9.9", forKey: SkippedVersionStore.defaultsKey)
        defaults.set("8.8.8", forKey: InstalledVersionStore.expectedVersionKey)
        defaults.set("a key from the future", forKey: "ErrorUpdate_KeyAddedLater")
        defaults.set("do not touch", forKey: "SomeoneElsesSetting_NotOurs")

        manager.eraseAllStoredData()

        #expect(defaults.string(forKey: SkippedVersionStore.defaultsKey) == nil)
        #expect(defaults.string(forKey: InstalledVersionStore.expectedVersionKey) == nil)
        #expect(defaults.string(forKey: "ErrorUpdate_KeyAddedLater") == nil,
                "Sweeping by prefix must cover keys added after this method was written")
        #expect(defaults.string(forKey: "SomeoneElsesSetting_NotOurs") == "do not touch",
                "The framework does not touch anyone else's settings")

        defaults.removeObject(forKey: "SomeoneElsesSetting_NotOurs")
    }

    // MARK: 5a. E-mail attachments go, other apps' downloads stay

    /// Measured 2026-09-24: the erase skipped the plain-text copies written for
    /// e-mail (whole report, `/Users/<name>/` paths) and removed the shared
    /// download directory, taking a verified update from any other app on the Mac.
    @Test func eraseAllStoredData_removesAttachmentsKeepsOtherAppsDownloads() throws {
        let manager = ErrorUpdateManager.shared
        let fileManager = FileManager.default
        let attachment = try #require(EmailComposer.writeReportToTemporaryFile(
            report: ErrorReport(errorMessage: "attachment to erase")))
        let unrelated = fileManager.temporaryDirectory
            .appendingPathComponent("ErrorReportNotes-\(UUID().uuidString).txt")
        try Data("not ours".utf8).write(to: unrelated)
        defer { try? fileManager.removeItem(at: unrelated) }

        let ours = UpdateDownloader.downloadRoot.appendingPathComponent(UUID().uuidString)
        let otherApp = UpdateDownloader.downloadRoot.deletingLastPathComponent()
            .appendingPathComponent("com.example.other-\(UUID().uuidString)")
        for directory in [ours, otherApp] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("package".utf8).write(to: directory.appendingPathComponent("update.zip"))
        }
        defer { try? fileManager.removeItem(at: otherApp) }

        manager.eraseAllStoredData()

        #expect(fileManager.fileExists(atPath: attachment.path) == false,
                "The e-mail copy carries the whole report and has to go")
        #expect(fileManager.fileExists(atPath: unrelated.path),
                "A file that only starts similarly is not ours")
        #expect(fileManager.fileExists(atPath: ours.path) == false)
        #expect(fileManager.fileExists(atPath: otherApp.appendingPathComponent("update.zip").path),
                "Another app's verified download is not this app's data")
    }

    // MARK: 6. Erasing stops the schedule

    /// Measured live in a host app on 2026-08-10: after pressing "Delete diagnostic
    /// data" the reports directory was empty, but `ErrorUpdate_LastUpdateCheckDate`
    /// **came back** a minute later — the schedule was still running and wrote it again.
    /// Keys disappeared and then quietly reappeared; the promise in the documentation
    /// held for tens of minutes, not for good.
    @Test func eraseAllStoredData_stopsPeriodicCheck() {
        let manager = ErrorUpdateManager.shared
        // Port 9 (discard) refuses the connection immediately — the instant tick from
        // `start()` has nowhere to go and writes nothing.
        manager.configure(serverURL: URL(string: "http://127.0.0.1:9")!)
        manager.startPeriodicUpdateCheck(interval: 3600)
        #expect(manager.isPeriodicUpdateCheckRunning, "Precondition: the schedule is running")

        manager.eraseAllStoredData()

        #expect(manager.isPeriodicUpdateCheckRunning == false,
                "After an erase the schedule must not restore the deleted keys")
    }
}
