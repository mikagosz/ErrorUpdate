//
//  ErrorUpdateManager.swift
//  ErrorUpdate
//

import Foundation
import Combine

/// The main coordinator for the ErrorUpdate framework.
///
/// Usage:
/// ```swift
/// ErrorUpdateManager.shared.configure(
///     ErrorUpdateConfig(serverURL: URL(string: "https://your-server.com")!)
/// )
/// ErrorUpdateManager.shared.setupCrashHandling()
/// ErrorUpdateManager.shared.startPeriodicUpdateCheck()
/// ```
@MainActor
public final class ErrorUpdateManager: ObservableObject {

    // MARK: - Singleton

    public static let shared = ErrorUpdateManager()

    // MARK: - Observable State

    @Published public private(set) var isConfigured = false
    /// All locally stored (not yet delivered) error reports, newest first.
    @Published public private(set) var pendingReports: [ErrorReport] = []
    /// The update found by the last check, if any.
    @Published public private(set) var availableUpdate: UpdateInfo?
    /// Local file URL of a downloaded, verified update ready to install.
    @Published public private(set) var downloadedUpdateURL: URL?
    /// Set when an install finished without changing the running version —
    /// see ``IneffectiveUpdate``. Survives relaunches until a version that
    /// actually takes effect is installed.
    @Published public private(set) var ineffectiveUpdate: IneffectiveUpdate?

    public var pendingReportsCount: Int { pendingReports.count }

    /// Optional delegate for hooking into the error/update lifecycle.
    public weak var delegate: ErrorUpdateDelegate?

    /// The app's marketing version, read from the bundle.
    public var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    // MARK: - Private

    private var config: ErrorUpdateConfig?
    private var reportStore: ReportStore?
    private var serverClient: ServerClient?
    private var updateChecker: UpdateChecker?
    private var updateDownloader: UpdateDownloader?
    private let updateInstaller = UpdateInstaller()
    private let updateScheduler = UpdateScheduler()
    private let installedVersions = InstalledVersionStore()

    /// Apps use ``shared``. This exists so tests can hold an instance of their
    /// own: the singleton and its `UserDefaults` keys are shared by every test
    /// suite, and suites run in parallel.
    init() {}

    // MARK: - Configuration

    /// Convenience overload for simple setups.
    public func configure(
        serverURL: URL,
        publicKey: Data = Data(),
        allowUnsignedUpdates: Bool = false,
        reportingOptIn: Bool = false
    ) {
        configure(ErrorUpdateConfig(
            serverURL: serverURL,
            publicKey: publicKey,
            allowUnsignedUpdates: allowUnsignedUpdates,
            reportingOptIn: reportingOptIn
        ))
    }

    /// Configures the framework. Call once, early in the app's lifecycle
    /// (e.g. `applicationDidFinishLaunching`).
    public func configure(_ config: ErrorUpdateConfig) {
        configure(config, session: nil, userDefaults: .standard)
    }

    /// Same as ``configure(_:)``, with the two collaborators tests need to own:
    /// the network session and the defaults holding the check cache.
    func configure(_ config: ErrorUpdateConfig, session: URLSession?, userDefaults: UserDefaults) {
        // Fail at configuration time rather than at the first update check —
        // this is a mistake the developer can only fix in code.
        guard URLSecurity.isAcceptable(config.serverURL) else {
            fputs("""
                ErrorUpdate: refusing to configure — \
                \(URLSecurity.rejectionReason(for: config.serverURL)).\n
                """, stderr)
            self.config = nil
            isConfigured = false
            return
        }

        // Reconfiguring is a mistake often enough to be worth saying out loud,
        // and it has to leave no part of the previous setup running: a live
        // scheduler would otherwise keep firing against the old configuration.
        let isReconfiguration = isConfigured
        if isReconfiguration {
            fputs("""
                ErrorUpdate: configure() called again — replacing the previous \
                configuration and stopping the running update schedule.\n
                """, stderr)
            updateScheduler.stop()
            availableUpdate = nil
            downloadedUpdateURL = nil
        }

        self.config = config

        do {
            reportStore = try ReportStore()
        } catch {
            fputs("ErrorUpdate: failed to initialize ReportStore: \(error)\n", stderr)
        }

        warnIfBundleHasNoVersion()

        let version = currentVersion ?? "0.0.0"
        let client = ServerClient(config: config, currentVersion: version, session: session)
        serverClient = client
        updateChecker = UpdateChecker(serverClient: client, currentVersion: version,
                                      userDefaults: userDefaults)
        updateDownloader = UpdateDownloader(config: config)

        updateScheduler.onTick = { [weak self] in
            Task { await self?.checkForUpdates(force: false) }
        }

        isConfigured = true

        // A crash file belongs to the previous run, so it is only worth looking
        // for on the first configuration. The same goes for the verdict on the
        // previous run's install.
        if !isReconfiguration {
            processPendingCrashFile()
            verifyPreviousInstall()
        }
        refreshPendingReports()
    }

