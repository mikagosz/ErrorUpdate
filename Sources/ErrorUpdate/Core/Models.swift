//
//  Models.swift
//  ErrorUpdate
//

import Foundation
import CryptoKit

/// The type of error being reported.
public enum ErrorType: String, Codable, Equatable, Sendable {
    /// An Objective-C exception (`NSException`).
    case exception
    /// A standard Swift `Error`.
    case swiftError
    /// A fatal signal like SIGSEGV.
    case signal
}

/// A detailed report of an error or crash.
public struct ErrorReport: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    /// Mutable: the store refreshes it when merging duplicate reports.
    public var timestamp: Date
    public let errorType: ErrorType
    public let errorMessage: String
    public let stackTrace: [String]
    public let appVersion: String
    public let osVersion: String
    public let systemInfo: SystemInfo
    public let customContext: [String: String]?
    public var contactEmail: String?
    /// Stable hash of the error's identity, used to deduplicate repeated crashes.
    public let contentHash: String
    /// How many times this exact error occurred (maintained by `ReportStore`).
    public var count: Int

    public init(
        errorType: ErrorType = .swiftError,
        errorMessage: String,
        stackTrace: [String] = [],
        appVersion: String? = nil,
        osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
        systemInfo: SystemInfo = .current(),
        customContext: [String: String]? = nil,
        contactEmail: String? = nil,
        contentHash: String? = nil,
        count: Int = 1,
        id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.id = id
        self.timestamp = timestamp
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.stackTrace = stackTrace
        self.appVersion = appVersion
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "0.0.0"
        self.osVersion = osVersion
        self.systemInfo = systemInfo
        self.customContext = customContext
        self.contactEmail = contactEmail
        self.count = count
        self.contentHash = contentHash
            ?? Self.makeContentHash(errorType: errorType, errorMessage: errorMessage, stackTrace: stackTrace)
    }

    /// Hash over the error's identity: type, message and the top of the stack.
    static func makeContentHash(errorType: ErrorType, errorMessage: String, stackTrace: [String]) -> String {
        let source = errorType.rawValue + "|" + errorMessage + "|" + stackTrace.prefix(5).joined(separator: "|")
        let digest = SHA256.hash(data: Data(source.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Information about an available software update.
public struct UpdateInfo: Codable, Equatable, Sendable {
    public let latestVersion: String
    public let available: Bool
    public let releaseNotes: String
    public let downloadURL: URL
    public let sha256: String
    /// Base64-encoded Ed25519 signature of the update file (optional).
    public let signature: String
    public let mandatory: Bool

    public init(
        latestVersion: String,
        available: Bool = true,
        releaseNotes: String = "",
        downloadURL: URL,
        sha256: String,
        signature: String = "",
        mandatory: Bool = false
    ) {
        self.latestVersion = latestVersion
        self.available = available
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.signature = signature
        self.mandatory = mandatory
    }

    // Tolerant decoding: only latestVersion, downloadURL and sha256 are required
    // so older servers without `signature`/`mandatory` keep working.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        latestVersion = try container.decode(String.self, forKey: .latestVersion)
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        sha256 = try container.decode(String.self, forKey: .sha256)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false
    }
}

/// Information about the system where the error occurred.
public struct SystemInfo: Codable, Equatable, Sendable {
    public let osVersion: String
    public let cpuModel: String
    public let ramGB: Int
    public let diskFreeGB: Int

    /// Creates a SystemInfo instance with current system data.
    public static func current() -> SystemInfo {
        let processInfo = ProcessInfo.processInfo

        let ramBytes = processInfo.physicalMemory
        let ramGB = Int(round(Double(ramBytes) / 1_073_741_824.0))

        var diskFreeGB = 0
        if let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attributes[.systemFreeSize] as? NSNumber {
            diskFreeGB = Int(round(freeSize.doubleValue / 1_073_741_824.0))
        }

        return SystemInfo(
            osVersion: processInfo.operatingSystemVersionString,
            cpuModel: Self.cpuBrandString() ?? "Unknown",
            ramGB: ramGB,
            diskFreeGB: diskFreeGB
        )
    }

    private static func cpuBrandString() -> String? {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var chars = [UInt8](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &chars, &size, nil, 0) == 0 else {
            return nil
        }
        return String(decoding: chars.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
}
