import Foundation
import CryptoKit

/// Downloads and verifies update files via SHA-256 checksum and Ed25519 signature.
public class UpdateDownloader {

    private let config: ErrorUpdateConfig
    private let session: URLSession
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2

    public init(config: ErrorUpdateConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Downloads the update file from `info.downloadURL`, verifies SHA-256 and Ed25519 signature.
    /// Returns the URL of the verified file, or throws on any verification failure.
    public func download(_ info: UpdateInfo) async throws -> URL {
        var lastError: Error?
        for attempt in 0..<maxRetries {
            do {
                return try await downloadAndVerify(info)
            } catch {
                lastError = error
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2, Double(attempt))
                    print("Download attempt \(attempt + 1) failed (\(error)), retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError ?? NSError(domain: "ErrorUpdate", code: -1,
                                   userInfo: [NSLocalizedDescriptionKey: "Download failed after \(maxRetries) retries"])
    }

    private func downloadAndVerify(_ info: UpdateInfo) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ErrorUpdate_download")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let tempFile = tempDir.appendingPathComponent(info.downloadURL.lastPathComponent)

        do {
            let (downloaded, _) = try await session.download(from: info.downloadURL)
            try FileManager.default.moveItem(at: downloaded, to: tempFile)
        } catch {
            throw NSError(domain: "ErrorUpdate", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Download failed: \(error.localizedDescription)"])
        }

        defer { try? FileManager.default.removeItem(at: tempFile) } // clean up on any error

        // 1. Verify SHA-256
        let downloadedSHA256 = try sha256(of: tempFile)
        guard downloadedSHA256.lowercased() == info.sha256.lowercased() else {
            throw NSError(domain: "ErrorUpdate", code: -1,
                         userInfo: [NSLocalizedDescriptionKey:
                                     "SHA-256 mismatch: expected \(info.sha256), got \(downloadedSHA256)"])
        }

        // 2. Verify Ed25519 signature
        if !info.signature.isEmpty {
            try await verifySignature(for: tempFile, signature: info.signature)
        }

        // Signature verified — keep the file
        return tempFile
    }

    private func sha256(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Verifies the Ed25519 signature over the file contents using the config's public key.
    private func verifySignature(for fileURL: URL, signature base64Signature: String) async throws {
        guard !config.publicKey.isEmpty else {
            // No public key configured — skip signature verification.
            print("[WARNING] No Ed25519 public key configured; skipping signature verification.")
            return
        }

        guard let signatureData = Data(base64Encoded: base64Signature),
              signatureData.count == 64 else {
            throw NSError(domain: "ErrorUpdate", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid signature format (expected 64-byte Base64)"])
        }

        do {
            let publicKeyObj = try Curve25519.Signing.PublicKey(rawRepresentation: config.publicKey)
            let fileData = try Data(contentsOf: fileURL)
            guard publicKeyObj.isValidSignature(signatureData, for: fileData) else {
                throw NSError(domain: "ErrorUpdate", code: -1,
                             userInfo: [NSLocalizedDescriptionKey: "Ed25519 signature verification failed"])
            }
        } catch {
            throw NSError(domain: "ErrorUpdate", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid public key: \(error.localizedDescription)"])
        }
    }
}
