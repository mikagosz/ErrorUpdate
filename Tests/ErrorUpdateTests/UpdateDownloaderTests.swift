import Testing
@testable import ErrorUpdate
import Foundation
import CryptoKit

// MARK: - URLProtocol mock

/// Serves a canned response for every request. The payload is registered
/// per-URL in `responses` because URLProtocol instances are created by the system.
private final class TestURLProtocol: URLProtocol {

    nonisolated(unsafe) static var responseData = Data()
    /// Announced `Content-Length`; when nil the real payload length is used.
    nonisolated(unsafe) static var announcedContentLength: Int?
    private static let lock = NSLock()

    static func setResponse(_ data: Data, announcedContentLength: Int? = nil) {
        lock.lock()
        responseData = data
        self.announcedContentLength = announcedContentLength
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.responseData
        let announced = Self.announcedContentLength ?? data.count
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com/update.zip")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/octet-stream",
                "Content-Length": String(announced),
            ]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func testSession(response: Data, announcedContentLength: Int? = nil) -> URLSession {
    TestURLProtocol.setResponse(response, announcedContentLength: announcedContentLength)
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Helpers

private func sha256hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

// MARK: - Tests

@Suite(.serialized) struct UpdateDownloaderTests {
    private func makeConfig(
        publicKey: Data = .init(),
        allowUnsignedUpdates: Bool = true,
        maxDownloadBytes: Int64 = 1_073_741_824
    ) -> ErrorUpdateConfig {
        ErrorUpdateConfig(serverURL: URL(string: "https://example.com/check")!,
                          publicKey: publicKey, allowUnsignedUpdates: allowUnsignedUpdates,
                          maxDownloadBytes: maxDownloadBytes, reportingOptIn: false)
    }

    // MARK: 1. Poprawny SHA-256 + podpis Ed25519 → sukces

    @Test func download_validSha256AndSignature_succeeds() async throws {
        let payload = Data([1, 2, 3, 4])
        let session = testSession(response: payload)
        let keyPair = Curve25519.Signing.PrivateKey()
        let signature = try keyPair.signature(for: payload)
        let sigBase64 = signature.base64EncodedString()

        let config = makeConfig(publicKey: keyPair.publicKey.rawRepresentation)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "New!",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: sigBase64, mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        let url = try await downloader.download(info)
        #expect(url.path.contains("update.zip"))
        let downloaded = try Data(contentsOf: url)
        #expect(downloaded == payload)
    }

    // MARK: 2. Zły SHA-256 → odrzucenie

    @Test func download_wrongSha256_rejected() async {
        let payload = Data([1, 2, 3])
        let session = testSession(response: payload)
        let config = makeConfig()
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: "wrong_hash_1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcd",
            signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected SHA-256 mismatch error")
        } catch {
            #expect(error.localizedDescription.contains("SHA-256 mismatch"))
        }
    }

    // MARK: 3. Poprawny SHA-256, ale zły podpis Ed25519 → odrzucenie

    @Test func download_correctSha256BadSignature_rejected() async throws {
        let payload = Data([1, 2, 3, 4])
        let session = testSession(response: payload)

        // Podpis wygenerowany kluczem A
        let keyPairA = Curve25519.Signing.PrivateKey()
        let signature = try keyPairA.signature(for: payload)
        let sigBase64 = signature.base64EncodedString()

        // Weryfikacja kluczem B (niepasującym)
        let keyPairB = Curve25519.Signing.PrivateKey()

        let config = makeConfig(publicKey: keyPairB.publicKey.rawRepresentation)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "New!",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: sigBase64, mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected signature verification failure")
        } catch {
            #expect(error.localizedDescription.contains("signature verification failed"))
        }
    }

    // MARK: 4. Brak klucza publicznego + jawna rezygnacja → pomija weryfikację podpisu

    @Test func download_noPublicKeyWithOptOut_skipsSignatureCheck() async throws {
        let payload = Data([1, 2, 3])
        let session = testSession(response: payload)
        let config = makeConfig()  // pusty klucz + allowUnsignedUpdates: true
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "not_a_real_signature", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        let url = try await downloader.download(info)
        #expect(url.path.contains("update.zip"))
    }

    // MARK: 5. Klucz publiczny jest, manifest bez podpisu → odrzucenie
    //
    // To jest wariant, który stanowi atak: napastnik kontrolujący manifest
    // pomija pole `signature` i podaje sumę SHA-256 własnego pliku. Suma się
    // zgadza, bo pochodzi z tego samego źródła co plik — jedyną przeszkodą
    // może być podpis, więc jego brak musi być błędem, nie pominięciem.

