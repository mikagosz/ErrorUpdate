import Foundation
import Darwin
import os.log

// Re-entrancy guard: separate counter (checked inside lock).
// os_unfair_lock provides mutual exclusion; the counter prevents double-processing.
private var isCrashing: Int32 = 0
private var crashLock: os_unfair_lock = os_unfair_lock()

// The C-style function that will handle the POSIX signals.
private func posixSignalHandler(_ signal: Int32) {
    // Prevent re-entrancy using os_unfair_lock (async-signal-safe on Darwin).
    os_unfair_lock_lock(&crashLock)
    defer { os_unfair_lock_unlock(&crashLock) }
    if isCrashing != 0 {
        abort()
    }
    isCrashing = 1

    let reportPath = CrashCatcher.crashReportURL().path
    let fileDescriptor = open(reportPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)

    guard fileDescriptor >= 0 else {
        // Cannot open file, unregister and re-raise.
        SignalHandler.unregister()
        raise(signal)
        return
    }

    defer { close(fileDescriptor) }

    // Write header indicating signal crash
    let header = "signal\n"
    _ = header.withCString { write(fileDescriptor, $0, strlen($0)) }

    // Write the signal number
    let signalNum = signal
    let signalStr = String(signalNum)
    _ = signalStr.withCString { write(fileDescriptor, $0, strlen($0)) }
    _ = "\n".withCString { write(fileDescriptor, $0, 1) }

    // Write stack trace
    var callStack = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
    let frameCount = backtrace(&callStack, Int32(callStack.count))

    if frameCount > 0 {
        backtrace_symbols_fd(&callStack, frameCount, fileDescriptor)
    }

    // Unregister handlers and re-raise the signal to let the system default handler run.
    SignalHandler.unregister()
    raise(signal)
}

// TODO: Handles catching POSIX signals.
final class SignalHandler {

    private static let signalsToTrap: [Int32] = [
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGSEGV
    ]

    static func register() {
        for signal in signalsToTrap {
            // Use sigaction for more robust signal handling if needed,
            // but Darwin.signal is sufficient for this purpose.
            Darwin.signal(signal, posixSignalHandler)
        }
    }

    static func unregister() {
        for signal in signalsToTrap {
            Darwin.signal(signal, SIG_DFL) // Restore default handler
        }
    }
}
