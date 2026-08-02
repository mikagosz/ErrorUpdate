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
        case signingIdentityMismatch(String)
        case bundleIdentifierMismatch(expected: String, found: String)
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
            case .signingIdentityMismatch(let output):
                return "The update is not signed by the same identity as the running app: \(output)"
            case .bundleIdentifierMismatch(let expected, let found):
                return "The update contains a different application: expected bundle identifier \(expected), found \(found)."
            case .installationFailed(let error):
                return "Installation failed: \(error.localizedDescription)"
            }
        }
    }

    /// The app an update is checked against: its bundle identifier and signing
    /// identity must match the incoming one.
    private let currentAppURL: URL?

    /// - Parameter currentAppURL: The running app bundle. Defaults to
    ///   `Bundle.main` when the host is an `.app` (useful to override in tests).
    public init(currentAppURL: URL? = nil) {
        if let currentAppURL {
            self.currentAppURL = currentAppURL
        } else {
            let mainBundleURL = Bundle.main.bundleURL
            self.currentAppURL = mainBundleURL.pathExtension == "app" ? mainBundleURL : nil
        }
    }

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

        // The image comes from the network, so it is mounted with as little
        // ceremony as possible: read-only, no Finder window, nothing opened
        // automatically. `-noverify` skips hdiutil's own checksum pass — the
        // file has already been checked against SHA-256 and its Ed25519
        // signature, and skipping it keeps that parser away from untrusted data.
        try runCommand("/usr/bin/hdiutil", arguments: [
            "attach", dmgURL.path,
            "-mountpoint", mountPoint,
            "-readonly", "-nobrowse", "-noverify", "-noautoopen",
        ])
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

        // Keep the name of the app being replaced. Taking it from the archive
        // would let a downloaded bundle install itself beside the running app
        // under its own name instead of replacing it.
        let appName = currentAppURL?.lastPathComponent ?? newAppURL.lastPathComponent

        // Install next to the currently running bundle when possible,
        // otherwise fall back to /Applications.
        let installDir: URL
        if let installDirectory {
            installDir = installDirectory
        } else if let currentAppURL {
            installDir = currentAppURL.deletingLastPathComponent()
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

    /// Verifies that the new bundle is intact, is the same application, and was
    /// signed by the same identity as the app currently running.
    ///
    /// `codesign --verify` alone only proves a bundle matches its own signature,
    /// which any attacker can arrange with a one-line ad-hoc signing command. The
    /// question that matters — who signed this — is answered by `-R` against the
    /// running app's designated requirement.
    private func verifyCodeSignature(_ appURL: URL) throws {
        // 1. The bundle must be signed and internally consistent.
        do {
            try runCommand("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        } catch InstallerError.taskFailed(_, _, let output) {
            throw InstallerError.codeSignVerificationFailed(output)
        }

        // 2. Compare against the app being replaced. Without a running .app
        //    bundle (unit tests, command-line hosts) there is nothing to compare
        //    against, so those checks are reported as skipped rather than faked.
        guard let currentAppURL else {
            Self.warn("not running from an .app bundle — skipping bundle identifier and signing identity checks")
            return
        }

        try verifyBundleIdentifier(of: appURL, matching: currentAppURL)
        try verifySigningIdentity(of: appURL, matching: currentAppURL)
    }

    /// Rejects an update that carries a different application than the one running.
    private func verifyBundleIdentifier(of appURL: URL, matching currentAppURL: URL) throws {
        guard let expected = Self.bundleIdentifier(ofAppAt: currentAppURL) else {
            Self.warn("the running app has no bundle identifier — skipping the identifier check")
            return
        }
        let found = Self.bundleIdentifier(ofAppAt: appURL)
        guard found == expected else {
            throw InstallerError.bundleIdentifierMismatch(expected: expected, found: found ?? "(none)")
        }
    }

    /// Requires the new bundle to satisfy the running app's designated requirement.
    private func verifySigningIdentity(of appURL: URL, matching currentAppURL: URL) throws {
        guard let requirement = designatedRequirement(of: currentAppURL) else {
            Self.warn("""
                could not read the running app's designated requirement (is it signed?) \
                — the update's origin was NOT verified
                """)
            return
        }

        // An ad-hoc requirement pins the exact cdhash of one build, so no future
        // version can ever satisfy it. Enforcing it would make every update fail;
        // the honest alternative is to say plainly that this path proves nothing
        // about origin and that trust rests entirely on the Ed25519 signature.
        guard !Self.isAdHocRequirement(requirement) else {
            Self.warn("""
                the running app is ad-hoc signed — the update's origin cannot be verified \
                by codesign; authenticity rests on the Ed25519 signature alone
                """)
            return
        }

        do {
            try runCommand("/usr/bin/codesign",
                           arguments: ["--verify", "--strict", "-R", "=" + requirement, appURL.path])
        } catch InstallerError.taskFailed(_, _, let output) {
            throw InstallerError.signingIdentityMismatch(output)
        }
    }

    /// Reads a bundle's designated requirement, e.g.
    /// `identifier "com.example.app" and anchor apple generic and …`.
    private func designatedRequirement(of appURL: URL) -> String? {
        // `codesign -d` writes to stderr and `-r-` to stdout; runCommand merges
        // both, and an implicit (ad-hoc) requirement arrives commented out.
        guard let output = try? runCommand("/usr/bin/codesign",
                                           arguments: ["-d", "-r-", appURL.path]) else {
            return nil
        }
        guard let line = output.split(separator: "\n").first(where: { $0.contains("designated =>") }),
              let range = line.range(of: "designated =>") else {
            return nil
        }
        let requirement = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return requirement.isEmpty ? nil : requirement
    }

    /// True for requirements that pin a single build's code directory hash,
    /// which is what ad-hoc signing produces.
    private static func isAdHocRequirement(_ requirement: String) -> Bool {
        requirement.contains("cdhash")
            && !requirement.contains("anchor")
            && !requirement.contains("certificate")
    }

    private static func bundleIdentifier(ofAppAt appURL: URL) -> String? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, options: [], format: nil) as? [String: Any] else {
            return nil
        }
        return plist["CFBundleIdentifier"] as? String
    }

    private static func warn(_ message: String) {
        fputs("ErrorUpdate: \(message)\n", stderr)
    }
}
