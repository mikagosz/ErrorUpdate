import Testing
@testable import ErrorUpdate
import Foundation

/// The library knows up front when the running app cannot replace itself.
@MainActor
@Suite struct InstallLocationTests {

    private func workDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_location_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// An empty `.app` folder is enough: the check looks at the place, not the bundle.
    private func fakeApp(in directory: URL) throws -> URL {
        let app = directory.appendingPathComponent("Current.app")
        try FileManager.default.createDirectory(
            at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        return app
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

    @Test func writableFolder_noProblem() throws {
        let dir = try workDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(InstallLocationProblem.check(try fakeApp(in: dir)) == nil)
    }

    @Test func translocatedCopy_isRecognised() throws {
        let dir = try workDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let translocated = dir.appendingPathComponent("AppTranslocation/0A1B2C3D/d")
        try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
        #expect(InstallLocationProblem.check(try fakeApp(in: translocated)) == .translocated)
    }

    @Test func folderWithoutWriteAccess_isRecognised() throws {
        let dir = try workDir()
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let app = try fakeApp(in: locked)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(InstallLocationProblem.check(app) == .folderNotWritable(path: locked.standardizedFileURL.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func readOnlyDiskImage_isRecognised() throws {
        let dir = try workDir()
        let staging = dir.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        _ = try fakeApp(in: staging)
        let dmg = dir.appendingPathComponent("app.dmg")
        let mount = dir.appendingPathComponent("mnt")
        try run("/usr/bin/hdiutil", ["create", dmg.path, "-srcfolder", staging.path,
                                     "-volname", "ErrorUpdateRO", "-fs", "HFS+", "-quiet"])
        try run("/usr/bin/hdiutil", ["attach", dmg.path, "-readonly", "-nobrowse",
                                     "-mountpoint", mount.path, "-quiet"])
        defer {
            try? run("/usr/bin/hdiutil", ["detach", mount.path, "-force", "-quiet"])
            try? FileManager.default.removeItem(at: dir)
        }
        #expect(InstallLocationProblem.check(mount.appendingPathComponent("Current.app")) == .readOnlyVolume)
    }

    @Test func installer_refusesBeforeOpeningTheArchive() throws {
        let dir = try workDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let translocated = dir.appendingPathComponent("AppTranslocation/X/d")
        try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
        let installer = UpdateInstaller(currentAppURL: try fakeApp(in: translocated))

        // The archive does not even exist: the refusal has to come first.
        let missing = dir.appendingPathComponent("never-downloaded.zip")
        #expect(throws: InstallLocationError(problem: .translocated)) {
            try installer.install(missing)
        }
        #expect(installer.locationProblem == .translocated)
    }

    @Test func manager_reportsProblem_andInstallFails() async throws {
        let dir = try workDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let translocated = dir.appendingPathComponent("AppTranslocation/X/d")
        try FileManager.default.createDirectory(at: translocated, withIntermediateDirectories: true)
        let manager = ErrorUpdateManager()
        manager.updateInstaller = UpdateInstaller(currentAppURL: try fakeApp(in: translocated))
        manager.stageDownloadedUpdate(dir.appendingPathComponent("update.zip"))

        #expect(manager.installLocationProblem == .translocated)
        let result = await manager.installUpdate(relaunch: false)
        guard case .failed(let error) = result else {
            Issue.record("Expected .failed, got \(result)")
            return
        }
        #expect(error as? InstallLocationError == InstallLocationError(problem: .translocated))
    }
}
