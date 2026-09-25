import Testing
@testable import ErrorUpdate
import Foundation

// MARK: - Manifest stub

/// Serves one fixed manifest, whatever the URL.
private final class StateManifestURLProtocol: URLProtocol {

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

/// The `availableUpdate` state **in the manager**.
///
/// Gap spotted 2026-08-10: the fix for "a periodic check wipes the update it just
/// found" removed an unconditional `availableUpdate = info` in the manager, but the
/// regression test landed one floor below — it only checked that the *checker* returns
/// `.notChecked`. Restoring the old assignment in the manager still passed green.
///
/// These tests run against their **own instance** of the manager and their own
/// `UserDefaults`, because the singleton and the keys in `.standard` are shared by every
/// suite, and suites run in parallel.
@MainActor
@Suite(.serialized) struct ManagerUpdateStateTests {

    private let janitor = DefaultsJanitor()

    private func makeManager() -> (ErrorUpdateManager, UserDefaults) {
        let sessionConfiguration = URLSessionConfiguration.ephemeral
        sessionConfiguration.protocolClasses = [StateManifestURLProtocol.self]
        let session = URLSession(configuration: sessionConfiguration)

        let defaults = janitor.make("ErrorUpdateManagerState")
        let manager = ErrorUpdateManager()
        manager.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                              allowUnsignedUpdates: true),
            session: session,
            userDefaults: defaults
        )
        return (manager, defaults)
    }

    // MARK: 1. A found update survives a periodic check

    /// Exactly the sequence from the original report: the user presses "check", sees a
    /// version, and a periodic check starts moments later against a fresh cache.
    @Test func foundUpdate_survivesPeriodicCheck() async {
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let (manager, _) = makeManager()

        await manager.checkForUpdates(force: true)
        #expect(manager.availableUpdate?.latestVersion == "2.0.0",
                "Precondition: a forced check must find the version")

        // The cache is fresh after the previous check, so the checker answers
        // "did not check" — which is not an answer of "there is no update".
        await manager.checkForUpdates(force: false)

        #expect(manager.availableUpdate?.latestVersion == "2.0.0",
                "A periodic check must not wipe an update that was already found")
    }

    // MARK: 2. A withdrawn release still clears the prompt

    /// The other side of the same fix: "did not check" leaves the state alone, but the
    /// server answering "I am not offering this version" **must** clear it. Without this
    /// an `if let` would look sufficient, and it is not.
    @Test func withdrawnRelease_clearsPrompt() async {
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let (manager, defaults) = makeManager()

        await manager.checkForUpdates(force: true)
        #expect(manager.availableUpdate != nil, "Precondition: the prompt is there")

        // The server withdraws the release; clear the cache so the question really goes out.
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        defaults.removeObject(forKey: "ErrorUpdate_LastUpdateCheckDate")

        await manager.checkForUpdates(force: false)

        #expect(manager.availableUpdate == nil,
                "A withdrawn release must clear the prompt, not stay on screen")
    }
}
