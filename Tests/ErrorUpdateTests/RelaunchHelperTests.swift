import Testing
@testable import ErrorUpdate
import Foundation

/// The relaunch helper must not open the new copy while the old process lives.
/// `touch` stands in for `open`: the "app" is a marker file, so the moment the
/// helper would open the app is the moment the marker appears.
@Suite struct RelaunchHelperTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("RelaunchHelperTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func startSleeper(seconds: String) throws -> Process {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = [seconds]
        try sleeper.run()
        return sleeper
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    @Test func doesNotOpenWhileOldProcessLives_opensAfterItEnds() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("opened")
        let sleeper = try startSleeper(seconds: "1.5")

        try RelaunchHelper.start(waitingFor: sleeper.processIdentifier, app: marker, opener: "/usr/bin/touch")

        try await Task.sleep(nanoseconds: 800_000_000)
        #expect(sleeper.isRunning)
        #expect(!FileManager.default.fileExists(atPath: marker.path), "opened while the old copy was still running")

        let opened = await waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: marker.path) }
        #expect(opened, "never opened after the old copy ended")
    }

    @Test func givesUpAfterLimit_andDoesNotOpen() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let marker = dir.appendingPathComponent("opened")
        let sleeper = try startSleeper(seconds: "30")
        defer { sleeper.terminate() }

        let helper = try RelaunchHelper.start(
            waitingFor: sleeper.processIdentifier, app: marker, opener: "/usr/bin/touch", limitSeconds: 1)

        let ended = await waitUntil(timeout: 5) { !helper.isRunning }
        #expect(ended)
        #expect(helper.terminationStatus == 1)
        #expect(!FileManager.default.fileExists(atPath: marker.path))
    }

    @Test func pathWithShellCharacters_isPassedVerbatim() async throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tricky = dir.appendingPathComponent("My App $(touch pwned) `x`; rm -rf.app")
        let pwned = dir.appendingPathComponent("pwned")

        let args = RelaunchHelper.arguments(waitingFor: 1, app: tricky)
        #expect(!args[1].contains(tricky.path), "path must not be pasted into the script")
        #expect(args[4] == tricky.path)

        // A pid that is already gone: the helper opens at once.
        let gone = try startSleeper(seconds: "0")
        gone.waitUntilExit()
        try RelaunchHelper.start(waitingFor: gone.processIdentifier, app: tricky, opener: "/usr/bin/touch")

        let opened = await waitUntil(timeout: 5) { FileManager.default.fileExists(atPath: tricky.path) }
        #expect(opened)
        #expect(!FileManager.default.fileExists(atPath: pwned.path))
    }
}
