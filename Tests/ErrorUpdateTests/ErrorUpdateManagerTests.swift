import Testing
@testable import ErrorUpdate
import Foundation

// Serializowany, bo wszystkie testy dzielą singleton `ErrorUpdateManager.shared`.
@MainActor
@Suite(.serialized) struct ErrorUpdateManagerTests {

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

    // MARK: 4. Adres serwera po czystym HTTP → odmowa konfiguracji

    @Test func configure_withPlainHTTPServerURL_isRefused() {
        let manager = ErrorUpdateManager.shared
        manager.configure(serverURL: URL(string: "https://example.com/check")!)
        #expect(manager.isConfigured)

        manager.configure(serverURL: URL(string: "http://example.com/check")!)
        #expect(manager.isConfigured == false, "Konfiguracja po HTTP musi zostać odrzucona")

        // Loopback zostaje dopuszczony — na nim stoi serwer testowy.
        manager.configure(serverURL: URL(string: "http://127.0.0.1:8000")!)
        #expect(manager.isConfigured)
    }

    // MARK: 5. currentVersion pochodzi z bundle (w testach może być nil)

    @Test func currentVersion_doesNotCrash() {
        _ = ErrorUpdateManager.shared.currentVersion
        #expect(true)
    }
}
