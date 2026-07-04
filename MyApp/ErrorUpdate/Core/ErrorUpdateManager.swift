import Foundation
import Combine

// TODO: Main coordinator for the framework.
public final class ErrorUpdateManager: ObservableObject {
    
    public static let shared = ErrorUpdateManager()
    
    @Published public private(set) var isConfigured: Bool = false
    @Published public private(set) var pendingReportsCount: Int = 0
    @Published public private(set) var availableUpdate: UpdateInfo?

    private var config: ErrorUpdateConfig?
    private var reportStore: ReportStore?
    private var updateChecker: UpdateChecker?
    private var updateDownloader: UpdateDownloader?
    private var updateInstaller: UpdateInstaller?

    private init() {}

    public var currentVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// Convenience initializer matching the app's call site.
    public func configure(serverURL: URL, publicKey: Data = Data(), reportingOptIn: Bool = false) {
        let config = ErrorUpdateConfig(serverURL: serverURL, publicKey: publicKey, reportingOptIn: reportingOptIn)
        self.configure(config)
    }

    public func configure(_ config: ErrorUpdateConfig) {
        self.config = config
        
        do {
            self.reportStore = try ReportStore()
        } catch {
            assertionFailure("Failed to initialize ReportStore: \(error)")
        }
        
        self.isConfigured = true
        print("ErrorUpdateManager configured.")
        
        self.updateChecker = UpdateChecker(config: config, currentVersion: currentVersion ?? "0.0.0")
        self.updateDownloader = UpdateDownloader(config: config)
        self.updateInstaller = UpdateInstaller()

        // Process any pending crash files from the last run.
        processPendingCrashFiles()
        
        // Update the count of pending reports.
        updatePendingReportsCount()
    }

    public func setupCrashHandling() {
        assertIsConfigured()
        CrashCatcher.register()
        SignalHandler.register()
    }

    public func logError(_ error: Error, context: [String: String]? = nil) {
        assertIsConfigured()
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
        
        let report = ErrorReport(
            errorType: "Swift Error",
            message: error.localizedDescription,
            stackTrace: Thread.callStackSymbols,
            osVersion: osVersion,
            appVersion: appVersion
        )
        
        reportStore?.save(report)
        updatePendingReportsCount()
        
        // Handle automatic sending based on opt-in
        if config?.reportingOptIn == true {
            // TODO: Implement network call to send the report
            print("reportingOptIn is true. Would send report now.")
        }
    }

    private func processPendingCrashFiles() {
        assertIsConfigured()
        
        let crashFileURL = CrashCatcher.crashReportURL()
        guard FileManager.default.fileExists(atPath: crashFileURL.path) else {
            return
        }
        
        do {
            let content = try String(contentsOf: crashFileURL, encoding: .utf8)
            var lines = content.split(separator: "\n").map(String.init)
            
            guard lines.count >= 2 else {
                try? FileManager.default.removeItem(at: crashFileURL)
                return
            }
            
            let type = lines.removeFirst()
            let message: String
            
            if type == "signal" {
                let signalNumber = lines.removeFirst()
                message = "Caught signal \(signalNumber)"
            } else { // exception
                let exceptionName = lines.removeFirst()
                let exceptionReason = lines.removeFirst()
                message = "\(exceptionName): \(exceptionReason)"
            }
            
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "N/A"
            
            let report = ErrorReport(
                errorType: type,
                message: message,
                stackTrace: lines,
                osVersion: osVersion,
                appVersion: appVersion
            )
            
            reportStore?.save(report)
            try FileManager.default.removeItem(at: crashFileURL)
            
            print("Processed and saved pending crash report.")
        } catch {
            print("Failed to process pending crash file: \(error)")
        }
    }
    
    private func updatePendingReportsCount() {
        self.pendingReportsCount = reportStore?.fetchAll().count ?? 0
    }

    /// Checks the server for a new update (async).
    public func checkForUpdates() async {
        guard let checker = updateChecker else { return }
        do {
            let info = try await checker.checkForUpdates()
            await MainActor.run {
                self.availableUpdate = info
            }
        } catch {
            print("checkForUpdates failed: \(error)")
        }
    }

    /// Downloads the available update.
    public func downloadUpdate() async {
        guard let info = availableUpdate,
              let downloader = updateDownloader else { return }
        do {
            let url = try await downloader.download(info)
            await MainActor.run {
                // Keep reference to the downloaded file URL for install
                print("Download complete: \(url)")
            }
        } catch {
            print("downloadUpdate failed: \(error)")
        }
    }

    /// Installs the downloaded update.
    public func installUpdate(from fileURL: URL) async {
        guard let installer = updateInstaller else { return }
        do {
            try installer.install(fileURL)
            await MainActor.run {
                print("Update installed successfully.")
            }
        } catch {
            print("installUpdate failed: \(error)")
        }
    }

    // A helper to ensure configure() has been called.
    private func assertIsConfigured() {
        assert(isConfigured, "ErrorUpdateManager must be configured before use. Call `configure()` first.")
    }
}
