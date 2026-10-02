//
//  InstallLocation.swift
//  ErrorUpdate
//

import Foundation

/// Why the running app cannot be replaced where it sits.
///
/// Before 1.0.5 the library found out only by failing halfway through an
/// install, and every app carried its own check (`writablePlace`) to offer the
/// manual route up front instead.
public enum InstallLocationProblem: Sendable, Equatable {
    /// Opened straight from Downloads (or another quarantined place): macOS
    /// runs a temporary read-only copy under `/AppTranslocation/`.
    case translocated
    /// The app sits on a read-only volume — typically the disk image it came on.
    case readOnlyVolume
    /// This user may not write to the folder holding the app.
    case folderNotWritable(path: String)

    /// A sentence for the user, with what to do about it.
    public var localizedDescription: String {
        switch self {
        case .translocated:
            return "The app is running from a temporary copy macOS made because it was opened straight from Downloads. Move it to the Applications folder, open it from there, and update again."
        case .readOnlyVolume:
            return "The app is running from a read-only disk image. Copy it to the Applications folder, open it from there, and update again."
        case .folderNotWritable(let path):
            return "The folder \(path) cannot be written to, so the app cannot replace itself. Download the new version and replace the app by hand."
        }
    }

    /// The problem with replacing the app at `appURL`, or `nil` when it can be replaced.
    static func check(_ appURL: URL, fileManager: FileManager = .default) -> InstallLocationProblem? {
        let standardized = appURL.standardizedFileURL
        if standardized.path.contains("/AppTranslocation/") {
            return .translocated
        }
        if (try? standardized.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            return .readOnlyVolume
        }
        let folder = standardized.deletingLastPathComponent().path
        if !fileManager.isWritableFile(atPath: folder) {
            return .folderNotWritable(path: folder)
        }
        return nil
    }
}

/// Thrown when an install is refused up front because the app cannot be
/// replaced where it sits. A separate type, so switches over
/// ``UpdateInstaller/InstallerError`` in existing apps stay exhaustive.
public struct InstallLocationError: LocalizedError, Sendable, Equatable {
    public let problem: InstallLocationProblem

    public init(problem: InstallLocationProblem) {
        self.problem = problem
    }

    public var errorDescription: String? { problem.localizedDescription }
}
