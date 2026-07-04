//
//  UpdateScheduler.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// Schedules and manages periodic checks for application updates.
class UpdateScheduler {
    
    private let updateChecker: UpdateChecker
    private var timer: Timer?
    
    // This callback would be used to trigger the UI presentation.
    var onUpdateAvailable: ((UpdateInfo) -> Void)?
    
    init(updateChecker: UpdateChecker) {
        self.updateChecker = updateChecker
    }
    
    deinit {
        stop()
    }
    
    /// Starts the periodic update check.
    /// - Parameter interval: The time interval in seconds between checks.
    func start(interval: TimeInterval) {
        // Ensure any existing timer is stopped before starting a new one.
        stop()
        
        // Fire the first check immediately, then start the timer for subsequent checks.
        performCheck()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
        
        // For a background-friendly timer, a DispatchSourceTimer would be more robust,
        // but for this implementation, a standard Timer is sufficient.
    }
    
    /// Stops the periodic update check.
    func stop() {
        timer?.invalidate()
        timer = nil
    }
    
    /// The action performed by the timer.
    private func performCheck() {
        print("Scheduler performing periodic update check...")
        updateChecker.checkForUpdates { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let updateInfo?):
                    // An update is available, trigger the callback.
                    self?.onUpdateAvailable?(updateInfo)
                case .success(nil):
                    // No update available or check was skipped.
                    print("No new update available.")
                case .failure(let error):
                    // An error occurred during the check.
                    print("Error during periodic update check: \(error.localizedDescription)")
                }
            }
        }
    }
}
