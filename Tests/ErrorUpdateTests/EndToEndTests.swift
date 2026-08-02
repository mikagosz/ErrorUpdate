import Testing
@testable import ErrorUpdate
import Foundation

/// Full check → download → verify → install cycle against a real local HTTP server.
///
/// Skipped unless `ERRORUPDATE_E2E_SERVER` is set. To run (from the repo root):
/// ```bash
/// ./TestServer/prepare.sh
/// (cd TestServer/www && python3 -m http.server 8000) &
/// ERRORUPDATE_E2E_SERVER=http://127.0.0.1:8000 \
/// ERRORUPDATE_E2E_PUBKEY=$(cat keys/errorupdate_public_key.txt) \
/// swift test --filter EndToEndTests
/// ```
@Suite struct EndToEndTests {

    static var serverURL: URL? {
        ProcessInfo.processInfo.environment["ERRORUPDATE_E2E_SERVER"].flatMap(URL.init)
    }

    @Test(.enabled(if: serverURL != nil), .timeLimit(.minutes(1)))
    func fullUpdateCycle() async throws {
        let serverURL = try #require(Self.serverURL)
        let publicKey = ProcessInfo.processInfo.environment["ERRORUPDATE_E2E_PUBKEY"]
            .flatMap { Data(base64Encoded: $0.trimmingCharacters(in: .whitespacesAndNewlines)) } ?? Data()

        // Without ERRORUPDATE_E2E_PUBKEY the run exercises the explicitly
        // unverified path; with it, signatures are mandatory.
        let config = ErrorUpdateConfig(serverURL: serverURL, publicKey: publicKey,
                                       allowUnsignedUpdates: publicKey.isEmpty)
        let client = ServerClient(config: config, currentVersion: "1.0")
        let checker = UpdateChecker(serverClient: client, currentVersion: "1.0")

        // 1. Version check against the real server
        let info = try #require(try await checker.checkForUpdates(force: true))
        #expect(info.latestVersion == "9.9.9")
        if !publicKey.isEmpty {
            #expect(!info.signature.isEmpty, "Manifest should carry an Ed25519 signature")
        }

        // 2. Download with SHA-256 (and Ed25519) verification
        let downloader = UpdateDownloader(config: config)
        let file = try await downloader.download(info)
        #expect(FileManager.default.fileExists(atPath: file.path))

        // 3. Install (codesign verification + swap) into a temp directory
        let installDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_e2e_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: installDir)
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
        }

        // Bez punktu odniesienia instalator pomija kontrolę identyfikatora i podpisu,
        // bo host testów nie jest pakietem .app. Wskazanie zbudowanej aplikacji demo
        // sprawia, że pełny cykl przechodzi też przez `codesign -R`.
        let currentAppURL = ProcessInfo.processInfo.environment["ERRORUPDATE_E2E_CURRENT_APP"]
            .map { URL(fileURLWithPath: $0) }
        let installer = UpdateInstaller(currentAppURL: currentAppURL)
        let installedApp = try installer.install(file, into: installDir)
        #expect(installedApp.pathExtension == "app")
        #expect(FileManager.default.fileExists(
            atPath: installedApp.appendingPathComponent("Contents/Info.plist").path))

        // 4. Installing again replaces the existing copy (backup path)
        let replacedApp = try installer.install(file, into: installDir)
        #expect(replacedApp.standardizedFileURL.path == installedApp.standardizedFileURL.path)
    }
}
