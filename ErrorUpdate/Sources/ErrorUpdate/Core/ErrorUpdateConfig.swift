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
    /// When empty, signature verification is skipped.
    public let publicKey: Data
    /// When `true`, saved error reports are also sent to the server automatically.
    public var reportingOptIn: Bool
    /// Email address error reports are addressed to when using the mail composer.
    public var supportEmail: String?

    public init(
        serverURL: URL,
        appID: String = Bundle.main.bundleIdentifier ?? "unknown",
        apiKey: String? = nil,
        publicKey: Data = Data(),
        reportingOptIn: Bool = false,
        supportEmail: String? = nil
    ) {
        self.serverURL = serverURL
        self.appID = appID
        self.apiKey = apiKey
        self.publicKey = publicKey
        self.reportingOptIn = reportingOptIn
        self.supportEmail = supportEmail
    }
}
