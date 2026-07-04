//
//  ErrorLogger.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// Provides a public API for manually logging Swift `Error` types.
public class ErrorLogger {
    
    // This would likely be configured via ErrorUpdateManager
    private static var isConfigured: Bool = false
    
    /// Logs a Swift error, creating a report to be sent to the server.
    /// - Parameters:
    ///   - error: The `Error` to be logged.
    ///   - context: A dictionary of custom key-value pairs to provide additional context.
    public static func log(_ error: Error, context: [String: String]? = nil) {
        // In a real implementation, this would be passed to the ReportBuilder (Task 7)
        // and then to the ServerClient (Task 3) to be sent.
        
        let report = createReport(from: error, context: context)
        
        // For now, we'll just print the constructed report.
        print("--- SWIFT ERROR LOGGED ---")
        print("Error: \(report.errorMessage)")
        print("Context: \(report.customContext ?? [:])")
        print("Stack Trace (simulated): \(report.stackTrace)")
        print("--------------------------")
        
        // TODO: Integrate with ReportBuilder and ServerClient
        // let report = ReportBuilder.build(fromError: error, context: context)
        // ServerClient.shared.submitErrorReport(report) { ... }
    }
    
    /// A private helper to construct an ErrorReport from a Swift Error.
    private static func createReport(from error: Error, context: [String: String]?) -> ErrorReport {
        let localizedDescription = (error as NSError).localizedDescription
        
        // For non-fatal errors, we can capture the current stack trace.
        let stackTrace = Thread.callStackSymbols
        
        // These values would be provided by the configured ErrorUpdateManager
        let appVersion = "1.0.0" // Placeholder
        let userEmail: String? = nil // Placeholder
        
        return ErrorReport(
            timestamp: Date(),
            appVersion: appVersion,
            osVersion: SystemInfo.current().osVersion,
            errorType: .swiftError,
            errorMessage: localizedDescription,
            stackTrace: stackTrace,
            systemInfo: SystemInfo.current(),
            customContext: context,
            userEmail: userEmail,
            consentEmail: userEmail != nil // Simplified logic
        )
    }
}

// MARK: - Error Extension
public extension Error {
    /// Provides a simple description for any `Error`.
    var simpleDescription: String {
        return (self as NSError).localizedDescription
    }
}
