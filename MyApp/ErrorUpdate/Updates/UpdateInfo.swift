import Foundation

/// Describes an available application update returned by the server.
public struct UpdateInfo: Codable, Equatable {
    public let latestVersion: String
    public let available: Bool
    public let releaseNotes: String
    public let downloadURL: URL
    public let sha256: String
    public let signature: String  // Base64-encoded Ed25519 signature
    public let mandatory: Bool

    public init(
        latestVersion: String,
        available: Bool,
        releaseNotes: String,
        downloadURL: URL,
        sha256: String,
        signature: String = "",
        mandatory: Bool = false
    ) {
        self.latestVersion = latestVersion
        self.available = available
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.signature = signature
        self.mandatory = mandatory
    }
}
