//
//  UpdateInstaller.swift
//  ErrorUpdate
//

import Foundation
import AppKit

/// Installs updates from downloaded `.dmg` or `.zip` files.
///
/// Note: installation replaces the app bundle on disk, which requires the app
/// to run outside the App Sandbox (or with appropriate user consent).
public final class UpdateInstaller: Sendable {

    public enum InstallerError: LocalizedError {
        case unsupportedFileFormat
        case taskFailed(command: String, exitCode: Int32, output: String)
        case couldNotFindAppBundle
        case codeSignVerificationFailed(String)
        case installationFailed(Error)

        public var errorDescription: String? {
            switch self {
            case .unsupportedFileFormat:
                return "Unsupported update file format (expected .dmg or .zip)."
            case .taskFailed(let command, let exitCode, let output):
                return "\(command) failed with exit code \(exitCode): \(output)"
            case .couldNotFindAppBundle:
                return "No .app bundle found inside the update."
            case .codeSignVerificationFailed(let output):
                return "Code signature verification failed: \(output)"
            case .installationFailed(let error):
                return "Installation failed: \(error.localizedDescription)"
            }
        }
    }

    public init() {}

    /// Installs an update from a local `.dmg` or `.zip` file.
    /// Blocking — call it from a background thread or task.
    /// - Parameter installDirectory: Where to place the new app bundle.
    ///   Defaults to the directory of the currently running app (or /Applications).
    /// - Returns: URL of the installed app bundle.
    @discardableResult
    public func install(_ fileURL: URL, into installDirectory: URL? = nil) throws -> URL {
        switch fileURL.pathExtension.lowercased() {
        case "dmg":
            return try installDmg(at: fileURL, installDirectory: installDirectory)
        case "zip":
            return try installZip(at: fileURL, installDirectory: installDirectory)
        default:
            throw InstallerError.unsupportedFileFormat
        }
    }

    /// Launches a new instance of the app at `appURL` and terminates this one.
    @MainActor
    public func relaunch(appAt appURL: URL) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", appURL.path]
        try? process.run()
        NSApp.terminate(nil)
    }

    // MARK: - DMG Installation

    private func installDmg(at dmgURL: URL, installDirectory: URL?) throws -> URL {
        // Unique mount point so parallel installs (or leftovers) never collide.
        let mountPoint = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_mount_\(UUID().uuidString)").path

        try runCommand("/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-mountpoint", mountPoint, dmgURL.path])
        defer {
            _ = try? runCommand("/usr/bin/hdiutil", arguments: ["detach", mountPoint, "-force"])
        }

        guard let appURL = try findAppBundle(in: URL(fileURLWithPath: mountPoint)) else {
            throw InstallerError.couldNotFindAppBundle
        }

        return try replaceInstalledApp(with: appURL, installDirectory: installDirectory)
    }

    // MARK: - ZIP Installation

    private func installZip(at zipURL: URL, installDirectory: URL?) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try runCommand("/usr/bin/ditto", arguments: ["-x", "-k", zipURL.path, tempDir.path])

        guard let appURL = try findAppBundle(in: tempDir) else {
            throw InstallerError.couldNotFindAppBundle
        }

        return try replaceInstalledApp(with: appURL, installDirectory: installDirectory)
    }

    // MARK: - Replacement

    /// Verifies the new bundle's code signature, then swaps it in with a backup
    /// so a failed copy never leaves the user without an app.
    private func replaceInstalledApp(with newAppURL: URL, installDirectory: URL?) throws -> URL {
        try verifyCodeSignature(newAppURL)

        let fileManager = FileManager.default
        let appName = newAppURL.lastPathComponent

        // Install next to the currently running bundle when possible,
        // otherwise fall back to /Applications.
        let installDir: URL
        if let installDirectory {
            installDir = installDirectory
        } else if Bundle.main.bundleURL.pathExtension == "app" {
            installDir = Bundle.main.bundleURL.deletingLastPathComponent()
        } else {
            installDir = URL(fileURLWithPath: "/Applications")
        }
        let destinationURL = installDir.appendingPathComponent(appName)

        var backupURL: URL?
        if fileManager.fileExists(atPath: destinationURL.path) {
            let backup = installDir.appendingPathComponent(appName + ".backup-\(UUID().uuidString.prefix(8))")
            try fileManager.moveItem(at: destinationURL, to: backup)
            backupURL = backup
        }

        do {
            try fileManager.copyItem(at: newAppURL, to: destinationURL)
        } catch {
            // Restore the previous version if the copy failed.
            if let backupURL {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw InstallerError.installationFailed(error)
        }

        if let backupURL {
            try? fileManager.removeItem(at: backupURL)
        }
        return destinationURL
    }

    // MARK: - Helpers

    @discardableResult
    private func runCommand(_ command: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        // Read before waiting so a full pipe buffer can never deadlock the process.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            throw InstallerError.taskFailed(command: command, exitCode: process.terminationStatus, output: output)
        }
        return output
    }

    /// Searches a directory (one level deep, then recursively) for a .app bundle.
    private func findAppBundle(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)

        if let app = contents.first(where: { $0.pathExtension == "app" }) {
            return app
        }
        for item in contents where item.hasDirectoryPath {
            if let found = try findAppBundle(in: item) {
                return found
            }
        }
        return nil
    }

    /// Verifies the code signature of an app bundle using `codesign`.
    private func verifyCodeSignature(_ appURL: URL) throws {
        do {
            try runCommand("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        } catch InstallerError.taskFailed(_, _, let output) {
            throw InstallerError.codeSignVerificationFailed(output)
        }
    }
}
