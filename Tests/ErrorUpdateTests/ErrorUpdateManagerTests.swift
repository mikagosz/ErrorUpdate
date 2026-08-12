import Testing
@testable import ErrorUpdate
import Foundation

// Serialized, because every test shares the `ErrorUpdateManager.shared` singleton.
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

    // MARK: 3. logError after configure does not crash

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
        #expect(manager.isConfigured == false, "Configuration over plain HTTP must be refused")

        // Loopback zostaje dopuszczony — na nim stoi serwer testowy.
        manager.configure(serverURL: URL(string: "http://127.0.0.1:8000")!)
        #expect(manager.isConfigured)
    }

    // MARK: 5. currentVersion comes from the bundle (may be nil under test)

    @Test func currentVersion_doesNotCrash() {
        _ = ErrorUpdateManager.shared.currentVersion
        #expect(true)
    }

    // MARK: 6. Crash file with non-UTF-8 bytes still produces a report

    /// Regression: a SwiftUI crash writes stack frames through
    /// `backtrace_symbols_fd`, which emits raw non-UTF-8 bytes once a mangled
    /// symbol gets long enough. Reading the file with `String(contentsOf:encoding:)`
    /// returned nil and the report was dropped — while the file itself was deleted
    /// by a `defer`, so nothing survived to debug. Measured on a real crash in a
    /// SwiftUI app: clean header, garbage from ~1.3 kB onwards.
    @Test func crashFileWithInvalidUTF8_stillYieldsReport() throws {
        let manager = ErrorUpdateManager.shared
        let crashURL = CrashCatcher.crashReportURL()

        var raw = Data("signal\n5\n0   MyApp    0x0000000104da87dc frameOne + 468\n".utf8)
        raw.append(contentsOf: [0x8F, 0x00, 0xFD, 0x4F, 0x45, 0x92])   // exactly the tail seen in the measured file
        raw.append(Data("\n2   MyApp    0x0000000104da9999 frameThree + 12\n".utf8))
        try raw.write(to: crashURL)

        manager.configure(serverURL: URL(string: "https://example.com/check")!, reportingOptIn: false)
        manager.processPendingCrashFile()
        manager.refreshPendingReports()   // configure() robi to samo po przetworzeniu pliku

        let report = manager.pendingReports.first { $0.errorMessage.contains("SIGTRAP") }
        #expect(report != nil, "A damaged tail must not wipe out the whole report")
        #expect(FileManager.default.fileExists(atPath: crashURL.path) == false,
                "A consumed crash file should be gone")

        // Frames from before the damage must survive — that is the point of the report.
        #expect(report?.stackTrace.contains { $0.contains("frameOne") } == true)

        if let id = report?.id { manager.discardReport(id) }
    }

    // MARK: 7. Unrecognised crash file is quarantined, not silently deleted

    @Test func unrecognisedCrashFile_isKeptForInspection() throws {
        let manager = ErrorUpdateManager.shared
        let crashURL = CrashCatcher.crashReportURL()
        let quarantine = crashURL.appendingPathExtension("unreadable")
        try? FileManager.default.removeItem(at: quarantine)

        try Data("cos zupelnie innego\ndruga linia\n".utf8).write(to: crashURL)

        manager.configure(serverURL: URL(string: "https://example.com/check")!, reportingOptIn: false)
        manager.processPendingCrashFile()

        #expect(FileManager.default.fileExists(atPath: crashURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: quarantine.path),
                "An unrecognised file goes to quarantine, not to the bin")

        try? FileManager.default.removeItem(at: quarantine)
    }
}