    @Test func download_publicKeySetManifestWithoutSignature_rejected() async throws {
        let attackerPayload = Data("podmieniony pakiet".utf8)
        let session = testSession(response: attackerPayload)
        let keyPair = Curve25519.Signing.PrivateKey()

        let config = makeConfig(publicKey: keyPair.publicKey.rawRepresentation)
        let info = UpdateInfo(
            latestVersion: "9.9.9", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(attackerPayload),  // pasująca suma — napastnik liczy ją sam
            signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the unsigned manifest to be rejected")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .signatureMissing = error else {
                Issue.record("Expected .signatureMissing, got \(error)")
                return
            }
        }
    }

    // MARK: 6. Ten sam atak przez rzeczywisty JSON bez pola `signature`
    //
    // Dekoder jest celowo tolerancyjny (starsze serwery), więc brakujące pole
    // staje się pustym łańcuchem. Test pilnuje, żeby ta tolerancja nigdy więcej
    // nie przekładała się na pominięcie weryfikacji.

    @Test func download_manifestJSONMissingSignatureField_rejected() async throws {
        let attackerPayload = Data("podmieniony pakiet".utf8)
        let json = """
        {
          "latestVersion": "9.9.9",
          "downloadURL": "https://example.com/update.zip",
          "sha256": "\(sha256hex(attackerPayload))"
        }
        """
        let info = try JSONDecoder().decode(UpdateInfo.self, from: Data(json.utf8))
        #expect(info.signature.isEmpty, "Dekoder ma nadal wczytywać manifest bez podpisu")

        let session = testSession(response: attackerPayload)
        let keyPair = Curve25519.Signing.PrivateKey()
        let config = makeConfig(publicKey: keyPair.publicKey.rawRepresentation)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the unsigned manifest to be rejected")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .signatureMissing = error else {
                Issue.record("Expected .signatureMissing, got \(error)")
                return
            }
        }
    }

    // MARK: 7. Manifest kieruje pobranie na czysty HTTP → odrzucenie
    //
    // Manifest może przyjść po HTTPS i mimo to wskazać adres pobrania po HTTP.
    // Ten adres pochodzi z sieci, więc biblioteka sprawdza go sama.

    @Test func download_insecureDownloadURL_rejected() async throws {
        let payload = Data([1, 2, 3])
        let session = testSession(response: payload)
        let config = makeConfig()
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "http://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the plain-HTTP download URL to be rejected")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .insecureDownloadURL = error else {
                Issue.record("Expected .insecureDownloadURL, got \(error)")
                return
            }
        }
    }

    // MARK: 8. Pobranie z loopbacku po HTTP nadal działa (serwer testowy)

    @Test func download_loopbackOverHTTP_allowed() async throws {
        let payload = Data([9, 8, 7])
        let session = testSession(response: payload)
        let config = makeConfig()
        let info = UpdateInfo(
            latestVersion: "9.9.9", available: true, releaseNotes: "",
            downloadURL: URL(string: "http://127.0.0.1:8000/downloads/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        let url = try await downloader.download(info)
        #expect(try Data(contentsOf: url) == payload)
    }

    // MARK: 9. Plik większy niż limit → odrzucenie

    @Test func download_payloadOverLimit_rejected() async throws {
        let payload = Data(repeating: 7, count: 4096)
        let session = testSession(response: payload)
        let config = makeConfig(maxDownloadBytes: 1024)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the oversized download to be rejected")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .downloadTooLarge = error else {
                Issue.record("Expected .downloadTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: 10. Serwer ogłasza ogromny Content-Length → przerwanie w trakcie
    //
    // Plik jest w rzeczywistości malutki, więc kontrola rozmiaru po pobraniu
    // przepuściłaby go bez mrugnięcia. Odrzucić może go wyłącznie delegat
    // reagujący na zapowiedziany rozmiar — czyli ten test bada tę ścieżkę,
    // a nie zabezpieczenie zapasowe.

    @Test func download_announcedContentLengthOverLimit_cancelledMidTransfer() async throws {
        let payload = Data(repeating: 7, count: 64)
        let session = testSession(response: payload, announcedContentLength: 500_000_000)
        let config = makeConfig(maxDownloadBytes: 1024)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the announced size to abort the download")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .downloadTooLarge = error else {
                Issue.record("Expected .downloadTooLarge, got \(error)")
                return
            }
        }
    }

    // MARK: 11. Plik dokładnie na granicy limitu → przechodzi

    @Test func download_payloadExactlyAtLimit_succeeds() async throws {
        let payload = Data(repeating: 7, count: 1024)
        let session = testSession(response: payload)
        let config = makeConfig(maxDownloadBytes: 1024)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        let url = try await downloader.download(info)
        #expect(try Data(contentsOf: url).count == 1024)
    }

    // MARK: 12. Brak klucza i brak jawnej rezygnacji → odrzucenie przed pobraniem

    @Test func download_noPublicKeyWithoutOptOut_rejected() async throws {
        let payload = Data([1, 2, 3])
        let session = testSession(response: payload)
        let config = makeConfig(allowUnsignedUpdates: false)
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the unverifiable download to be refused")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .unsignedUpdatesNotAllowed = error else {
                Issue.record("Expected .unsignedUpdatesNotAllowed, got \(error)")
                return
            }
        }
    }
}
