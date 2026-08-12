import Testing
@testable import ErrorUpdate
import Foundation

// Regression 2026-08-12: a version check could be answered from `URLCache` without
// ever reaching the server. A release pulled back with `"available": false` kept
// being offered, and a *forced* check — the one a user explicitly asks for — found
// an update the server was not offering. Measured on the demo app: with the HTTP
// cache present the check made **zero** network requests; after deleting the cache
// the very same setup behaved correctly.
//
// The app-level one-hour cache is deliberate and `force` bypasses it. This second,
// invisible cache was neither deliberate nor bypassable, so the fix pins the policy
// on the request itself.

/// Records the request it was handed, then answers with a canned body.
private final class CapturingURLProtocol: URLProtocol {

    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var body = Data()
    private static let lock = NSLock()

    static func arm(body: Data) {
        lock.lock()
        self.body = body
        lastRequest = nil
        lock.unlock()
    }

    static var captured: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return lastRequest
    }

    override class func canInit(with request: URLRequest) -> Bool {
        lock.lock()
        lastRequest = request
        lock.unlock()
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.body
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func manifest(available: Bool) -> Data {
    let json = """
    {
      "available": \(available),
      "latestVersion": "9.9.9",
      "releaseNotes": "test",
      "downloadURL": "https://example.com/x.zip",
      "sha256": "00",
      "mandatory": false
    }
    """
    return Data(json.utf8)
}

private func client(body: Data) -> ServerClient {
    CapturingURLProtocol.arm(body: body)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [CapturingURLProtocol.self]
    let config = ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!)
    return ServerClient(
        config: config,
        currentVersion: "1.0",
        session: URLSession(configuration: configuration)
    )
}

// `.serialized` is not decoration: the stub keeps the response body in a static
// property, and Swift Testing runs tests in PARALLEL by default. Without it the two
// tests overwrite each other's manifest and the second one reads the first one's —
// the very first run of this suite failed exactly there, on healthy production code.
@Suite(.serialized) struct VersionCheckCacheTests {

    @Test func versionCheckIgnoresLocalCache() async throws {
        _ = try await client(body: manifest(available: true)).fetchVersionInfo()

        let request = try #require(CapturingURLProtocol.captured)
        #expect(
            request.cachePolicy == .reloadIgnoringLocalCacheData,
            """
            A version check asks about STATE, not about a resource — an answer from \
            the cache means a withdrawn release keeps being offered. Measured \
            2026-08-12: under the default policy the check never touched the server.
            """
        )
    }

    @Test
    func withdrawnReleaseIsUnavailable() async throws {
        let info = try await client(body: manifest(available: false)).fetchVersionInfo()
        #expect(info.available == false)
        #expect(info.latestVersion == "9.9.9")
    }
}
