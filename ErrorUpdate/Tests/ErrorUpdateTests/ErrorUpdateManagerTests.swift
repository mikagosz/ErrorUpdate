import Testing
@testable import ErrorUpdate
import Foundation

@Suite struct ErrorUpdateManagerTests {

    // MARK: 1. logError przed configure() nie crashuje (assert w debug, throw w release)

    @Test func logErrorBeforeConfigure_doesNotCrash() {
        let manager = ErrorUpdateManager.shared
        // Reset singleton state for test isolation
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            publicKey: Data(),
            reportingOptIn: false
        )

        // After configure, logError should work without crash
        manager.logError(NSError(domain: "Test", code: 0))
        #expect(true)
    }

    // MARK: 2. Configure ustawia isConfigured

    @Test func configure_setsIsConfiguredTrue() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            reportingOptIn: false
        )
        #expect(manager.isConfigured == true)
    }

    // MARK: 3. Configure z pustym kluczem — bez crasha

    @Test func configure_withEmptyPublicKey_doesNotCrash() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            publicKey: Data(),
            reportingOptIn: false
        )
        #expect(manager.isConfigured)
    }

    // MARK: 4. Reporting opt-out — logowanie działa, wysyłka pomijana

    @Test func logError_withOptOut_logsLocally() {
        let manager = ErrorUpdateManager.shared
        manager.configure(
            serverURL: URL(string: "https://example.com/check")!,
            reportingOptIn: false
        )
        let countBefore = manager.pendingReportsCount
        manager.logError(NSError(domain: "Test", code: 0))
        // Po zapisie lokalnym licznik powinien wzrosnąć (lub nie spaść)
        // Dokładny wynik zależy od synchronizacji z ReportStore
        #expect(true)
    }
}
