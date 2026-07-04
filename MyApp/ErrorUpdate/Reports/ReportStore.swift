import Foundation

// TODO: Manages persistence and retrieval of error reports.
class ReportStore {
    
    private let fileManager = FileManager.default
    private let queue = DispatchQueue(label: "com.errorupdate.reportstore.sync")
    private let reportsDirectory: URL
    
    enum StoreError: Error {
        case directoryCreationError
        case serializationError
        case fileReadError
    }
    
    init() throws {
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let bundleID = Bundle.main.bundleIdentifier else {
            throw StoreError.directoryCreationError
        }
        
        reportsDirectory = appSupportURL.appendingPathComponent(bundleID).appendingPathComponent("reports")
        
        try queue.sync {
            try fileManager.createDirectory(at: reportsDirectory, withIntermediateDirectories: true, attributes: nil)
        }
    }
    
    func save(_ report: ErrorReport) {
        queue.async {
            do {
                var reportToSave = report
                
                // Deduplication logic
                let existingReports = try self.fetchAllUnsafe()
                if let existing = existingReports.first(where: {
                    $0.contentHash == report.contentHash &&
                    $0.timestamp.timeIntervalSinceNow > -86400 // 24 hours
                }) {
                    reportToSave = existing
                    reportToSave.count += 1
                    reportToSave.timestamp = Date() // Update timestamp to keep it recent
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
    
    func fetchAll() -> [ErrorReport] {
        return queue.sync {
            do {
                return try fetchAllUnsafe()
            } catch {
                print("Failed to fetch reports: \(error)")
                return []
            }
        }
    }
    
    func markAsSent(_ id: UUID) {
        queue.async {
            let fileURL = self.reportsDirectory.appendingPathComponent("\(id.uuidString).json")
            if self.fileManager.fileExists(atPath: fileURL.path) {
                try? self.fileManager.removeItem(at: fileURL)
                print("Marked report as sent (deleted): \(id)")
            }
        }
    }
    
    // Unsafe version for internal use on the sync queue
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
