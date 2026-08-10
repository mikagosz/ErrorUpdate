//
//  UpdateDownloader.swift
//  ErrorUpdate
//

import Foundation
import CryptoKit

/// Downloads update files and verifies them via SHA-256 checksum and,
/// when a public key is configured, an Ed25519 signature.
public final class UpdateDownloader: Sendable {

    public enum DownloadError: LocalizedError {
        case sha256Mismatch(expected: String, actual: String)
        case insecureDownloadURL(URL)
        case downloadTooLarge(limit: Int64)
        case signatureMissing
        case unsignedUpdatesNotAllowed
        case invalidSignatureFormat
        case signatureVerificationFailed
        case invalidPublicKey(Error)

        public var errorDescription: String? {
            switch self {
            case .sha256Mismatch(let expected, let actual):
                return "SHA-256 mismatch: expected \(expected), got \(actual)"
            case .insecureDownloadURL(let url):
                return "Refusing to download over an insecure connection: \(URLSecurity.rejectionReason(for: url))"
            case .downloadTooLarge(let limit):
                return "The update exceeds the maximum download size of \(limit) bytes."
            case .signatureMissing:
                return "The update manifest carries no Ed25519 signature while a public key is configured — refusing the update."
            case .unsignedUpdatesNotAllowed:
                return "No Ed25519 public key configured. Set `publicKey`, or opt out explicitly with `allowUnsignedUpdates: true`."
            case .invalidSignatureFormat:
                return "Invalid signature format (expected 64-byte Base64)"
            case .signatureVerificationFailed:
                return "Ed25519 signature verification failed"
            case .invalidPublicKey(let error):
                return "Invalid public key: \(error.localizedDescription)"
            }
        }
    }

    private let config: ErrorUpdateConfig
    private let session: URLSession
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2

    public init(config: ErrorUpdateConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Downloads the update file from `info.downloadURL` and verifies it.
    /// Returns the URL of the verified file; throws on any verification failure.
    /// Network failures are retried with exponential backoff.
    public func download(_ info: UpdateInfo) async throws -> URL {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await downloadAndVerify(info)
            } catch let error as DownloadError {
                // Verification failures are not transient — do not retry.
                throw error
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? URLError(.unknown)
    }

    private func downloadAndVerify(_ info: UpdateInfo) async throws -> URL {
        // Refuse before spending bandwidth: without a public key nothing about
        // the file's origin can be established, so this needs a deliberate opt-in.
        guard !config.publicKey.isEmpty || config.allowUnsignedUpdates else {
            throw DownloadError.unsignedUpdatesNotAllowed
        }

        // The download URL arrives from the network, so a manifest served over
        // HTTPS could still steer the download itself onto plain HTTP.
        guard URLSecurity.isAcceptable(info.downloadURL) else {
            throw DownloadError.insecureDownloadURL(info.downloadURL)
        }

        // A unique directory per download avoids collisions between attempts.
        let downloadDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_download")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let fileName = info.downloadURL.lastPathComponent.isEmpty ? "update" : info.downloadURL.lastPathComponent
        let destinationURL = downloadDir.appendingPathComponent(fileName)

        // Nothing can be verified until the file is on disk, so the size has to
        // be bounded while the file is still arriving.
        let response: URLResponse
        do {
            response = try await SizeLimitedDownload(limit: config.maxDownloadBytes,
                                                     destinationURL: destinationURL)
                .run(url: info.downloadURL, configuration: session.configuration)
        } catch {
            try? FileManager.default.removeItem(at: downloadDir)
            throw error
        }

        do {
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw ServerClient.ServerError.httpError(statusCode: httpResponse.statusCode)
            }

            // Belt and braces: a body delivered in one piece can outrun the
            // progress callbacks entirely.
            let size = try Self.fileSize(of: destinationURL)
            guard size <= config.maxDownloadBytes else {
                throw DownloadError.downloadTooLarge(limit: config.maxDownloadBytes)
            }

            // 1. Verify SHA-256 (streamed, so large files never sit in memory).
            let actualSHA256 = try Self.sha256(of: destinationURL)
            guard actualSHA256.lowercased() == info.sha256.lowercased() else {
                throw DownloadError.sha256Mismatch(expected: info.sha256, actual: actualSHA256)
            }

            // 2. Verify the Ed25519 signature.
            //
            // Whether an update has to be signed is decided by the app alone.
            // A manifest that simply omits `signature` must never be able to
            // switch verification off — that would hand the decision to the
            // very party the signature protects against.
            if !config.publicKey.isEmpty {
                guard !info.signature.isEmpty else {
                    throw DownloadError.signatureMissing
                }
                try Self.verifySignature(for: destinationURL, signature: info.signature, publicKey: config.publicKey)
            }

            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: downloadDir)
            throw error
        }
    }

    static func fileSize(of url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Streams the file through SHA-256 in 1 MB chunks.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func verifySignature(for fileURL: URL, signature base64Signature: String, publicKey: Data) throws {
        guard let signatureData = Data(base64Encoded: base64Signature),
              signatureData.count == 64 else {
            throw DownloadError.invalidSignatureFormat
        }

        let key: Curve25519.Signing.PublicKey
        do {
            key = try Curve25519.Signing.PublicKey(rawRepresentation: publicKey)
        } catch {
            throw DownloadError.invalidPublicKey(error)
        }

        // Ed25519 has no streaming API — the whole message has to be available
        // at once. Memory-mapping keeps it out of the process's memory anyway:
        // the kernel pages the file in as CryptoKit reads it, so verification
        // costs the same for a 20 MB update as for a 1 GB one. `.mappedIfSafe`
        // falls back to a plain read when the file cannot be mapped safely.
        let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard key.isValidSignature(signatureData, for: fileData) else {
            throw DownloadError.signatureVerificationFailed
        }
    }
}