    // MARK: - Error Reporting

    /// Installs handlers for uncaught exceptions and fatal signals.
    /// The resulting crash file is converted into a report on the next launch.
    public func setupCrashHandling() {
        guard warnIfNotConfigured() else { return }
        CrashCatcher.register()
        SignalHandler.register()
    }

    /// Logs a non-fatal Swift error. The report is stored locally and, when
    /// `reportingOptIn` is enabled, also sent to the server.
    public func logError(_ error: Error, context: [String: String]? = nil) {
        guard warnIfNotConfigured() else { return }

        let report = ReportBuilder.build(from: error, context: context)
        delegate?.didCatchError(report)
        storeAndMaybeSend(report)
    }

    /// Sends all pending reports to the server, removing the ones that were accepted.
    public func sendPendingReports() async {
        guard let serverClient, let reportStore else { return }

        for report in reportStore.fetchAll() {
            do {
                try await serverClient.submitReport(report)
                await withCheckedContinuation { continuation in
                    reportStore.markAsSent(report.id) { continuation.resume() }
                }
            } catch {
                // Keep the report for a later attempt.
                fputs("ErrorUpdate: failed to send report \(report.id): \(error)\n", stderr)
            }
        }
        refreshPendingReports()
    }

    /// Permanently deletes a stored report.
    public func discardReport(_ id: UUID) {
        reportStore?.markAsSent(id) { [weak self] in
            Task { @MainActor in self?.refreshPendingReports() }
        }
    }

    /// Erases everything this framework has written outside your app: stored
    /// reports, the raw crash file, its quarantined sibling, cached downloads and
    /// every `ErrorUpdate_*` key in `UserDefaults`.
    ///
    /// Call this when you remove the framework from an app, or to give users a
    /// "delete my diagnostic data" button. Reports contain stack traces with
    /// `/Users/<name>/` paths, OS and hardware details — without this method they
    /// stay on disk indefinitely, long after the library is gone from the project.
    ///
    /// Safe to call at any time: the store is left usable, so reporting simply
    /// starts from an empty slate. Published state is reset as well, so the UI
    /// does not keep showing reports that no longer exist.
    ///
    /// The periodic update check is stopped, because it would otherwise write
    /// `ErrorUpdate_LastUpdateCheckDate` back within the hour and quietly undo
    /// part of the erase. An app that stays open and still wants automatic
    /// checks has to ask for them again with ``startPeriodicUpdateCheck(interval:)``.
    ///
    /// - Returns: `true` when everything could be removed. `false` means at least
    ///   one item survived — a report file locked by another process, say — and
    ///   the rest was still erased.
    @discardableResult
    public func eraseAllStoredData() -> Bool {
        var allGone = true
        let fileManager = FileManager.default

        // First, before anything is removed: a tick landing mid-erase would put
        // the last-check date straight back.
        updateScheduler.stop()

        do {
            try reportStore?.eraseAll()
        } catch {
            fputs("ErrorUpdate: could not erase stored reports: \(error)\n", stderr)
            allGone = false
        }

        // Crash file plus the quarantined copy left by an unreadable one.
        let crashFile = CrashCatcher.crashReportURL()
        for url in [crashFile, crashFile.appendingPathExtension("unreadable")]
        where fileManager.fileExists(atPath: url.path) {
            do { try fileManager.removeItem(at: url) } catch { allGone = false }
        }

        // Half-finished downloads live in a temporary directory of our own.
        let downloads = fileManager.temporaryDirectory.appendingPathComponent("ErrorUpdate_download")
        if fileManager.fileExists(atPath: downloads.path) {
            do { try fileManager.removeItem(at: downloads) } catch { allGone = false }
        }

        // Every key this framework writes is prefixed, so sweeping the prefix
        // covers the ones added after this method was written too.
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("ErrorUpdate_") {
            defaults.removeObject(forKey: key)
        }

        pendingReports = []
        availableUpdate = nil
        downloadedUpdateURL = nil
        ineffectiveUpdate = nil

        return allGone
    }

