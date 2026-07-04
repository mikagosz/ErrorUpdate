//
//  ReportBuilder.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// Assembles the final error report from various data sources.
class ReportBuilder {

    // These would be configured via ErrorUpdateManager
    private static var appVersion: String = "1.0.0" // Placeholder
    private static var userEmail: String? = nil // Placeholder
    private static var consentEmail: Bool = false // Placeholder

    /// The primary builder for creating an `ErrorReport`.
    static func build(
        errorType: ErrorType,
        errorMessage: String,
        stackTrace: [String],
        customContext: [String: String]?
    ) -> ErrorReport {
        
        return ErrorReport(
            timestamp: Date(),
            appVersion: self.appVersion,
            osVersion: SystemInfo.current().osVersion,
            errorType: errorType,
            errorMessage: errorMessage,
            stackTrace: stackTrace,
            systemInfo: SystemInfo.current(),
            customContext: customContext,
            userEmail: self.userEmail,
            consentEmail: self.consentEmail
        )
    }
    
    /// Convenience builder for Swift `Error` types.
    static func build(from error: Error, context: [String: String]?) -> ErrorReport {
        return build(
            errorType: .swiftError,
            errorMessage: (error as NSError).localizedDescription,
            stackTrace: Thread.callStackSymbols,
            customContext: context
        )
    }
    
    /// Convenience builder for `NSException` types.
    static func build(from exception: NSException, context: [String: String]?) -> ErrorReport {
        let errorMessage = "Uncaught Exception: \(exception.name.rawValue) - \(exception.reason ?? "No reason")"
        return build(
            errorType: .exception,
            errorMessage: errorMessage,
            stackTrace: exception.callStackSymbols,
            customContext: context
        )
    }

    /// Convenience builder for fatal signals.
    static func build(from signal: Int32, context: [String: String]?) -> ErrorReport {
        let signalName = Self.name(for: signal)
        return build(
            errorType: .signal,
            errorMessage: "Fatal Signal: \(signalName)",
            stackTrace: Thread.callStackSymbols,
            customContext: context
        )
    }

    /// Formats an `ErrorReport` into a human-readable plain text string.
    static func formatAsPlainText(report: ErrorReport) -> String {
        var components = [String]()
        
        components.append("--- Error Report ---")
        components.append("Timestamp: \(report.timestamp.description)")
        components.append("App Version: \(report.appVersion)")
        components.append("OS Version: \(report.osVersion)")
        components.append("Error Type: \(report.errorType.rawValue)")
        components.append("Error Message: \(report.errorMessage)")
        
        if let context = report.customContext, !context.isEmpty {
            components.append("\n--- Custom Context ---")
            context.forEach { key, value in
                components.append("\(key): \(value)")
            }
        }
        
        components.append("\n--- System Info ---")
        components.append("CPU: \(report.systemInfo.cpuModel)")
        components.append("RAM: \(report.systemInfo.ramGB) GB")
        components.append("Disk Free: \(report.systemInfo.diskFreeGB) GB")
        
        if !report.stackTrace.isEmpty {
            components.append("\n--- Stack Trace ---")
            components.append(contentsOf: report.stackTrace)
        }
        
        return components.joined(separator: "\n")
    }
    
    /// Helper to get a string name for a signal number.
    private static func name(for signal: Int32) -> String {
        switch signal {
        case SIGSEGV: return "SIGSEGV (Segmentation Fault)"
        case SIGABRT: return "SIGABRT (Abort)"
        case SIGILL: return "SIGILL (Illegal Instruction)"
        case SIGFPE: return "SIGFPE (Floating-Point Exception)"
        case SIGPIPE: return "SIGPIPE (Broken Pipe)"
        default: return "Unknown Signal (\(signal))"
        }
    }
}
