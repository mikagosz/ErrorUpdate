import Testing
@testable import ErrorUpdate
import Foundation

/// Hangs of the main thread and operations that never end — the two kinds of
/// trouble that do not crash and so slipped past the crash handlers.
@Suite(.serialized) struct HangAndOperationTests {

    /// Collects callbacks from background queues.
    private final class Box<T>: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [T] = []
        func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
        var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    private func tempURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ErrorUpdate_\(name)_\(UUID().uuidString)")
    }

    // MARK: Operation watch

    @Test func operationNotEnded_reportsOnceWithItsName() async {
        let box = Box<OperationWatch.Overdue>()
        let watch = OperationWatch(name: "ramCleanup", limit: 0.1) { box.add($0) }
        _ = watch
        #expect(await waitUntil(timeout: 2) { !box.all.isEmpty })
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(box.all.count == 1)
        #expect(box.all.first?.name == "ramCleanup")
        #expect(box.all.first?.startedFrom.isEmpty == false)
    }

    @Test func operationEndedInTime_reportsNothing() async {
        let box = Box<OperationWatch.Overdue>()
        let watch = OperationWatch(name: "quick", limit: 0.2) { box.add($0) }
        watch.end()
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(box.all.isEmpty)
    }

    // MARK: Hang detector

    @Test func blockedMainThread_writesMarkerDuringHang_reportsDurationAfter() async {
        let marker = tempURL("hang.marker")
        defer { try? FileManager.default.removeItem(at: marker) }
        let box = Box<TimeInterval>()
        let detector = HangDetector(threshold: 0.3, pingInterval: 0.05, markerURL: marker) { box.add($0) }
        detector.start()
        defer { detector.stop() }
        try? await Task.sleep(nanoseconds: 200_000_000)

        DispatchQueue.main.async { Thread.sleep(forTimeInterval: 1.2) }   // the spinning cursor

        #expect(await waitUntil(timeout: 1.1) { FileManager.default.fileExists(atPath: marker.path) },
                "A marker must exist while the main thread is stuck")
        // Other suites run in parallel and some block the main thread for
        // seconds themselves (hdiutil in InstallLocationTests), so the report
        // can come late and shorter or longer hangs may be reported as well.
        #expect(await waitUntil(timeout: 30) { box.all.contains { $0 >= 0.9 } },
                "The 1.2 s hang must be reported once it ends")
        #expect(await waitUntil(timeout: 30) { !FileManager.default.fileExists(atPath: marker.path) },
                "A recovered hang removes its marker")
    }

    @Test func responsiveMainThread_reportsNothing() async {
        let box = Box<TimeInterval>()
        let detector = HangDetector(threshold: 0.3, pingInterval: 0.05, markerURL: nil) { box.add($0) }
        detector.start()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        detector.stop()
        #expect(box.all.isEmpty)
    }

    // MARK: Manager

    @MainActor
    private func manager(marker: URL? = nil) throws -> (ErrorUpdateManager, URL) {
        let dir = tempURL("reports")
        let manager = ErrorUpdateManager()
        manager.useReportStoreForTesting(try ReportStore(directory: dir))
        if let marker { manager.hangMarkerURL = marker }
        return (manager, dir)
    }

    @MainActor
    @Test func overdueOperation_landsInPendingReports() async throws {
        let (manager, dir) = try manager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let watch = manager.beginOperation("backup", limit: 0.1)
        _ = watch
        #expect(await waitUntil(timeout: 3) { !manager.pendingReports.isEmpty })
        let report = try #require(manager.pendingReports.first)
        #expect(report.errorMessage.contains("backup"))
        #expect(report.customContext?[ReportBuilder.kindKey] == "operationOverdue")
    }

    @MainActor
    @Test func watchOperation_endsTheWatchOnReturn() async throws {
        let (manager, dir) = try manager()
        defer { try? FileManager.default.removeItem(at: dir) }
        let value = await manager.watchOperation("fast", limit: 0.2) { 42 }
        #expect(value == 42)
        try? await Task.sleep(nanoseconds: 500_000_000)
        #expect(manager.pendingReports.isEmpty)
    }

    @MainActor
    @Test func hangLeftByPreviousRun_isReportedOnce() async throws {
        let marker = tempURL("hang.marker")
        defer { try? FileManager.default.removeItem(at: marker) }
        try String(Date().addingTimeInterval(-60).timeIntervalSince1970)
            .write(to: marker, atomically: true, encoding: .utf8)
        let (manager, dir) = try manager(marker: marker)
        defer { try? FileManager.default.removeItem(at: dir) }

        manager.processUnfinishedHang()
        #expect(await waitUntil(timeout: 3) { !manager.pendingReports.isEmpty })
        #expect(manager.pendingReports.first?.customContext?[ReportBuilder.kindKey] == "hangUntilExit")
        #expect(!FileManager.default.fileExists(atPath: marker.path))

        manager.processUnfinishedHang()
        try? await Task.sleep(nanoseconds: 300_000_000)
        #expect(manager.pendingReports.count == 1)
        #expect(manager.pendingReports.first?.count == 1, "Identical reports merge with a counter — the counter must stay at 1")
    }
}
