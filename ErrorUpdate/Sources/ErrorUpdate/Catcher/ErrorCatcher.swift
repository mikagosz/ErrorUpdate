//
//  ErrorCatcher.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

// MARK: - Main Crash Catcher

/// The main class for setting up and managing native crash handling.
public class ErrorCatcher {
    
    /// Enables the crash handlers for both exceptions and signals.
    /// This should be called early in the application's lifecycle.
    public static func activate() {
        NativeExceptionHandler.setup()
        SignalHandler.register()
    }

    /// Disables all custom crash handlers, restoring default system behavior.
    public static func deactivate() {
        NativeExceptionHandler.disable()
        SignalHandler.unregister()
    }
}


// MARK: - Private Implementation

// Global function to be called by the uncaught exception handler.
private func uncaughtExceptionHandler(exception: NSException) {
    let callStack = exception.callStackSymbols
    let reason = exception.reason ?? "No reason provided"
    let name = exception.name.rawValue
    
    // TODO: Integrate with ReportBuilder (Task 7)
    // This is a simplified version for now.
    let reportPayload: [String: Any] = [
        "type": "exception",
        "name": name,
        "reason": reason,
        "stackTrace": callStack
    ]
    
    // In a real implementation, this would save the payload to a file
    // to be processed on the next app launch.
    print("--- NATIVE CRASH (NSException) ---")
    print("Payload: \(reportPayload)")
    print("---------------------------------")
    
    // Clean up and let the app terminate as it normally would.
    ErrorCatcher.deactivate()
    exception.raise()
}


/// Handles the catching of native Objective-C exceptions.
private class NativeExceptionHandler {
    
    /// Sets up the uncaught exception handler for the application.
    static func setup() {
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    /// Disables the custom uncaught exception handler.
    static func disable() {
        NSSetUncaughtExceptionHandler(nil)
    }
}
