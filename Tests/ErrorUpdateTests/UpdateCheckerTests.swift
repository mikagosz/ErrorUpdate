import Testing
@testable import ErrorUpdate
import Foundation

// MARK: - Manifest mock

/// Serves a fixed version-check manifest.
private final class ManifestURLProtocol: URLProtocol {

    nonisolated(unsafe) private static var manifest = Data()
    private static let lock = NSLock()

    static func setManifest(latestVersion: String, available: Bool = true) {
        let json = """
        {
          "latestVersion": "\(latestVersion)",
          "available": \(available),
          "downloadURL": "https://example.com/update.zip",
          "sha256": "\(String(repeating: "0", count: 64))",
          "signature": "",
          "mandatory": false
        }
        """
        lock.lock()
        manifest = Data(json.utf8)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.manifest
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

@Suite(.serialized) struct UpdateCheckerTests {

    /// Fresh defaults per test, so neither the 1-hour cache nor a skipped
    /// version leaks between cases.
    private func makeDefaults() -> UserDefaults {
        let suiteName = "ErrorUpdateTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suiteName)!
    }

    private func makeChecker(
        currentVersion: String = "1.0.0",
        defaults: UserDefaults
    ) -> UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ManifestURLProtocol.self]
        let session = URLSession(configuration: configuration)

        let config = ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                                       allowUnsignedUpdates: true)
        let client = ServerClient(config: config, currentVersion: currentVersion, session: session)
        return UpdateChecker(serverClient: client, currentVersion: currentVersion,
                             userDefaults: defaults)
    }

    // MARK: 1. A newer version nobody skipped is reported

    @Test func newerVersion_isReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let checker = makeChecker(defaults: makeDefaults())

        let result = try await checker.checkForUpdates(force: true)
        #expect(result.info?.latestVersion == "2.0.0")
    }

    // MARK: 2. A skipped version stays away on an automatic check

    @Test func skippedVersion_isNotReportedOnPeriodicCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: false)
        #expect(result == .noUpdate, "The prompt must not come back with a version the user dismissed")
    }

    // MARK: 3. A check the user asked for overrides the dismissal

    @Test func skippedVersion_isReportedOnForcedCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: true)
        #expect(result.info?.latestVersion == "2.0.0",
                "Someone who asks for a check wants the answer")
    }

    // MARK: 4. A version newer than the skipped one shows up as usual

    @Test func versionNewerThanSkipped_isReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.1.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: false)
        #expect(result.info?.latestVersion == "2.1.0",
                "One click must not mute updates for good")
    }

    // MARK: 5. A manifest with available: false offers nothing

    @Test func unavailableUpdate_isNotReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        let checker = makeChecker(defaults: makeDefaults())

        let result = try await checker.checkForUpdates(force: false)
        #expect(result == .noUpdate, "The server said available: false — no prompt should appear")
    }

    // MARK: 6. available: false holds even for a forced check
    //
    // Unlike a skipped version, where the user decides: here it is the server,
    // which simply has not released that version yet.

    @Test func unavailableUpdate_isNotReportedEvenWhenForced() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        let checker = makeChecker(defaults: makeDefaults())

        let result = try await checker.checkForUpdates(force: true)
        #expect(result == .noUpdate)
    }

    // MARK: 7. A version older than the skipped one stays silenced

    @Test func versionOlderThanSkipped_staysSuppressed() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "1.5.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: false)
        #expect(result == .noUpdate)
    }

    // MARK: 8. A fresh cache means "did not check", not "no update"
    //
    // Regression found while driving a host app through an automation bridge
    // (2026-08-09): a check the user asked for found an update, and the periodic
    // check starting moments later wiped it off the screen because it hit the
    // still-fresh cache.

    @Test func freshCache_reportsNotChecked() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        let checker = makeChecker(defaults: defaults)

        // 1. The user's own check — finds the update and stamps the date.
        let forced = try await checker.checkForUpdates(force: true)
        #expect(forced.info?.latestVersion == "2.0.0")

        // 2. The periodic check right after — the cache is still fresh.
        let periodic = try await checker.checkForUpdates(force: false)
        #expect(periodic == .notChecked,
                "A skipped check must not pose as the answer \"no update\"")
        #expect(periodic.info == nil)
    }

    // MARK: 9. A version that installed without effect is not offered again
    //
    // The update loop from that same bridge test: the bundle was swapped, the
    // version in Info.plist stayed, so every later check offers the same thing.

    @Test func ineffectiveVersion_isNotOfferedOnPeriodicCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        InstalledVersionStore(defaults: defaults).markIneffective("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: false)
        guard case .ineffective(let info) = result else {
            Issue.record("An ineffective version needs its own verdict, not \(result)")
            return
        }
        #expect(info.latestVersion == "2.0.0", "The verdict carries the version so it can be reported")
        #expect(result.info == nil, "…but it does not reach the UI as available")
    }

    // MARK: 10. A forced check still shows it
    //
    // The release may have been repackaged under the same number since.

    @Test func ineffectiveVersion_isStillOfferedOnForcedCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        InstalledVersionStore(defaults: defaults).markIneffective("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: true)
        #expect(result.info?.latestVersion == "2.0.0")
    }

    // MARK: 11. A newer release does not inherit the broken one's silence

    @Test func versionNewerThanIneffective_isOfferedNormally() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.1.0")
        let defaults = makeDefaults()
        InstalledVersionStore(defaults: defaults).markIneffective("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let result = try await checker.checkForUpdates(force: false)
        #expect(result.info?.latestVersion == "2.1.0")
    }

    // MARK: 12. The verdict on whether an install took effect

    @Test func installVerdict_comparesPromiseWithRunningVersion() {
        #expect(InstalledVersionStore.verdict(expected: "2.0.0", actual: "1.0") == .ineffective,
                "Promised 2.0.0, running 1.0 — the install changed nothing")
        #expect(InstalledVersionStore.verdict(expected: "2.0.0", actual: "2.0.0") == .tookEffect)
        #expect(InstalledVersionStore.verdict(expected: "2.0.0", actual: "2.1.0") == .tookEffect,
                "A manual upgrade in the meantime is not a broken release")
    }

    // MARK: 13. The silence covers exactly one version

    @Test func ineffectiveMark_appliesToThatVersionOnly() {
        let store = InstalledVersionStore(defaults: makeDefaults())
        store.markIneffective("2.0.0")

        #expect(store.isKnownIneffective("2.0.0"))
        #expect(!store.isKnownIneffective("2.0.1"))
        #expect(!store.isKnownIneffective("1.9.0"))

        store.clearIneffective()
        #expect(!store.isKnownIneffective("2.0.0"))
    }
}
