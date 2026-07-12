import Testing
@testable import ErrorUpdate
import Foundation

@MainActor
@Suite struct ErrorUpdateManagerTests {

    // MARK: 1. Configure ustawia isConfigured

    @Test func configure_setsIsConfiguredTrue() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            reportingOptIn: false
        )
        #expect(manager.isConfigured == true)
    }

    // MARK: 2. Configure z pustym kluczem — bez crasha

    @Test func configure_withEmptyPublicKey_doesNotCrash() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            publicKey: Data(),
            reportingOptIn: false
        )
        #expect(manager.isConfigured)
    }

    // MARK: 3. logError po configure działa bez crasha

    @Test func logErrorAfterConfigure_doesNotCrash() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            publicKey: Data(),
            reportingOptIn: false
        )

        manager.logError(NSError(domain: "Test", code: 0))
        #expect(manager.isConfigured)
    }

    // MARK: 4. currentVersion pochodzi z bundle (w testach może być nil)

    @Test func currentVersion_doesNotCrash() {
        _ = ErrorUpdateManager.shared.currentVersion
        #expect(true)
    }
}
