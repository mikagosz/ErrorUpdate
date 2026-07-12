import Foundation

/// Manages persistence and retrieval of error reports as JSON files
/// (one file per report, named by the report's UUID).
public final class ReportStore: @unchecked Sendable {

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.errorupdate.reportstore.sync")
    private let reportsDirectory: URL

    /// Reports with the same `contentHash` within this window are merged
    /// into a single entry with an incremented `count`.
    private let deduplicationWindow: TimeInterval = 86_400 // 24 h

    enum StoreError: Error {
        case directoryCreationError
    }

    /// - Parameter directory: Custom storage directory (useful for tests).
    ///   Defaults to `Application Support/<bundle id>/reports`.
    public init(directory: URL? = nil) throws {
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
                var reportToSave = report

                let existingReports = try self.fetchAllUnsafe()
                if let existing = existingReports.first(where: {
                    $0.contentHash == report.contentHash &&
                    $0.timestamp.timeIntervalSinceNow > -self.deduplicationWindow
                }) {
                    reportToSave = existing
                    reportToSave.count += 1
                    reportToSave.timestamp = Date()
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(reportToSave)
                let fileURL = self.reportsDirectory.appendingPathComponent("\(reportToSave.id.uuidString).json")
                try data.write(to: fileURL, options: .atomic)
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
                return try fetchAllUnsafe().sorted { $0.timestamp > $1.timestamp }
            } catch {
                fputs("ErrorUpdate: failed to fetch reports: \(error)\n", stderr)
                return []
            }
        }
    }

    /// Removes a report after it was successfully delivered.
    public func markAsSent(_ id: UUID, completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            let fileURL = self.reportsDirectory.appendingPathComponent("\(id.uuidString).json")
            try? self.fileManager.removeItem(at: fileURL)
            completion?()
        }
    }

    // Must only be called on `queue`.
    private func fetchAllUnsafe() throws -> [ErrorReport] {
        let fileURLs = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return fileURLs.compactMap { url in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ErrorReport.self, from: data)
        }
    }
}
