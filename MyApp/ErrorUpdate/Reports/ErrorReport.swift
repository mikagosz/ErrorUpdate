import Foundation
import CryptoKit

// TODO: Data model for a single error report.
struct ErrorReport: Codable, Identifiable {
    let id: UUID
    let errorType: String
    let message: String
    let stackTrace: [String]
    let osVersion: String
    let appVersion: String
    var timestamp: Date = Date()
    var contactEmail: String?
    let contentHash: String
    var count: Int = 1
    
    init(errorType: String, message: String, stackTrace: [String], osVersion: String, appVersion: String, contactEmail: String? = nil, id: UUID = UUID()) {
        self.id = id
        self.errorType = errorType
        self.message = message
        self.stackTrace = stackTrace
        self.osVersion = osVersion
        self.appVersion = appVersion
        self.contactEmail = contactEmail
        
        // Generate contentHash for deduplication
        let hashSource = errorType + stackTrace.prefix(5).joined()
        let hashData = Data(hashSource.utf8)
        self.contentHash = SHA256.hash(data: hashData).compactMap { String(format: "%02x", $0) }.joined()
    }
}
