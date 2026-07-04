import Foundation
import AppKit

/// Installs updates from downloaded .dmg or .zip files.
public class UpdateInstaller {

    public enum InstallerError: Error {
        case unsupportedFileFormat
        case taskFailed(command: String, exitCode: Int32, output: String)
        case couldNotFindAppBundle
        case codeSignVerificationFailed
        case installationFailed(Error)
    }

    /// Installs an update from a local file URL (.dmg or .zip).
    /// Cleans up temporary files on failure.
    public func install(_ fileURL: URL) throws {
        let fileExtension = fileURL.pathExtension.lowercased()

        switch fileExtension {
        case "dmg":
            try installDmg(at: fileURL)
        case "zip":
            try installZip(at: fileURL)
        default:
            throw InstallerError.unsupportedFileFormat
        }
    }

    // MARK: - DMG Installation

    private func installDmg(at dmgURL: URL) throws {
        let mountPoint = "/Volumes/ErrorUpdateInstaller"
        defer {
            // Always attempt cleanup
            let _ = try? runCommand("/usr/bin/hdiutil", arguments: ["detach", mountPoint])
        }

        // 1. Attach DMG
        try runCommand("/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-mountpoint", mountPoint, dmgURL.path])

        // 2. Find .app bundle inside the mounted volume
        guard let appURL = try findAppBundle(in: URL(fileURLWithPath: mountPoint)) else {
            throw InstallerError.couldNotFindAppBundle
        }

        // 3. Verify code signature before installing
        try verifyCodeSignature(appURL)

        // 4. Copy to /Applications
        let appName = appURL.lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications/\(appName)")

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: appURL, to: destURL)
    }

    // MARK: - ZIP Installation

    private func installZip(at zipURL: URL) throws {
        // Extract to a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try runCommand("/usr/bin/unzip", arguments: [zipURL.path, "-d", tempDir.path])

        // 1. Find .app bundle
        guard let appURL = try findAppBundle(in: tempDir) else {
            throw InstallerError.couldNotFindAppBundle
        }

        // 2. Verify code signature before installing
        try verifyCodeSignature(appURL)

        // 3. Copy to /Applications
        let appName = appURL.lastPathComponent
        let destURL = URL(fileURLWithPath: "/Applications/\(appName)")

        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: appURL, to: destURL)
    }

    // MARK: - Helpers

    /// Runs a command and throws if it exits non-zero.
    @discardableResult
    private func runCommand(_ command: String, arguments: [String]) throws -> String {
        let process = Process()
        process.launchPath = command
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launch()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw InstallerError.taskFailed(command: command, exitCode: process.terminationStatus, output: output)
        }
        return output
    }

    /// Searches a directory recursively for a .app bundle.
    private func findAppBundle(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        if let app = contents.first(where: { $0.pathExtension == "app" }) {
            return app
        }
        // Recurse into subdirectories
        for item in contents where item.hasDirectoryPath {
            if let found = try findAppBundle(in: item) {
                return found
            }
        }
        return nil
    }

    /// Verifies the code signature of an app bundle using `codesign`.
    private func verifyCodeSignature(_ appURL: URL) throws {
        let process = Process()
        process.launchPath = "/usr/bin/codesign"
        process.arguments = ["--verify", "--deep", "--strict", appURL.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.launch()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            throw InstallerError.codeSignVerificationFailed
        }
    }
}
