//
//  ErrorUpdateConfig.swift
//  ErrorUpdate
//

import Foundation

/// Configuration for the ErrorUpdate framework.
public struct ErrorUpdateConfig: Sendable {
    /// Base URL of the update/report server. The framework appends
    /// `/api/error-update/version-check` and `/api/error-update/report`.
    public let serverURL: URL
    /// Identifier of the application, sent as the `X-App-ID` header.
    public let appID: String
    /// Optional API key, sent as the `X-API-Key` header.
    public let apiKey: String?
    /// Ed25519 public key (raw 32 bytes) used to verify update signatures.
    /// When set, every update **must** carry a valid signature — a manifest
    /// without one is rejected instead of silently skipping verification.
    public let publicKey: Data
    /// Opt-out for running without signature verification.
    ///
    /// Downloads are refused when `publicKey` is empty unless this is `true`.
    /// Setting it accepts that an update is only checked against a checksum
    /// the same server supplies, which protects against a corrupted transfer
    /// and against nothing else.
    public let allowUnsignedUpdates: Bool
    /// Upper bound for a downloaded update, in bytes (default 1 GB).
    ///
    /// Verification can only run once the file is on disk, so without a bound a
    /// manifest pointing at a huge file fills the user's disk before anything
    /// gets checked. The transfer is cancelled as soon as the limit is passed —
    /// or immediately, when the server announces a larger `Content-Length`.
    public let maxDownloadBytes: Int64
    /// When `true`, saved error reports are also sent to the server automatically.
    public var reportingOptIn: Bool
    /// Email address error reports are addressed to when using the mail composer.
    public var supportEmail: String?

    public init(
        serverURL: URL,
        appID: String = Bundle.main.bundleIdentifier ?? "unknown",
        apiKey: String? = nil,
        publicKey: Data = Data(),
        allowUnsignedUpdates: Bool = false,
        maxDownloadBytes: Int64 = 1_073_741_824,
        reportingOptIn: Bool = false,
        supportEmail: String? = nil
    ) {
        self.serverURL = serverURL
        self.appID = appID
        self.apiKey = apiKey
        self.publicKey = publicKey
        self.allowUnsignedUpdates = allowUnsignedUpdates
        self.maxDownloadBytes = maxDownloadBytes
        self.reportingOptIn = reportingOptIn
        self.supportEmail = supportEmail
    }
}
