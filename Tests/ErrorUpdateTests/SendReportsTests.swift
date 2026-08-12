import Testing
@testable import ErrorUpdate
import Foundation

// MARK: - Report server stub

/// Records the reports it was sent and answers with whatever `statusCode` says.
private final class ReportURLProtocol: URLProtocol {

    nonisolated(unsafe) private static var bodies: [Data] = []
    nonisolated(unsafe) private static var statusCode = 200
    private static let lock = NSLock()

    static func reset(statusCode: Int = 200) {
        lock.lock()
        bodies = []
        self.statusCode = statusCode
        lock.unlock()
    }

    static var sentReports: [Data] {
        lock.lock(); defer { lock.unlock() }
        return bodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("report") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // httpBody is sometimes empty once the request has been through URLSession —
        // the body then lives in the stream, and that is the only place to read it.
        if let body = request.httpBody {
            Self.lock.lock(); Self.bodies.append(body); Self.lock.unlock()
        } else if let stream = request.httpBodyStream {
            stream.open()
            var received = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                received.append(contentsOf: buffer[0..<count])
            }
            stream.close()
            Self.lock.lock(); Self.bodies.append(received); Self.lock.unlock()
        }

        Self.lock.lock()
        let code = Self.statusCode
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: code,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Tests

/// Submitting queued reports to the server.
///
/// Until 2026-08-10 this path had **no test at all**: `TestServer` only served
/// `version-check`, so `sendPendingReports()` had nowhere to go, and four integrations
/// of the framework into real applications never touched it. The queue after a *failed*
/// submission was covered; after a successful one it was not.
@MainActor
@Suite(.serialized) struct SendReportsTests {

    private func makeManager(store: ReportStore) throws -> ErrorUpdateManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReportURLProtocol.self]

        let manager = ErrorUpdateManager()
        manager.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                              allowUnsignedUpdates: true),
            session: URLSession(configuration: configuration),
            userDefaults: UserDefaults(suiteName: "ErrorUpdateSend-\(UUID().uuidString)")!
        )
        // Our own store in a temporary directory: the default one is shared by every
        // suite, and suites run in parallel. It must be the **same instance** the test
        // writes to — two `ReportStore`s over one directory keep separate caches and do
        // not see each other's writes.
        manager.useReportStoreForTesting(store)
        return manager
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("send-test-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: 1. A successful submission empties the queue

    @Test func successfulSubmission_emptiesQueueAndReachesServer() async throws {
        ReportURLProtocol.reset(statusCode: 200)
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try ReportStore(directory: directory)
        store.save(ErrorReport(errorMessage: "report to submit"))
        _ = store.fetchAll()                      // settles the write
        let manager = try makeManager(store: store)
        #expect(manager.pendingReportsCount == 1, "Precondition: one report queued")

        await manager.sendPendingReports()

        #expect(manager.pendingReportsCount == 0,
                "Once the server has accepted it, the report must not stay queued")

        let sent = ReportURLProtocol.sentReports
        #expect(sent.count == 1, "The server must receive exactly one report")
        let body = String(data: sent.first ?? Data(), encoding: .utf8) ?? ""
        #expect(body.contains("report to submit"),
                "The report's content must reach the server, not an empty shell")
    }

    // MARK: 2. A server refusal leaves the report queued

    /// This side had already been checked by measurement (a server with no endpoint) but
    /// not by a test — and it is the side that decides whether a user's report is lost.
    @Test func serverRefusal_leavesReportQueued() async throws {
        ReportURLProtocol.reset(statusCode: 500)
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try ReportStore(directory: directory)
        store.save(ErrorReport(errorMessage: "report that must survive"))
        _ = store.fetchAll()
        let manager = try makeManager(store: store)

        await manager.sendPendingReports()

        #expect(manager.pendingReportsCount == 1,
                "A report the server rejected stays for the next attempt")
    }
}