    /// Points the manager at a report store of the test's own making. The default
    /// store lives in a directory shared by every suite, and suites run in parallel.
    func useReportStoreForTesting(_ store: ReportStore) {
        reportStore = store
        refreshPendingReports()
    }

    /// Reloads `pendingReports` from disk.
    public func refreshPendingReports() {
        pendingReports = reportStore?.fetchAll() ?? []
    }

    // MARK: - Updates

    /// Checks the server for a new version. Updates `availableUpdate`.
    ///
    /// A check the 1-hour cache skips leaves `availableUpdate` as it was — silence
    /// from the cache is not an answer that there is no update.
    ///
    /// - Parameter force: Pass `true` (default) for user-initiated checks;
    ///   automatic periodic checks pass `false` to respect the 1-hour cache.
    public func checkForUpdates(force: Bool = true) async {
        guard let updateChecker else {
            warnNotConfigured()
            return
        }
        do {
            switch try await updateChecker.checkForUpdates(force: force) {
            case .notChecked:
                // The cache was still fresh, so nothing was asked of the server.
                // An update found a moment ago stays on screen — clearing it here
                // made the periodic check erase what the user had just been shown.
                break
            case .noUpdate:
                availableUpdate = nil
            case .available(let info):
                availableUpdate = info
                delegate?.didDetectUpdate(info)
            case .ineffective(let info):
                // The server keeps offering a version that already installed
                // without changing anything. Say so instead of raising the same
                // prompt again — and, as with `.notChecked`, leave whatever the
                // user is currently looking at alone.
                reportIneffectiveUpdate(expected: info.latestVersion)
            }
        } catch {
            delegate?.updateDidFail(error)
        }
    }

    /// Starts periodic background update checks.
    public func startPeriodicUpdateCheck(interval: TimeInterval = 3600) {
        guard warnIfNotConfigured() else { return }
        updateScheduler.start(interval: interval)
    }

    /// Stops the periodic update check.
    public func stopPeriodicUpdateCheck() {
        updateScheduler.stop()
    }

    /// Whether a periodic update check is currently scheduled.
    var isPeriodicUpdateCheckRunning: Bool { updateScheduler.isRunning }

    /// Downloads and verifies the available update. Sets `downloadedUpdateURL`.
    @discardableResult
    public func downloadUpdate() async -> URL? {
        guard let info = availableUpdate, let updateDownloader else { return nil }
        do {
            let url = try await updateDownloader.download(info)
            downloadedUpdateURL = url
            return url
        } catch {
            delegate?.updateDidFail(error)
            return nil
        }
    }