/// Downloads a file, cancelling the transfer as soon as it passes `limit`, so an
/// oversized update never finishes landing on the user's disk.
///
/// This runs its own `URLSession` on purpose: a delegate handed to the async
/// `download(from:delegate:)` never receives `URLSessionDownloadDelegate`
/// progress callbacks, so a limit enforced that way would only ever be noticed
/// after the whole file had already been written. The session is built from the
/// caller's configuration, which keeps injected settings (and test protocols)
/// in force.
private final class SizeLimitedDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {

    private let limit: Int64
    private let destinationURL: URL

    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var exceededLimit = false
    private var failure: Error?
    private var response: URLResponse?

    init(limit: Int64, destinationURL: URL) {
        self.limit = limit
        self.destinationURL = destinationURL
    }

    func run(url: URL, configuration: URLSessionConfiguration) async throws -> URLResponse {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // `totalBytesExpectedToWrite` is the announced Content-Length, which
        // stops an oversized file before it starts; the written count covers
        // servers that announce nothing.
        guard totalBytesExpectedToWrite > limit || totalBytesWritten > limit else { return }

        lock.lock()
        exceededLimit = true
        lock.unlock()
        downloadTask.cancel()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // The file at `location` is deleted as soon as this returns, so it has
        // to be moved here rather than after the continuation resumes.
        do {
            try FileManager.default.moveItem(at: location, to: destinationURL)
            lock.lock()
            response = downloadTask.response
            lock.unlock()
        } catch {
            lock.lock()
            failure = error
            lock.unlock()
        }
    }

    // Always the last callback, so the continuation resumes exactly once.
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let exceeded = exceededLimit
        let failure = self.failure
        let response = self.response
        lock.unlock()

        guard let continuation else { return }

        if exceeded {
            continuation.resume(throwing: UpdateDownloader.DownloadError.downloadTooLarge(limit: limit))
        } else if let error {
            continuation.resume(throwing: error)
        } else if let failure {
            continuation.resume(throwing: failure)
        } else if let response {
            continuation.resume(returning: response)
        } else {
            continuation.resume(throwing: URLError(.unknown))
        }
    }
}
