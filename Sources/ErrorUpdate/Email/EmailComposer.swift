//
//  EmailComposer.swift
//  ErrorUpdate
//

import AppKit

/// Composes an email with an error report using the default mail client.
@MainActor
public enum EmailComposer {

    /// A `mailto:` URL only reliably works up to about this length.
    private static let mailtoLengthLimit = 2000

    /// Attempts to open the user's default mail client with a pre-filled report.
    ///
    /// A crash report runs to tens of kilobytes and a `mailto:` link breaks well
    /// before that, so the report travels as a **file attachment** whenever the
    /// system's mail composer is available. Only when it is not do we fall back
    /// to `mailto:` — and there a long report goes to the clipboard, because
    /// `mailto:` has no way to carry a file.
    /// - Returns: `true` if the mail client was opened.
    @discardableResult
    public static func send(report: ErrorReport, to recipient: String) -> Bool {
        let subject = "Error Report: \(report.appVersion) - \(report.errorMessage.prefix(40))"

        if sendWithAttachment(report: report, to: recipient, subject: subject) {
            return true
        }
        return sendViaMailto(report: report, to: recipient, subject: subject)
    }

    /// Composes the mail through `NSSharingService`, with the report attached as
    /// a text file. Returns `false` when no mail composer is available, so the
    /// caller can fall back.
    private static func sendWithAttachment(report: ErrorReport, to recipient: String, subject: String) -> Bool {
        guard let service = NSSharingService(named: .composeEmail),
              let attachment = writeReportToTemporaryFile(report: report) else {
            return false
        }

        service.recipients = [recipient]
        service.subject = subject

        let items: [Any] = [
            """
            \(report.errorMessage)

            The full report is attached as \(attachment.lastPathComponent).
            """,
            attachment,
        ]

        guard service.canPerform(withItems: items) else { return false }
        service.perform(withItems: items)
        return true
    }

    /// Original route: a `mailto:` link, with the clipboard carrying anything
    /// that does not fit. Kept for setups without a system mail composer.
    private static func sendViaMailto(report: ErrorReport, to recipient: String, subject: String) -> Bool {
        var body = ReportBuilder.formatAsPlainText(report: report)

        if mailtoURL(to: recipient, subject: subject, body: body) == nil
            || mailtoLength(to: recipient, subject: subject, body: body) > mailtoLengthLimit {
            // Too long — fall back to a short body plus clipboard.
            copyToClipboard(report: report)
            body = """
            \(report.errorMessage)

            (The full report was copied to the clipboard — please paste it here.)
            """
        }

        guard let url = mailtoURL(to: recipient, subject: subject, body: body) else {
            return false
        }
        return NSWorkspace.shared.open(url)
    }

    /// Writes the report as a plain-text file for attaching. The name carries the
    /// app version and a timestamp, so several reports from one user stay apart
    /// in a mailbox.
    static func writeReportToTemporaryFile(report: ErrorReport) -> URL? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let name = "ErrorReport-\(report.appVersion)-\(formatter.string(from: report.timestamp)).txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)

        do {
            try ReportBuilder.formatAsPlainText(report: report).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    /// Copies the plain-text version of a report to the clipboard.
    public static func copyToClipboard(report: ErrorReport) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ReportBuilder.formatAsPlainText(report: report), forType: .string)
    }

    private static func mailtoURL(to recipient: String, subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipient
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    private static func mailtoLength(to recipient: String, subject: String, body: String) -> Int {
        mailtoURL(to: recipient, subject: subject, body: body)?.absoluteString.count ?? .max
    }
}
