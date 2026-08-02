//
//  URLSecurity.swift
//  ErrorUpdate
//

import Foundation

/// Decides which URLs the framework is willing to talk to.
///
/// App Transport Security already blocks plain HTTP, but that is a property of
/// the platform, not of this library: an integrator who adds an ATS exception
/// for an unrelated reason would silently lose the protection. A library whose
/// whole job is delivering trustworthy updates should enforce this itself.
enum URLSecurity {

    /// Hosts allowed over plain HTTP. Loopback never leaves the machine, and the
    /// bundled test server depends on it (ATS exempts these addresses too).
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    /// `true` for HTTPS, or for plain HTTP pointing at loopback.
    static func isAcceptable(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return true
        case "http":
            return isLoopback(url)
        default:
            return false
        }
    }

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return loopbackHosts.contains(host) || host.hasSuffix(".localhost")
    }

    /// Explains a rejection in terms the integrator can act on.
    static func rejectionReason(for url: URL) -> String {
        "\(url.absoluteString) is not an HTTPS address (plain HTTP is accepted for loopback only)"
    }
}
