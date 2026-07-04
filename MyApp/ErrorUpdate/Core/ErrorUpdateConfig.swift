import Foundation
import Combine

// TODO: Configuration model for the framework.
public struct ErrorUpdateConfig {
    let serverURL: URL
    let publicKey: Data // Ed25519 public key for update signature verification
    var reportingOptIn: Bool = false
}
