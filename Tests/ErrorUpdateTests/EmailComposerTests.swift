import Testing
@testable import ErrorUpdate
import Foundation
import AppKit

/// Raport z crasha nie mieści się w `mailto:` (limit ~2000 znaków), więc
/// `EmailComposer` wysyła w treści skrót, a pełną wersję kładzie do schowka.
/// Ta obietnica jest w treści maila napisana wprost — więc schowek musi ją spełnić.
@MainActor
@Suite(.serialized) struct EmailComposerTests {

    private func report(frames: Int) -> ErrorReport {
        ErrorReport(
            errorType: .signal,
            errorMessage: "Fatal Signal: SIGTRAP (Trace Trap)",
            stackTrace: (0..<frames).map { "\($0)   MyApp  0x00000001000\($0)  someVeryLongMangledSymbolName + \($0)" }
        )
    }

    // MARK: 1. Pełny raport ląduje w schowku, nie sama zapowiedź

    @Test func copyToClipboard_putsWholeReportWithStackTrace() {
        let report = report(frames: 50)
        NSPasteboard.general.clearContents()

        EmailComposer.copyToClipboard(report: report)

        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        #expect(clipboard.contains("--- Error Report ---"))
        #expect(clipboard.contains("someVeryLongMangledSymbolName + 49"),
                "W schowku ma być cały stos, nie skrót")
        #expect(clipboard.count > 2000, "Pełny raport jest z definicji dłuższy niż limit mailto")
    }

    // MARK: 2. Krótki raport mieści się w mailto i nie potrzebuje schowka

    @Test func shortReport_fitsInMailtoBody() {
        let short = report(frames: 1)
        let body = ReportBuilder.formatAsPlainText(report: short)
        #expect(body.count < 2000)
    }

    // MARK: 3. Załącznik niesie cały raport

    /// `mailto:` nie ma jak przenieść pliku, więc raport szedł wyłącznie przez
    /// schowek — w skrzynce lądowała wiadomość, która wyglądała na pustą.
    /// Teraz pełna treść jedzie jako załącznik.
    @Test func attachmentFile_containsWholeReport() throws {
        let report = report(frames: 50)

        let url = try #require(EmailComposer.writeReportToTemporaryFile(report: report))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "txt")
        #expect(url.lastPathComponent.contains("ErrorReport-"))

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("--- Error Report ---"))
        #expect(contents.contains("someVeryLongMangledSymbolName + 49"),
                "Załącznik ma nieść cały stos, nie skrót")
    }
}
