import Testing
@testable import ErrorUpdate
import Foundation

/// `installUpdate` reports what it did. Every install here targets a throwaway
/// bundle in a temporary directory, never the running test host.
@MainActor
@Suite struct InstallResultTests {

    private func makeApp(bundleID: String, version: String, in directory: URL) throws -> URL {
        let appURL = directory.appendingPathComponent("Current.app")
        let macOSDir = appURL.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)
        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": "Current",
            "CFBundleExecutable": "Current",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": version,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))
        let executable = macOSDir.appendingPathComponent("Current")
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appURL.path])
        return appURL
    }

    private func run(_ command: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(command) \(arguments) failed")
    }

    /// A running "Current.app" 1.0 and a zipped update holding `bundleID` at `version`.
    private func fixture(updateBundleID: String, updateVersion: String)
        throws -> (workDir: URL, currentApp: URL, zip: URL) {
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_result_\(UUID().uuidString)")
        let runningDir = workDir.appendingPathComponent("Applications")
        let newDir = workDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: runningDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        let currentApp = try makeApp(bundleID: "com.example.current", version: "1.0", in: runningDir)
        let newApp = try makeApp(bundleID: updateBundleID, version: updateVersion, in: newDir)
        let zipURL = workDir.appendingPathComponent("update.zip")
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", newApp.path, zipURL.path])
        return (workDir, currentApp, zipURL)
    }

    @Test func noDownload_reportsNothingDownloaded() async {
        let manager = ErrorUpdateManager()
        let result = await manager.installUpdate(relaunch: false)
        guard case .nothingDownloaded = result else {
            Issue.record("Expected .nothingDownloaded, got \(result)")
            return
        }
        #expect(!result.isInstalled)
    }

    @Test func successfulInstall_reportsVersionReadFromDisk() async throws {
        let f = try fixture(updateBundleID: "com.example.current", updateVersion: "2.0")
        defer { try? FileManager.default.removeItem(at: f.workDir) }
        let manager = ErrorUpdateManager()
        manager.updateInstaller = UpdateInstaller(currentAppURL: f.currentApp)
        manager.stageDownloadedUpdate(f.zip)

        let result = await manager.installUpdate(relaunch: false)

        guard case .installed(let version, let appURL) = result else {
            Issue.record("Expected .installed, got \(result)")
            return
        }
        #expect(version == "2.0")
        #expect(result.installedVersion == "2.0")
        #expect(appURL.standardizedFileURL == f.currentApp.standardizedFileURL)
        #expect(UpdateInstaller.shortVersion(ofAppAt: f.currentApp) == "2.0")
        #expect(manager.downloadedUpdateURL == nil)
    }

    @Test func rejectedInstall_reportsFailureAndLeavesAppUntouched() async throws {
        let f = try fixture(updateBundleID: "com.example.intruder", updateVersion: "2.0")
        defer { try? FileManager.default.removeItem(at: f.workDir) }
        let manager = ErrorUpdateManager()
        manager.updateInstaller = UpdateInstaller(currentAppURL: f.currentApp)
        manager.stageDownloadedUpdate(f.zip)

        let result = await manager.installUpdate(relaunch: false)

        guard case .failed(let error) = result,
              case .bundleIdentifierMismatch? = error as? UpdateInstaller.InstallerError else {
            Issue.record("Expected .failed(.bundleIdentifierMismatch), got \(result)")
            return
        }
        #expect(result.installedVersion == nil)
        #expect(UpdateInstaller.shortVersion(ofAppAt: f.currentApp) == "1.0")
    }
}
