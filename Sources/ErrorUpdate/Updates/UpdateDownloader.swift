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
        case invalidSignatureFormat
        case signatureVerificationFailed
        case invalidPublicKey(Error)

        public var errorDescription: String? {
            switch self {
            case .sha256Mismatch(let expected, let actual):
                return "SHA-256 mismatch: expected \(expected), got \(actual)"
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
        // A unique directory per download avoids collisions between attempts.
        let downloadDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_download")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let fileName = info.downloadURL.lastPathComponent.isEmpty ? "update" : info.downloadURL.lastPathComponent
        let destinationURL = downloadDir.appendingPathComponent(fileName)

        let (downloadedURL, response) = try await session.download(from: info.downloadURL)

        do {
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                throw ServerClient.ServerError.httpError(statusCode: httpResponse.statusCode)
            }

            try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)

            // 1. Verify SHA-256 (streamed, so large files never sit in memory).
            let actualSHA256 = try Self.sha256(of: destinationURL)
            guard actualSHA256.lowercased() == info.sha256.lowercased() else {
                throw DownloadError.sha256Mismatch(expected: info.sha256, actual: actualSHA256)
            }

            // 2. Verify Ed25519 signature when both key and signature are present.
            if !config.publicKey.isEmpty && !info.signature.isEmpty {
                try Self.verifySignature(for: destinationURL, signature: info.signature, publicKey: config.publicKey)
            }

            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: downloadDir)
            throw error
        }
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

        // Ed25519 needs the whole message; update files are typically small
        // enough (tens of MB) for this to be acceptable.
        let fileData = try Data(contentsOf: fileURL)
        guard key.isValidSignature(signatureData, for: fileData) else {
            throw DownloadError.signatureVerificationFailed
        }
    }
}
