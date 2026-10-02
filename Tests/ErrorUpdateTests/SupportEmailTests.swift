import Testing
@testable import ErrorUpdate
import Foundation

/// The configured support address is the one reports go to (1.0.8). Before,
/// `ErrorUpdateConfig.supportEmail` was stored and never read.
@MainActor
@Suite struct SupportEmailTests {

    private let janitor = DefaultsJanitor()

    private func manager(email: String?) -> ErrorUpdateManager {
        let manager = ErrorUpdateManager()
        manager.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                              allowUnsignedUpdates: true, supportEmail: email),
            session: nil, userDefaults: janitor.make("SupportEmail"))
        return manager
    }

    @Test func configuredAddress_isExposed() {
        #expect(manager(email: "support@fractal8.eu").supportEmail == "support@fractal8.eu")
    }

    @Test func surroundingSpaces_areTrimmed() {
        #expect(manager(email: "  support@fractal8.eu ").supportEmail == "support@fractal8.eu")
    }

    @Test func missingOrBlankAddress_isNil() {
        #expect(manager(email: nil).supportEmail == nil)
        #expect(manager(email: "   ").supportEmail == nil)
        #expect(ErrorUpdateManager().supportEmail == nil, "Not configured — no address")
    }
}
