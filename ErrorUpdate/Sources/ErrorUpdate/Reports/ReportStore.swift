import Foundation

/// Manages persistence and retrieval of error reports using JSON-lines files.
public class ReportStore {

    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.errorupdate.reportstore.sync")
    private let reportsDirectory: URL

    enum StoreError: Error {
        case directoryCreationError
        case serializationError
        case fileReadError
    }

    /// Initialize with a custom directory (useful for tests).
    public init(directory: URL? = nil) throws {
        let dir: URL
        if let directory = directory {
            dir = directory
        } else if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
                  let bundleID = Bundle.main.bundleIdentifier {
            dir = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("reports")
        } else {
            throw StoreError.directoryCreationError
        }

        self.reportsDirectory = dir
        try queue.sync {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        }
    }

    /// Initialize with a custom directory (convenience).
    public convenience init(directory: URL) throws {
        try self.init(directory: directory)
    }

    public func save(_ report: ErrorReport) {
        queue.async {
            do {
                var reportToSave = report

                // Deduplication logic: if same contentHash within 24h, increment counter
                let existingReports = try self.fetchAllUnsafe()
                if let existing = existingReports.first(where: {
                    $0.contentHash == report.contentHash &&
                    $0.timestamp.timeIntervalSinceNow > -86400
                }) {
                    reportToSave = existing
                    reportToSave.count += 1
                    reportToSave.timestamp = Date()
                }

                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(reportToSave)
                let fileURL = self.reportsDirectory.appendingPathComponent("\(reportToSave.id.uuidString).json")
                try data.write(to: fileURL)

                print("Saved report with ID: \(reportToSave.id)")
            } catch {
                print("Failed to save report: \(error)")
            }
        }
    }

    public func fetchAll() -> [ErrorReport] {
        return queue.sync {
            do {
                return try fetchAllUnsafe()
            } catch {
                print("Failed to fetch reports: \(error)")
                return []
            }
        }
    }

    public func markAsSent(_ id: UUID) {
        queue.async {
            let fileURL = self.reportsDirectory.appendingPathComponent("\(id.uuidString).json")
            if self.fileManager.fileExists(atPath: fileURL.path) {
                try? self.fileManager.removeItem(at: fileURL)
                print("Marked report as sent (deleted): \(id)")
            }
        }
    }

    private func fetchAllUnsafe() throws -> [ErrorReport] {
        let fileURLs = try fileManager.contentsOfDirectory(at: reportsDirectory, includingPropertiesForKeys: nil)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return fileURLs.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(ErrorReport.self, from: data)
        }
    }
}
