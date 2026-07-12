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

    private init() {}

    // MARK: - Configuration

    /// Convenience overload for simple setups.
    public func configure(serverURL: URL, publicKey: Data = Data(), reportingOptIn: Bool = false) {
        configure(ErrorUpdateConfig(serverURL: serverURL, publicKey: publicKey, reportingOptIn: reportingOptIn))
    }

    /// Configures the framework. Call once, early in the app's lifecycle
    /// (e.g. `applicationDidFinishLaunching`).
    public func configure(_ config: ErrorUpdateConfig) {
        self.config = config

        do {
            reportStore = try ReportStore()
        } catch {
            fputs("ErrorUpdate: failed to initialize ReportStore: \(error)\n", stderr)
        }

        let version = currentVersion ?? "0.0.0"
        let client = ServerClient(config: config, currentVersion: version)
        serverClient = client
        updateChecker = UpdateChecker(serverClient: client, currentVersion: version)
        updateDownloader = UpdateDownloader(config: config)

        updateScheduler.onTick = { [weak self] in
            Task { await self?.checkForUpdates(force: false) }
        }

        isConfigured = true

        // Turn a crash file from the previous run into a report.
        processPendingCrashFile()
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

    /// Reloads `pendingReports` from disk.
    public func refreshPendingReports() {
        pendingReports = reportStore?.fetchAll() ?? []
    }

    // MARK: - Updates

    /// Checks the server for a new version. Updates `availableUpdate`.
    /// - Parameter force: Pass `true` (default) for user-initiated checks;
    ///   automatic periodic checks pass `false` to respect the 1-hour cache.
    public func checkForUpdates(force: Bool = true) async {
        guard let updateChecker else {
            warnNotConfigured()
            return
        }
        do {
            let info = try await updateChecker.checkForUpdates(force: force)
            availableUpdate = info
            if let info {
                delegate?.didDetectUpdate(info)
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
        do {
            let installedAppURL = try await Task.detached(priority: .userInitiated) {
                try installer.install(fileURL)
            }.value
            downloadedUpdateURL = nil
            if relaunch {
                installer.relaunch(appAt: installedAppURL)
            }
        } catch {
            delegate?.updateDidFail(error)
        }
    }

    // MARK: - Crash File Processing

    private func processPendingCrashFile() {
        let crashFileURL = CrashCatcher.crashReportURL()
        guard FileManager.default.fileExists(atPath: crashFileURL.path) else { return }
        defer { try? FileManager.default.removeItem(at: crashFileURL) }

        guard let content = try? String(contentsOf: crashFileURL, encoding: .utf8) else { return }
        var lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard lines.count >= 2 else { return }

        let report: ErrorReport
        switch lines.removeFirst() {
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
            return
        }

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
        assertionFailure("ErrorUpdateManager must be configured before use. Call `configure()` first.")
        fputs("ErrorUpdate: manager used before configure() — call ignored.\n", stderr)
    }
}
