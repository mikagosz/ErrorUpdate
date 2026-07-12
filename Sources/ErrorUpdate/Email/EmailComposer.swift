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
    /// When the report is too long for a `mailto:` link, only the summary is
    /// included in the body and the full report is copied to the clipboard.
    /// - Returns: `true` if the mail client was opened.
    @discardableResult
    public static func send(report: ErrorReport, to recipient: String) -> Bool {
        let subject = "Error Report: \(report.appVersion) - \(report.errorMessage.prefix(40))"
        let fullBody = ReportBuilder.formatAsPlainText(report: report)

        var body = fullBody
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
