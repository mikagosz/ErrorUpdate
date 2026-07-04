//
//  EmailComposer.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import AppKit

/// Composes and presents an email with the error report.
class EmailComposer {
    
    // This would be configured via ErrorUpdateManager
    private static var recipientEmail: String = "reports@example.com" // Placeholder

    /// Attempts to open the user's default mail client with a pre-filled report.
    /// - Parameter report: The `ErrorReport` to be sent.
    /// - Returns: `true` if the mail client was successfully opened, `false` otherwise.
    @discardableResult
    static func send(report: ErrorReport) -> Bool {
        let subject = "Error Report: \(report.appVersion) - \(report.errorMessage.prefix(40))...".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Error Report"
        let body = ReportBuilder.formatAsPlainText(report: report).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "Could not format report."
        
        let mailtoURLString = "mailto:\(recipientEmail)?subject=\(subject)&body=\(body)"
        
        guard let url = URL(string: mailtoURLString) else {
            return false
        }
        
        // Check if the URL is too long for mailto (a common but informal limit is ~2000 characters)
        if mailtoURLString.count > 2000 {
            print("Warning: Report is too long for a 'mailto:' link. Consider a different reporting method.")
            return false
        }
        
        // Use NSWorkspace to open the URL, which will launch the default mail client.
        if NSWorkspace.shared.open(url) {
            return true
        } else {
            // Fallback if opening the URL fails for some reason.
            return false
        }
    }

    /// Copies the plain-text version of a report to the user's clipboard.
    /// This is a fallback for when the mail client cannot be opened.
    /// - Parameter report: The `ErrorReport` to be copied.
    static func copyToClipboard(report: ErrorReport) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ReportBuilder.formatAsPlainText(report: report), forType: .string)
    }
}
