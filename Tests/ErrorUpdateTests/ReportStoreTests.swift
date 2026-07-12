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

    private func makeReport(contentHash: String = "abc123", timestamp: Date = Date()) -> ErrorReport {
        ErrorReport(
            errorMessage: "Test error",
            stackTrace: ["frame1", "frame2", "frame3", "frame4", "frame5"],
            appVersion: "1.0.0",
            contentHash: contentHash,
            timestamp: timestamp
        )
    }

    // MARK: 1. Dwa identyczne crashe w krótkim odstępie → jeden wpis z licznikiem 2

    @Test func saveDuplicateWithin24h_incrementsCounter() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)
        let report = makeReport()

        await save(report, to: store)
        // Save second time (same contentHash)
        await save(report, to: store)

        let saved = store.fetchAll()
        #expect(saved.count == 1, "Expected exactly one report, got \(saved.count)")
        #expect(saved[0].count == 2, "Expected count 2, got \(saved[0].count)")
    }

    // MARK: 2. Crashe z różnymi contentHash → osobne wpisy

    @Test func saveDifferentReports_createsSeparateEntries() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)

        await save(makeReport(contentHash: "hash1"), to: store)
        await save(makeReport(contentHash: "hash2"), to: store)

        let saved = store.fetchAll()
        #expect(saved.count == 2)
    }

    // MARK: 3. Raporty starsze niż 24h nie są uznawane za duplikaty

    @Test func saveOldDuplicate_createsNewEntry() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)

        // Save a report with a timestamp older than 24h directly to disk
        let oldReport = makeReport(timestamp: Date().addingTimeInterval(-86400 - 10))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(oldReport)
        try data.write(to: dir.appendingPathComponent("\(oldReport.id.uuidString).json"))

        // Now save a new report with the same contentHash
        await save(makeReport(), to: store)

        let saved = store.fetchAll()
        #expect(saved.count == 2, "Expected 2 entries (old + new), got \(saved.count)")
    }

    // MARK: 4. markAsSent usuwa plik

    @Test func markAsSent_removesFile() async throws {
        let dir = try testDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = try ReportStore(directory: dir)
        let report = makeReport()
        await save(report, to: store)

        await withCheckedContinuation { continuation in
            store.markAsSent(report.id) { continuation.resume() }
        }

        let saved = store.fetchAll()
        #expect(saved.count == 0)
    }

    // MARK: - Helpers

    /// Saves and waits for the asynchronous write to complete.
    private func save(_ report: ErrorReport, to store: ReportStore) async {
        await withCheckedContinuation { continuation in
            store.save(report) { continuation.resume() }
        }
    }
}
