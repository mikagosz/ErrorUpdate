import Testing
@testable import ErrorUpdate
import Foundation

@Suite struct ReportStoreTests {

    // Helper: create a temp directory for testing
    private func testDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ErrorUpdate_test_reports_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeReport(contentHash: String = "abc123", count: Int = 1) -> ErrorReport {
        ErrorReport(
            contentHash: contentHash,
            count: count,
            errorMessage: "Test error",
            stackTrace: ["frame1", "frame2", "frame3", "frame4", "frame5"],
            appVersion: "1.0.0",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    // MARK: 1. Dwa identyczne crashe w krótkim odstępie → jeden wpis z licznikiem 2

    @Test func saveDuplicateWithin24h_incrementsCounter() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)
        let report = makeReport()

        // Save first time
        store.save(report)
        // Wait for async save to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms

        // Save second time (same contentHash)
        store.save(report)
        try await Task.sleep(nanoseconds: 200_000_000)

        let saved = store.fetchAll()
        #expect(saved.count == 1, "Expected exactly one report, got \(saved.count)")
        #expect(saved[0].count == 2, "Expected count 2, got \(saved[0].count)")
    }

    // MARK: 2. Crashe z różnymi contentHash → osobne wpisy

    @Test func saveDifferentReports_createsSeparateEntries() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)
        let report1 = makeReport(contentHash: "hash1")
        let report2 = makeReport(contentHash: "hash2")

        store.save(report1)
        store.save(report2)
        try await Task.sleep(nanoseconds: 300_000_000)

        let saved = store.fetchAll()
        #expect(saved.count == 2)
    }

    // MARK: 3. Raporty starsze niż 24h nie są uznawane za duplikaty

    @Test func saveOldDuplicate_createsNewEntry() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)

        // Create a report with a timestamp older than 24h
        var report = makeReport()
        report.timestamp = Date().addingTimeInterval(-86400 - 10) // 24h + 10s ago
        report.id = UUID()
        try {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            let fileURL = dir.appendingPathComponent("\(report.id.uuidString).json")
            try data.write(to: fileURL)
        }()

        try await Task.sleep(nanoseconds: 100_000_000)

        // Now save a new report with the same contentHash
        let newReport = makeReport()
        store.save(newReport)
        try await Task.sleep(nanoseconds: 300_000_000)

        let saved = store.fetchAll()
        #expect(saved.count == 2, "Expected 2 entries (old + new), got \(saved.count)")
    }

    // MARK: 4. markAsSent usuwa plik

    @Test func markAsSent_removesFile() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)
        let report = makeReport()
        store.save(report)
        try await Task.sleep(nanoseconds: 200_000_000)

        store.markAsSent(report.id)
        try await Task.sleep(nanoseconds: 200_000_000)

        let saved = store.fetchAll()
        #expect(saved.count == 0)
    }
}
