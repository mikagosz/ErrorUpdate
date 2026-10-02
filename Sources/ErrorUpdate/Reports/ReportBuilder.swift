//
//  ReportBuilder.swift
//  ErrorUpdate
//

import Foundation

/// Assembles `ErrorReport` values from various error sources.
public enum ReportBuilder {

    /// Builds a report for a Swift `Error`.
    static func build(from error: Error, context: [String: String]?, contactEmail: String? = nil) -> ErrorReport {
        ErrorReport(
            errorType: .swiftError,
            errorMessage: (error as NSError).localizedDescription,
            stackTrace: Thread.callStackSymbols,
            customContext: context,
            contactEmail: contactEmail
        )
    }

    /// Builds a report for an `NSException`.
    static func build(from exception: NSException, context: [String: String]?, contactEmail: String? = nil) -> ErrorReport {
        ErrorReport(
            errorType: .exception,
            errorMessage: "Uncaught Exception: \(exception.name.rawValue) - \(exception.reason ?? "No reason")",
            stackTrace: exception.callStackSymbols,
            customContext: context,
            contactEmail: contactEmail
        )
    }

    /// Builds a report for a fatal signal.
    static func build(fromSignal signal: Int32, stackTrace: [String], contactEmail: String? = nil) -> ErrorReport {
        ErrorReport(
            errorType: .signal,
            errorMessage: "Fatal Signal: \(name(for: signal))",
            stackTrace: stackTrace,
            contactEmail: contactEmail
        )
    }

    /// Context key marking what kind of trouble a report describes, for the
    /// kinds `ErrorType` has no case for. Adding cases to the public enum would
    /// break exhaustive switches in existing apps.
    static let kindKey = "errorUpdate.kind"

    /// The main thread did not answer for `duration` seconds and then recovered.
    /// The message stays the same for every hang so repeats merge into one report.
    static func build(hangDuration duration: TimeInterval) -> ErrorReport {
        ErrorReport(
            errorType: .swiftError,
            errorMessage: "Main thread stopped responding",
            customContext: [kindKey: "hang",
                            "durationSeconds": String(format: "%.1f", duration)]
        )
    }

    /// The main thread stopped answering and the app ended before it recovered —
    /// most often the user force-quit it. Found on the next launch.
    static func build(unfinishedHangStartedAt started: Date) -> ErrorReport {
        ErrorReport(
            errorType: .swiftError,
            errorMessage: "Main thread stopped responding and the app ended before it recovered",
            customContext: [kindKey: "hangUntilExit",
                            "hangStarted": ISO8601DateFormatter().string(from: started)]
        )
    }

    /// A watched operation did not end within its limit.
    static func build(overdue: OperationWatch.Overdue) -> ErrorReport {
        ErrorReport(
            errorType: .swiftError,
            errorMessage: "Operation did not finish within its limit: \(overdue.name)",
            stackTrace: overdue.startedFrom,
            customContext: [kindKey: "operationOverdue",
                            "operation": overdue.name,
                            "limitSeconds": String(format: "%.0f", overdue.limit)]
        )
    }

    /// Formats an `ErrorReport` into a human-readable plain text string.
    public static func formatAsPlainText(report: ErrorReport) -> String {
        var components = [String]()

        components.append("--- Error Report ---")
        components.append("Timestamp: \(report.timestamp.description)")
        components.append("App Version: \(report.appVersion)")
        components.append("OS Version: \(report.osVersion)")
        components.append("Error Type: \(report.errorType.rawValue)")
        components.append("Error Message: \(report.errorMessage)")
        components.append("Occurrences: \(report.count)")

        if let context = report.customContext, !context.isEmpty {
            components.append("\n--- Custom Context ---")
            for (key, value) in context.sorted(by: { $0.key < $1.key }) {
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

    /// Human-readable name for a signal number.
    static func name(for signal: Int32) -> String {
        switch signal {
        case SIGSEGV: return "SIGSEGV (Segmentation Fault)"
        case SIGABRT: return "SIGABRT (Abort)"
        case SIGILL: return "SIGILL (Illegal Instruction)"
        case SIGFPE: return "SIGFPE (Floating-Point Exception)"
        case SIGBUS: return "SIGBUS (Bus Error)"
        case SIGTRAP: return "SIGTRAP (Trace Trap)"
        case SIGPIPE: return "SIGPIPE (Broken Pipe)"
        default: return "Unknown Signal (\(signal))"
        }
    }
}
