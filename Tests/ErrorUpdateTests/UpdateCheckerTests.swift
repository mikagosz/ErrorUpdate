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

    // MARK: 1. Nowsza wersja bez pominięcia → zgłaszana

    @Test func newerVersion_isReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let checker = makeChecker(defaults: makeDefaults())

        let info = try await checker.checkForUpdates(force: true)
        #expect(info?.latestVersion == "2.0.0")
    }

    // MARK: 2. Pominięta wersja nie wraca przy sprawdzeniu automatycznym

    @Test func skippedVersion_isNotReportedOnPeriodicCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let info = try await checker.checkForUpdates(force: false)
        #expect(info == nil, "Okno nie ma wracać z wersją, którą użytkownik odrzucił")
    }

    // MARK: 3. Sprawdzenie wymuszone przez użytkownika ignoruje pominięcie

    @Test func skippedVersion_isReportedOnForcedCheck() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let info = try await checker.checkForUpdates(force: true)
        #expect(info?.latestVersion == "2.0.0", "Kto sam prosi o sprawdzenie, chce zobaczyć wynik")
    }

    // MARK: 4. Wersja nowsza od pominiętej pokazuje się normalnie

    @Test func versionNewerThanSkipped_isReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.1.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let info = try await checker.checkForUpdates(force: false)
        #expect(info?.latestVersion == "2.1.0",
                "Jedno kliknięcie nie może wyciszyć aktualizacji na zawsze")
    }

    // MARK: 5. Manifest z available: false → brak aktualizacji

    @Test func unavailableUpdate_isNotReported() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        let checker = makeChecker(defaults: makeDefaults())

        let info = try await checker.checkForUpdates(force: false)
        #expect(info == nil, "Serwer ogłosił available: false — okno nie ma się pojawić")
    }

    // MARK: 6. available: false obowiązuje też przy sprawdzeniu wymuszonym
    //
    // Inaczej niż pominięcie wersji: tam decyduje użytkownik, tutaj serwer,
    // który po prostu jeszcze nie wydał tej wersji.

    @Test func unavailableUpdate_isNotReportedEvenWhenForced() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        let checker = makeChecker(defaults: makeDefaults())

        let info = try await checker.checkForUpdates(force: true)
        #expect(info == nil)
    }

    // MARK: 7. Wersja starsza od pominiętej pozostaje wyciszona

    @Test func versionOlderThanSkipped_staysSuppressed() async throws {
        ManifestURLProtocol.setManifest(latestVersion: "1.5.0")
        let defaults = makeDefaults()
        SkippedVersionStore(defaults: defaults).skip("2.0.0")

        let checker = makeChecker(defaults: defaults)
        let info = try await checker.checkForUpdates(force: false)
        #expect(info == nil)
    }
}
