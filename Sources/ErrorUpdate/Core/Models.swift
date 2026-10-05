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
    /// Mutable: the store folds repeated hangs into it when merging duplicates.
    public var customContext: [String: String]?
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
        // Checked here, not only in the downloader: a host that opens the address
        // itself (a "Download" button handing it to NSWorkspace) never passes
        // through the downloader, and a manifest could point it at `file://`,
        // `smb://` or another app's URL scheme.
        guard URLSecurity.isAcceptable(downloadURL) else {
            throw DecodingError.dataCorruptedError(
                forKey: .downloadURL, in: container,
                debugDescription: "downloadURL must use https (or http to loopback): \(downloadURL)")
        }
        sha256 = try container.decode(String.self, forKey: .sha256)
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
        signature = try container.decodeIfPresent(String.self, forKey: .signature) ?? ""
        mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false
    }
}

/// An update that installed successfully and changed nothing.
///
/// Reported when the version the app runs after an install is not the version
/// the install promised — almost always a release packaged without bumping
/// `CFBundleShortVersionString`. Without this, the same update is offered again
/// on every check, and the user has no way to tell that anything went wrong.
public struct IneffectiveUpdate: Equatable, Sendable {
    /// The version the install was supposed to produce.
    public let expectedVersion: String
    /// The version the app actually reports after the install.
    public let actualVersion: String

    public init(expectedVersion: String, actualVersion: String) {
        self.expectedVersion = expectedVersion
        self.actualVersion = actualVersion
    }

    /// A ready-to-show explanation, aimed at whoever built the release.
    public var localizedDescription: String {
        """
        Update to \(expectedVersion) installed but the app still reports \
        \(actualVersion). The packaged build most likely carries the old \
        CFBundleShortVersionString. This version will not be offered \
        automatically again.
        """
    }
}

/// The first launch of a newer version than the previous launch ran.
///
/// Reported once, on the launch that notices it, whatever brought the new
/// version in — the in-app install, an installer package or a manual copy.
/// Use it for anything that has to follow the app to a new version: re-register
/// a privileged helper, migrate data, show "what's new".
public struct CompletedUpdate: Equatable, Sendable {
    /// The version the previous launch ran.
    public let previousVersion: String
    /// The version running now.
    public let currentVersion: String
    /// `true` when this library's own install produced this version.
    public let installedInApp: Bool

    public init(previousVersion: String, currentVersion: String, installedInApp: Bool) {
        self.previousVersion = previousVersion
        self.currentVersion = currentVersion
        self.installedInApp = installedInApp
    }
}

/// Who started an update check — decides whether a skipped version is shown.
/// See ``ErrorUpdateManager/checkForUpdates(_:)``.
public enum UpdateCheckTrigger: Sendable, Equatable {
    /// The user asked ("Check Now"): always asks the server, shows everything.
    case user
    /// The app checked on its own: 1-hour cache, skipped version stays quiet.
    case automatic
}

/// What ``ErrorUpdateManager/installUpdate(relaunch:)`` did.
///
/// Before 1.0.3 the call returned nothing, and every app worked out the
/// outcome itself by reading the `Info.plist` on disk after the swap.
public enum UpdateInstallResult: Sendable {
    /// The new bundle is in place. `version` comes from its `Info.plist` on
    /// disk (`nil` only if that file could not be read); `appURL` is where it sits.
    case installed(version: String?, appURL: URL)
    /// There was no downloaded update — call `downloadUpdate()` first.
    case nothingDownloaded
    /// Nothing was swapped; the running app is untouched. The same error went
    /// to the delegate's `updateDidFail(_:)`.
    case failed(any Error)

    /// `true` for `.installed`.
    public var isInstalled: Bool {
        if case .installed = self { return true }
        return false
    }

    /// The version now on disk, for `.installed`.
    public var installedVersion: String? {
        if case .installed(let version, _) = self { return version }
        return nil
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
