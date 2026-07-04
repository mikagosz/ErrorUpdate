//
//  ErrorUpdateManager.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// The main coordinator for the ErrorUpdate framework.
public class ErrorUpdateManager {
    
    // MARK: - Singleton
    
    /// The shared singleton instance.
    public static let shared = ErrorUpdateManager()
    
    // MARK: - Public Properties
    
    /// The delegate for receiving callbacks.
    public weak var delegate: ErrorUpdateDelegate?
    
    // MARK: - Private Properties
    
    private var serverClient: ServerClient?
    private var updateChecker: UpdateChecker?
    private var updateScheduler: UpdateScheduler?
    
    private var isConfigured = false
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Public API
    
    /// Configures the framework with server details and app information.
    /// This must be called once, typically in `applicationDidFinishLaunching`.
    public func configure(
        serverURL: URL,
        appID: String,
        apiKey: String,
        currentVersion: String,
        userEmail: String? = nil
    ) {
        guard !isConfigured else {
            print("ErrorUpdateManager is already configured.")
            return
        }
        
        self.serverClient = ServerClient(serverURL: serverURL, appID: appID, apiKey: apiKey, currentVersion: currentVersion)
        self.updateChecker = UpdateChecker(serverClient: self.serverClient!, currentVersion: currentVersion)
        self.updateScheduler = UpdateScheduler(updateChecker: self.updateChecker!)
        
        // Setup the scheduler callback
        self.updateScheduler?.onUpdateAvailable = { [weak self] updateInfo in
            self?.delegate?.didDetectUpdate(updateInfo)
            // In Task 16, this will trigger the UI.
            print("Update available: \(updateInfo.latestVersion)")
        }
        
        self.isConfigured = true
        print("ErrorUpdateManager configured successfully.")
    }
    
    /// Sets up automatic crash handling for native exceptions and signals.
    public func setupCrashHandling() {
        assertIsConfigured()
        ErrorCatcher.activate()
        // The actual report building/sending from the catcher will be integrated later.
    }
    
    /// Logs a non-fatal Swift error.
    /// - Parameters:
    ///   - error: The `Error` to be logged.
    ///   - context: A dictionary of custom key-value pairs for additional context.
    public func logError(_ error: Error, context: [String: String]? = nil) {
        assertIsConfigured()
        
        let report = ReportBuilder.build(from: error, context: context)
        delegate?.didCatchError(report)
        
        serverClient?.submitErrorReport(report) { result in
            switch result {
            case .success:
                print("Successfully submitted error report.")
            case .failure(let error):
                print("Failed to submit error report: \(error)")
            }
        }
    }
    
    /// Manually triggers a check for updates.
    public func checkForUpdates() {
        assertIsConfigured()
        updateChecker?.checkForUpdates { [weak self] result in
            switch result {
            case .success(let updateInfo?):
                self?.delegate?.didDetectUpdate(updateInfo)
                // In Task 16, this will trigger the UI.
                 print("Update available: \(updateInfo.latestVersion)")
            case .success(nil):
                print("No new update available.")
            case .failure(let error):
                self?.delegate?.updateDidFail(error)
            }
        }
    }
    
    /// Starts a periodic check for updates in the background.
    /// - Parameter interval: The time in seconds between checks.
    public func startPeriodicUpdateCheck(interval: TimeInterval) {
        assertIsConfigured()
        updateScheduler?.start(interval: interval)
    }

    /// Stops the periodic update check.
    public func stopPeriodicUpdateCheck() {
        updateScheduler?.stop()
    }
    
    // MARK: - Private Helpers
    
    private func assertIsConfigured() {
        guard isConfigured else {
            fatalError("ErrorUpdateManager must be configured by calling `configure(...)` before use.")
        }
    }
}
