import Testing
@testable import ErrorUpdate
import Foundation
import AppKit

/// A crash report does not fit in a `mailto:` URL (a limit of roughly 2000 characters),
/// so `EmailComposer` puts a summary in the body and the full version on the clipboard.
/// That promise is stated in the mail body itself — so the clipboard has to keep it.
@MainActor
@Suite(.serialized) struct EmailComposerTests {

    private func report(frames: Int) -> ErrorReport {
        ErrorReport(
            errorType: .signal,
            errorMessage: "Fatal Signal: SIGTRAP (Trace Trap)",
            stackTrace: (0..<frames).map { "\($0)   MyApp  0x00000001000\($0)  someVeryLongMangledSymbolName + \($0)" }
        )
    }

    // MARK: 1. The full report reaches the clipboard, not just the promise of it

    @Test func copyToClipboard_putsWholeReportWithStackTrace() {
        let report = report(frames: 50)
        NSPasteboard.general.clearContents()

        EmailComposer.copyToClipboard(report: report)

        let clipboard = NSPasteboard.general.string(forType: .string) ?? ""
        #expect(clipboard.contains("--- Error Report ---"))
        #expect(clipboard.contains("someVeryLongMangledSymbolName + 49"),
                "The clipboard must carry the whole stack, not the summary")
        #expect(clipboard.count > 2000, "A full report is by definition longer than the mailto limit")
    }

    // MARK: 2. A short report fits in mailto and needs no clipboard

    @Test func shortReport_fitsInMailtoBody() {
        let short = report(frames: 1)
        let body = ReportBuilder.formatAsPlainText(report: short)
        #expect(body.count < 2000)
    }

    // MARK: 3. The attachment carries the whole report

    /// `mailto:` has no way to carry a file, so the report travelled by clipboard
    /// alone — and what landed in the mailbox looked like an empty message. The full
    /// content now goes as an attachment.
    @Test func attachmentFile_containsWholeReport() throws {
        let report = report(frames: 50)

        let url = try #require(EmailComposer.writeReportToTemporaryFile(report: report))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.pathExtension == "txt")
        #expect(url.lastPathComponent.contains("ErrorReport-"))

        let contents = try String(contentsOf: url, encoding: .utf8)
        #expect(contents.contains("--- Error Report ---"))
        #expect(contents.contains("someVeryLongMangledSymbolName + 49"),
                "The attachment must carry the whole stack, not the summary")
    }
}
