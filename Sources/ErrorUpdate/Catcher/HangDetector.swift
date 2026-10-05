//
//  HangDetector.swift
//  ErrorUpdate
//

import Foundation

/// Notices when the main thread stops answering — the spinning cursor.
///
/// A background timer posts a ping to the main queue and waits for the answer.
/// A ping left unanswered longer than `threshold` is a hang. It is measured
/// from the ping, not from the last answer, so a timer that macOS delayed
/// (App Nap) cannot pass for a hang: no ping is outstanding then.
/// Time is the system uptime, which stands still while the Mac sleeps — on the
/// wall clock a ping sent just before sleep would come back as a hang as long
/// as the sleep.
///
/// While a hang lasts, a marker file holds its start time. A hang that ends
/// normally removes it and reports the duration; a hang the user ends by
/// force-quitting leaves it behind, and the next launch reports that instead.
/// The main thread's own stack cannot be read from here, so these reports
/// carry no stack trace.
final class HangDetector: @unchecked Sendable {

    let threshold: TimeInterval
    let pingInterval: TimeInterval
    private let markerURL: URL?
    private let onHang: @Sendable (TimeInterval) -> Void

    private let queue = DispatchQueue(label: "ErrorUpdate.HangDetector", qos: .utility)
    private let lock = NSLock()
    private var timer: DispatchSourceTimer?
    /// System uptime when the ping was sent and when the hang began.
    private var outstandingPing: TimeInterval?
    private var hangStarted: TimeInterval?

    init(threshold: TimeInterval, pingInterval: TimeInterval = 0.5, markerURL: URL?,
         onHang: @escaping @Sendable (TimeInterval) -> Void) {
        self.threshold = threshold
        self.pingInterval = pingInterval
        self.markerURL = markerURL
        self.onHang = onHang
    }

    deinit { timer?.cancel() }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        source.setEventHandler { [weak self] in self?.tick() }
        timer = source
        source.resume()
    }

    func stop() {
        lock.lock()
        timer?.cancel()
        timer = nil
        outstandingPing = nil
        hangStarted = nil
        lock.unlock()
        removeMarker()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard let sent = outstandingPing else {
            outstandingPing = now
            lock.unlock()
            DispatchQueue.main.async { [weak self] in self?.pong() }
            return
        }
        let newHang = hangStarted == nil && now - sent > threshold
        if newHang { hangStarted = sent }
        lock.unlock()
        // The marker is read by a person and by the next launch, so it keeps the wall clock.
        if newHang { writeMarker(started: Date().addingTimeInterval(sent - now)) }
    }

    private func pong() {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        let started = hangStarted
        outstandingPing = nil
        hangStarted = nil
        lock.unlock()
        guard let started else { return }
        removeMarker()
        onHang(now - started)
    }

    // MARK: - Marker

    private func writeMarker(started: Date) {
        guard let markerURL else { return }
        try? String(started.timeIntervalSince1970).write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private func removeMarker() {
        guard let markerURL else { return }
        try? FileManager.default.removeItem(at: markerURL)
    }

    /// The start time of a hang the previous run never recovered from, if any.
    /// Removes the marker, so it is reported once.
    static func takeUnfinishedHang(at markerURL: URL) -> Date? {
        guard let text = try? String(contentsOf: markerURL, encoding: .utf8) else { return nil }
        try? FileManager.default.removeItem(at: markerURL)
        guard let seconds = TimeInterval(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
