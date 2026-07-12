//
//  UpdateScheduler.swift
//  ErrorUpdate
//

import Foundation

/// Schedules periodic checks for application updates.
@MainActor
final class UpdateScheduler {

    /// Called on the main actor every time a scheduled check should run.
    var onTick: (() -> Void)?

    // The scheduler lives as long as the manager singleton, so the timer is
    // released via stop() rather than deinit.
    private var timer: Timer?

    /// Starts periodic checks. Fires once immediately, then every `interval` seconds.
    func start(interval: TimeInterval) {
        stop()
        onTick?()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.onTick?()
            }
        }
        timer?.tolerance = interval * 0.1
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