    /// Installs the previously downloaded update and relaunches the app.
    /// - Parameter relaunch: When `true`, the app restarts into the new version.
    public func installUpdate(relaunch: Bool = true) async {
        guard let fileURL = downloadedUpdateURL else { return }
        let installer = updateInstaller
        // Written before the swap, not after: from here on the process can be
        // replaced at any moment, and the next launch is the only place where
        // "did this install actually change the version" can be answered.
        if let expected = availableUpdate?.latestVersion {
            installedVersions.expect(expected)
        }
        do {
            let installedAppURL = try await Task.detached(priority: .userInitiated) {
                try installer.install(fileURL)
            }.value
            downloadedUpdateURL = nil
            // The archive has done its job. It has to go before the relaunch —
            // past that line this process can be replaced at any moment, and the
            // full download (17 MB in one measured app) would sit in $TMPDIR
            // until a reboot, once per update.
            Self.removeDownloadArtifacts(of: fileURL)
            if relaunch {
                installer.relaunch(appAt: installedAppURL)
            }
        } catch {
            // Nothing was swapped, so there is no install to pass judgement on
            // at the next launch.
            installedVersions.clearExpectation()
            delegate?.updateDidFail(error)
        }
    }

    /// Removes the per-download directory the downloader created for `fileURL`,
    /// and the shared parent once it is empty.
    ///
    /// Deliberately narrow: only a directory that sits directly inside our own
    /// `ErrorUpdate_download` is removed, so a caller passing some other path
    /// cannot turn this into a delete of an unrelated folder.
    nonisolated static func removeDownloadArtifacts(of fileURL: URL) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("ErrorUpdate_download")
        let directory = fileURL.deletingLastPathComponent()

        guard directory.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else {
            return
        }
        try? fileManager.removeItem(at: directory)

