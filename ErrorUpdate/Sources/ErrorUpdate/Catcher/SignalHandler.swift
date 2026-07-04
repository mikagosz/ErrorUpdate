//
//  SignalHandler.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

// C-style function to act as the signal handler
private func signalHandler(signal: Int32) {
    let signalName: String
    switch signal {
    case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
    case SIGABRT: signalName = "SIGABRT (Abort)"
    case SIGILL: signalName = "SIGILL (Illegal Instruction)"
    case SIGFPE: signalName = "SIGFPE (Floating-Point Exception)"
    case SIGPIPE: signalName = "SIGPIPE (Broken Pipe)"
    default: signalName = "Unknown Signal (\(signal))"
    }

    let callStack = Thread.callStackSymbols

    // TODO: Integrate with a crash handler that builds and saves the report.
    print("--- FATAL SIGNAL ---")
    print("Received signal: \(signalName)")
    print("Stack Trace:")
    callStack.forEach { print($0) }
    print("--------------------")

    // Unregister the signal handler and re-raise the signal to crash.
    SignalHandler.unregister()
    raise(signal)
}


/// Sets up signal handlers for crash detection.
class SignalHandler {
    private static let signalsToTrap: [Int32] = [
        SIGABRT,
        SIGILL,
        SIGSEGV,
        SIGFPE,
        SIGPIPE
    ]

    /// Registers the signal handlers for common crash signals.
    static func register() {
        for signal in signalsToTrap {
            // The first argument to `signal` is the signal number.
            // The second is a pointer to the handler function.
            // `SIG_ERR` is returned on failure.
            if signal(signal, signalHandler) == SIG_ERR {
                print("Error: Could not register signal handler for signal \(signal).")
            }
        }
    }

    /// Unregisters all custom signal handlers.
    static func unregister() {
        for signal in signalsToTrap {
            // Restore the default signal handler.
            signal(signal, SIG_DFL)
        }
    }
}
