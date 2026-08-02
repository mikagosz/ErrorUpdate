import Foundation

/// Manages persistence and retrieval of error reports as JSON files
/// (one file per report, named by the report's UUID).
///
/// The directory is read exactly once and then mirrored in memory. Rereading and
/// re-decoding every file on each save made a crash loop cost quadratic time at
/// the very moment the app could least afford it, and `fetchAll()` — which the
/// manager calls on the main actor — paid for the whole directory every time.
///
/// The store assumes it is the only writer of its directory; files dropped in
/// from outside after the first read are not noticed.
public final class ReportStore: @unchecked Sendable {

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.errorupdate.reportstore.sync")
    private let reportsDirectory: URL

    /// Reports with the same `contentHash` within this window are merged
    /// into a single entry with an incremented `count`.
    private let deduplicationWindow: TimeInterval = 86_400 // 24 h

    /// Upper bound on stored reports; the oldest are dropped past it.
    ///
    /// Nothing else bounds them: with `reportingOptIn == false` reports sit on
    /// disk until the user discards them by hand.
    private let maxStoredReports: Int

    // Both are only touched on `queue`. `cachedReports` is nil until first use.
    private var cachedReports: [UUID: ErrorReport]?
    private var idsByContentHash: [String: UUID] = [:]

    enum StoreError: Error {
        case directoryCreationError
    }

    /// - Parameters:
    ///   - directory: Custom storage directory (useful for tests).
    ///     Defaults to `Application Support/<bundle id>/reports`.
    ///   - maxStoredReports: How many reports to keep before dropping the oldest.
    public init(directory: URL? = nil, maxStoredReports: Int = 50) throws {
        self.maxStoredReports = max(1, maxStoredReports)

        if let directory {
            reportsDirectory = directory
        } else if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleID = Bundle.main.bundleIdentifier ?? "ErrorUpdate"
            reportsDirectory = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("reports")
        } else {
            throw StoreError.directoryCreationError
        }

        try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true)
    }

    /// Saves a report, merging it with an existing duplicate when one exists.
    /// - Parameter completion: Called on a background queue once the write finished.
    public func save(_ report: ErrorReport, completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            do {
                try self.loadIfNeeded()

                var reportToSave = report
                // One dictionary lookup instead of decoding the whole directory.
                if let existingID = self.idsByContentHash[report.contentHash],
                   var existing = self.cachedReports?[existingID],
                   existing.timestamp.timeIntervalSinceNow > -self.deduplicationWindow {
                    existing.count += 1
                    existing.timestamp = Date()
                    reportToSave = existing
                }

                try self.write(reportToSave)
                self.cachedReports?[reportToSave.id] = reportToSave
                self.idsByContentHash[reportToSave.contentHash] = reportToSave.id

                self.pruneToLimit()
            } catch {
                fputs("ErrorUpdate: failed to save report: \(error)\n", stderr)
            }
            completion?()
        }
    }

    /// Returns all stored reports, newest first.
    public func fetchAll() -> [ErrorReport] {
        queue.sync {
            do {
                try loadIfNeeded()
                return (cachedReports ?? [:]).values.sorted { $0.timestamp > $1.timestamp }
            } catch {
                fputs("ErrorUpdate: failed to fetch reports: \(error)\n", stderr)
                return []
            }
        }
    }

    /// Removes a report after it was successfully delivered.
    public func markAsSent(_ id: UUID, completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            try? self.fileManager.removeItem(at: self.fileURL(for: id))
            self.forget(id)
            completion?()
        }
    }

    // MARK: - Private (queue only)

    private func loadIfNeeded() throws {
        guard cachedReports == nil else { return }

        let fileURLs = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var reports: [UUID: ErrorReport] = [:]
        for url in fileURLs where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let report = try? decoder.decode(ErrorReport.self, from: data) else { continue }
            reports[report.id] = report
        }

        cachedReports = reports
        // Newest wins, so a fresh duplicate merges into the most recent entry.
        idsByContentHash = [:]
        for report in reports.values.sorted(by: { $0.timestamp < $1.timestamp }) {
            idsByContentHash[report.contentHash] = report.id
        }
    }

    private func write(_ report: ErrorReport) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        try data.write(to: fileURL(for: report.id), options: .atomic)
    }

    private func pruneToLimit() {
        guard let reports = cachedReports, reports.count > maxStoredReports else { return }

        let oldest = reports.values
            .sorted { $0.timestamp > $1.timestamp }
            .dropFirst(maxStoredReports)

        for report in oldest {
            try? fileManager.removeItem(at: fileURL(for: report.id))
            forget(report.id)
        }
    }

    private func forget(_ id: UUID) {
        guard let report = cachedReports?.removeValue(forKey: id) else { return }
        if idsByContentHash[report.contentHash] == id {
            idsByContentHash.removeValue(forKey: report.contentHash)
        }
    }

    private func fileURL(for id: UUID) -> URL {
        reportsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}
