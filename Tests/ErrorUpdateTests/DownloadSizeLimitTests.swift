import Testing
@testable import ErrorUpdate
import Foundation
import Network
import CryptoKit

// MARK: - Loopback HTTP server

/// A minimal HTTP server on 127.0.0.1 that streams a payload in chunks.
///
/// The `URLProtocol` mock used by the other download tests never delivers
/// progress callbacks, so it cannot exercise the size limit at all — only a
/// real transfer can show that an oversized download is cut off while it is
/// still arriving, rather than merely rejected once it has landed on disk.
private final class SlowHTTPServer: @unchecked Sendable {

    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.errorupdate.tests.httpserver")
    private let totalBytes: Int
    private let announceContentLength: Bool
    private let chunkSize = 64 * 1024

    private let lock = NSLock()
    private var _bytesSent = 0

    /// How much of the payload actually left the server before the client hung up.
    var bytesSent: Int {
        lock.lock()
        defer { lock.unlock() }
        return _bytesSent
    }

    private(set) var port: UInt16 = 0

    init(totalBytes: Int, announceContentLength: Bool = true) throws {
        self.totalBytes = totalBytes
        self.announceContentLength = announceContentLength

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)

        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)

        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
            listener.cancel()
            throw ServerError.didNotStart
        }
        self.port = port.rawValue
    }

    enum ServerError: Error { case didNotStart }

    var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    func stop() {
        listener.cancel()
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        // Read the request line, then start answering.
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] _, _, _, _ in
            guard let self else { return }

            var header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            if self.announceContentLength {
                header += "Content-Length: \(self.totalBytes)\r\n"
            }
            header += "Connection: close\r\n\r\n"

            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
                guard error == nil else { connection.cancel(); return }
                self?.sendBody(on: connection, remaining: self?.totalBytes ?? 0)
            })
        }
    }

    private func sendBody(on connection: NWConnection, remaining: Int) {
        guard remaining > 0 else {
            connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }

        let size = min(chunkSize, remaining)
        let chunk = Data(repeating: 0x41, count: size)

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            guard error == nil else { connection.cancel(); return }

            self.lock.lock()
            self._bytesSent += size
            self.lock.unlock()

            // A short pause keeps the transfer long enough to be interrupted.
            self.queue.asyncAfter(deadline: .now() + 0.005) {
                self.sendBody(on: connection, remaining: remaining - size)
            }
        })
    }
}

// MARK: - Tests

@Suite(.serialized) struct DownloadSizeLimitTests {

    private func makeConfig(maxDownloadBytes: Int64) -> ErrorUpdateConfig {
        ErrorUpdateConfig(serverURL: URL(string: "https://example.com/check")!,
                          allowUnsignedUpdates: true, maxDownloadBytes: maxDownloadBytes)
    }

    private func makeInfo(url: URL) -> UpdateInfo {
        UpdateInfo(
            latestVersion: "9.9.9", available: true, releaseNotes: "",
            downloadURL: url,
            // Nieistotna — pobranie ma polec, zanim dojdzie do liczenia sumy.
            sha256: String(repeating: "0", count: 64), signature: "", mandatory: false)
    }

    // MARK: 1. Zapowiedziany Content-Length ponad limit → zerwanie na starcie

    @Test(.timeLimit(.minutes(1)))
    func announcedContentLengthOverLimit_abortsBeforeDownloadingEverything() async throws {
        let payloadSize = 8 * 1024 * 1024   // 8 MB
        let server = try SlowHTTPServer(totalBytes: payloadSize)
        defer { server.stop() }

        let config = makeConfig(maxDownloadBytes: 64 * 1024)   // 64 KB
        let downloader = UpdateDownloader(config: config)
        let info = makeInfo(url: server.baseURL.appendingPathComponent("update.zip"))

        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the oversized download to be refused")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .downloadTooLarge = error else {
                Issue.record("Expected .downloadTooLarge, got \(error)")
                return
            }
        }

        // Sedno sprawy: plik nigdy nie dojechał w całości na dysk użytkownika.
        #expect(server.bytesSent < payloadSize,
                "Serwer wysłał \(server.bytesSent) z \(payloadSize) bajtów — pobranie nie zostało przerwane")
    }

    // MARK: 2. Serwer nie podaje Content-Length → zerwanie po przekroczeniu limitu

    @Test(.timeLimit(.minutes(1)))
    func unannouncedOversizedBody_abortsOnceLimitIsPassed() async throws {
        let payloadSize = 8 * 1024 * 1024
        let server = try SlowHTTPServer(totalBytes: payloadSize, announceContentLength: false)
        defer { server.stop() }

        let limit: Int64 = 128 * 1024
        let config = makeConfig(maxDownloadBytes: limit)
        let downloader = UpdateDownloader(config: config)
        let info = makeInfo(url: server.baseURL.appendingPathComponent("update.zip"))

        do {
            _ = try await downloader.download(info)
            Issue.record("Expected the oversized download to be refused")
        } catch let error as UpdateDownloader.DownloadError {
            guard case .downloadTooLarge = error else {
                Issue.record("Expected .downloadTooLarge, got \(error)")
                return
            }
        }

        #expect(server.bytesSent < payloadSize,
                "Serwer wysłał \(server.bytesSent) z \(payloadSize) bajtów — pobranie nie zostało przerwane")
    }

    // MARK: 3. Plik mieszczący się w limicie przechodzi przez tę samą ścieżkę

    @Test(.timeLimit(.minutes(1)))
    func payloadWithinLimit_downloadsCompletely() async throws {
        let payloadSize = 128 * 1024
        let server = try SlowHTTPServer(totalBytes: payloadSize)
        defer { server.stop() }

        let expected = Data(repeating: 0x41, count: payloadSize)
        let config = makeConfig(maxDownloadBytes: 1024 * 1024)
        let downloader = UpdateDownloader(config: config)
        let info = UpdateInfo(
            latestVersion: "9.9.9", available: true, releaseNotes: "",
            downloadURL: server.baseURL.appendingPathComponent("update.zip"),
            sha256: SHA256.hash(data: expected).map { String(format: "%02x", $0) }.joined(),
            signature: "", mandatory: false)

        let url = try await downloader.download(info)
        #expect(try Data(contentsOf: url).count == payloadSize)
    }
}
