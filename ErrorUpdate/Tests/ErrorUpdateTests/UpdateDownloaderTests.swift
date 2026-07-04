import Testing
@testable import ErrorUpdate
import Foundation
import CryptoKit

// MARK: - URLProtocol mock

private struct TestURLProtocol: URLProtocol {
    private let response: (data: Data, response: HTTPURLResponse)

    init(data: Data, statusCode: Int = 200) {
        let headers = ["Content-Type": "application/octet-stream"]
        self.response = (data, HTTPURLResponse(
            url: URL(string: "https://example.com/update.zip")!,
            statusCode: statusCode, httpVersion: nil, headerFields: headers)!)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocol(self, didReceive: response.response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func testSession(response: Data) -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [TestURLProtocol.self]
    return URLSession(configuration: config)
}

// MARK: - Helpers

private func sha256hex(_ data: Data) -> String {
    SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
}

// MARK: - Tests

@Suite struct UpdateDownloaderTests {
    private func makeConfig(publicKey: Data = .init()) -> ErrorUpdateConfig {
        ErrorUpdateConfig(serverURL: URL(string: "https://example.com/check")!,
                          publicKey: publicKey, reportingOptIn: false)
    }

    // MARK: 1. Poprawny SHA-256 + podpis Ed25519 → sukces

    @Test func download_validSha256AndSignature_succeeds() async throws {
        let payload = Data([1, 2, 3, 4])
        let session = testSession(response: payload)
        let keyPair = try Curve25519.Signing.PrivateKey()
        let signature = try keyPair.signature(for: payload)
        let sigBase64 = signature.rawRepresentation.base64EncodedString()
        let pubKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyPair.publicKey.rawRepresentation)

        let config = makeConfig(publicKey: pubKey.rawRepresentation)
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

    @Test func download_correctSha256BadSignature_rejected() async {
        let payload = Data([1, 2, 3, 4])
        let session = testSession(response: payload)

        // Podpis wygenerowany kluczem A
        let keyPairA = try! Curve25519.Signing.PrivateKey()
        let signature = try! keyPairA.signature(for: payload)
        let sigBase64 = signature.rawRepresentation.base64EncodedString()

        // Weryfikacja kluczem B (niepasującym)
        let keyPairB = try! Curve25519.Signing.PrivateKey()
        let wrongPubKey = try! Curve25519.Signing.PublicKey(rawRepresentation: keyPairB.publicKey.rawRepresentation)

        let config = makeConfig(publicKey: wrongPubKey.rawRepresentation)
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

    // MARK: Brak klucza publicznego → pomija weryfikację podpisu

    @Test func download_noPublicKey_skipsSignatureCheck() async throws {
        let payload = Data([1, 2, 3])
        let session = testSession(response: payload)
        let config = makeConfig()  // pusty klucz
        let info = UpdateInfo(
            latestVersion: "2.0.0", available: true, releaseNotes: "",
            downloadURL: URL(string: "https://example.com/update.zip")!,
            sha256: sha256hex(payload), signature: "not_a_real_signature", mandatory: false)

        let downloader = UpdateDownloader(config: config, session: session)
        let url = try await downloader.download(info)
        #expect(url.path.contains("update.zip"))
    }
}
