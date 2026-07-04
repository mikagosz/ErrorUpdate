//
//  Models.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// The type of error being reported.
public enum ErrorType: String, Codable, Equatable {
    /// An Objective-C exception (`NSException`).
    case exception
    /// A standard Swift `Error`.
    case swiftError
    /// A fatal signal like SIGSEGV.
    case signal
}

/// A detailed report of an error or crash.
public struct ErrorReport: Codable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let appVersion: String
    public let osVersion: String
    public let errorType: ErrorType
    public let errorMessage: String
    public let stackTrace: [String]
    public let systemInfo: SystemInfo
    public let customContext: [String: String]?
    public let userEmail: String?
    public let consentEmail: Bool
    public let contentHash: String
    public var count: Int

    public init(id: UUID = UUID(), timestamp: Date = Date(), appVersion: String = "1.0.0", osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString, errorType: ErrorType = .swiftError, errorMessage: String = "", stackTrace: [String] = [], systemInfo: SystemInfo = .current(), customContext: [String: String]? = nil, userEmail: String? = nil, consentEmail: Bool = false, contentHash: String = "", count: Int = 1) {
        self.id = id
        self.timestamp = timestamp
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.errorType = errorType
        self.errorMessage = errorMessage
        self.stackTrace = stackTrace
        self.systemInfo = systemInfo
        self.customContext = customContext
        self.userEmail = userEmail
        self.consentEmail = consentEmail
        self.contentHash = contentHash
        self.count = count
    }
}

/// Information about an available software update.
public struct UpdateInfo: Codable, Equatable {
    public let latestVersion: String
    public let available: Bool
    public let releaseNotes: String
    public let downloadURL: URL
    public let sha256: String
    public let mandatory: Bool
}

/// Information about the system where the error occurred.
public struct SystemInfo: Codable, Equatable {
    public let osVersion: String
    public let cpuModel: String // Note: Getting the exact CPU model programmatically is non-trivial and may require external libraries or private APIs. This will be a placeholder.
    public let ramGB: Int
    public let diskFreeGB: Int
    
    /// Creates a SystemInfo instance with current system data.
    public static func current() -> SystemInfo {
        let processInfo = ProcessInfo.processInfo
        
        let osVersion = processInfo.operatingSystemVersionString
        
        // Getting precise CPU model is hard. We'll use a placeholder.
        // A more advanced implementation might use `sysctlbyname` e.g., "machdep.cpu.brand_string"
        let cpuModel = "Unknown"
        
        let ramBytes = processInfo.physicalMemory
        let ramGB = Int(round(Double(ramBytes) / 1024.0 / 1024.0 / 1024.0))
        
        // Get free disk space
        let fileManager = FileManager.default
        let diskFreeGB: Int
        do {
            let attributes = try fileManager.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                diskFreeGB = Int(round(freeSize.doubleValue / 1024.0 / 1024.0 / 1024.0))
            } else {
                diskFreeGB = 0
            }
        } catch {
            diskFreeGB = 0
        }
        
        return SystemInfo(
            osVersion: osVersion,
            cpuModel: cpuModel,
            ramGB: ramGB,
            diskFreeGB: diskFreeGB
        )
    }
}