        // The shared parent is worth removing too, but only when nothing else
        // is downloading into it right now.
        if let leftovers = try? fileManager.contentsOfDirectory(atPath: root.path), leftovers.isEmpty {
            try? fileManager.removeItem(at: root)
        }
    }

    /// Answers the question the previous run could not: did the install that
    /// relaunched this app actually produce the version it promised?
    ///
    /// Runs once per launch, on the first `configure(_:)`.
    private func verifyPreviousInstall() {
        let actual = currentVersion ?? "0.0.0"

        // A version that once failed and is now running got fixed and reissued
        // under the same number — the silence has served its purpose.
        if let ineffective = installedVersions.ineffectiveVersion,
           InstalledVersionStore.verdict(expected: ineffective, actual: actual) == .tookEffect {
            installedVersions.clearIneffective()
        }

        guard let expected = installedVersions.expectedVersion else { return }
        installedVersions.clearExpectation()

        guard InstalledVersionStore.verdict(expected: expected, actual: actual) == .ineffective else {
            // The install did what it said. Any earlier verdict is stale.
            installedVersions.clearIneffective()
            ineffectiveUpdate = nil
            return
        }

        installedVersions.markIneffective(expected)
        reportIneffectiveUpdate(expected: expected)
    }

    /// Publishes the warning, tells the delegate and — because a library whose
    /// integrator ignores both would otherwise fail silently — writes to stderr.
    private func reportIneffectiveUpdate(expected: String) {
        let report = IneffectiveUpdate(expectedVersion: expected,
                                       actualVersion: currentVersion ?? "0.0.0")
        ineffectiveUpdate = report
        delegate?.updateDidNotTakeEffect(report)
        fputs("ErrorUpdate: \(report.localizedDescription)\n", stderr)
    }

    // MARK: - Crash File Processing

    /// Warns when the bundle carries no version number.
    ///
    /// This is not a cosmetic gap: without `CFBundleShortVersionString` the app is
    /// treated as `0.0.0`, so *every* release compares as newer and the update
    /// prompt comes back forever. Measured in a real app whose `Info.plist` had
    /// neither a version nor an identifier — nothing worked, and nothing said why.
    ///
    /// Silent under a test runner: a test host legitimately has no marketing
    /// version, and the warning would fire on every configure in every test.
    func warnIfBundleHasNoVersion() {
        guard currentVersion == nil, !Self.hasWarnedAboutMissingVersion else { return }
        guard !Self.isRunningTests else { return }
        Self.hasWarnedAboutMissingVersion = true

        fputs("""
            ErrorUpdate: the app has no CFBundleShortVersionString, so it is treated as \
            version 0.0.0 — every update will look newer and keep being offered. Add the key \
            to your Info.plist. With GENERATE_INFOPLIST_FILE = NO, Xcode adds nothing on its \
            own and INFOPLIST_KEY_* build settings are ignored, so the file has to carry it.\n
            """, stderr)
    }

    /// Once per process — the point is to tell the developer, not to fill the log.
    private nonisolated(unsafe) static var hasWarnedAboutMissingVersion = false

    /// Whether this process is a test run.
    ///
    /// `XCTestConfigurationFilePath` is **not** enough: measured under
    /// `swift test`, the process is `swiftpm-testing-helper` and that variable is
    /// absent. `XCTestCase` is loaded in both runners (Swift Testing runs with
    /// XCTest interop), which makes it the reliable signal.
    private static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Implicitly `internal` so tests can call it directly: `configure()` only does
    /// so on the first configuration, and under a test runner the singleton has
    /// already been configured by earlier cases.
    func processPendingCrashFile() {
        let crashFileURL = CrashCatcher.crashReportURL()
        guard FileManager.default.fileExists(atPath: crashFileURL.path) else { return }

        guard let data = try? Data(contentsOf: crashFileURL) else {
            // The file is there but unreadable — leave it and try again on the next
            // launch. Deleting here would destroy the only trace of the crash.
            return
        }

        // Deliberately `String(decoding:as:)` rather than `String(contentsOf:encoding:.utf8)`.
        // Given long, mangled SwiftUI symbols, `backtrace_symbols_fd` writes bytes that
        // are not valid UTF-8 — measured on a crash in a SwiftUI app: a correct header,
        // then raw garbage in the middle of a frame from roughly 1.3 kB in. The
        // `encoding:` initialiser returned nil there and **the whole report was lost**,
        // even though the signal number and the first stack frames were intact. This
        // version never fails: damaged bytes become U+FFFD and the rest survives.
        let content = String(decoding: data, as: UTF8.self)
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        let report: ErrorReport
        switch lines.count >= 2 ? lines.removeFirst() : "" {
        case "signal":
            let signalNumber = Int32(lines.removeFirst()) ?? -1
            report = ReportBuilder.build(fromSignal: signalNumber, stackTrace: lines.filter { !$0.isEmpty })
        case "exception":
            let name = lines.removeFirst()
            let reason = lines.isEmpty ? "" : lines.removeFirst()
            report = ErrorReport(
                errorType: .exception,
                errorMessage: "Uncaught Exception: \(name) - \(reason)",
                stackTrace: lines.filter { !$0.isEmpty }
            )
        default:
            // The header cannot be recognised. Do not delete it silently — set the
            // file aside so it can be inspected without coming back on every launch.
            let quarantine = crashFileURL.appendingPathExtension("unreadable")
            try? FileManager.default.removeItem(at: quarantine)
            try? FileManager.default.moveItem(at: crashFileURL, to: quarantine)
            FileHandle.standardError.write(Data(
                "ErrorUpdate: unrecognised crash file, set aside as \(quarantine.lastPathComponent)\n".utf8
            ))
            return
        }

        // Only here — the file goes away only once a report has been built from it.
        try? FileManager.default.removeItem(at: crashFileURL)

        delegate?.didCatchError(report)
        storeAndMaybeSend(report)
    }

    // MARK: - Helpers

    private func storeAndMaybeSend(_ report: ErrorReport) {
        reportStore?.save(report) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshPendingReports()
                if self.config?.reportingOptIn == true {
                    await self.sendPendingReports()
                }
            }
        }
    }

    @discardableResult
    private func warnIfNotConfigured() -> Bool {
        if !isConfigured { warnNotConfigured() }
        return isConfigured
    }

    private func warnNotConfigured() {
        // Deliberately not `assertionFailure`: this is a library, and a misuse
        // of its API is not a reason to kill the integrator's app in Debug.
        fputs("""
            ErrorUpdate: manager used before configure() — call ignored. \
            Call configure() early in the app's lifecycle.\n
            """, stderr)
    }
}
