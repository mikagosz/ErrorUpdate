//
//  SignalHandler.swift
//  ErrorUpdate
//
//  Catches fatal POSIX signals and writes a raw crash file using
//  async-signal-safe calls (open/write/backtrace_symbols_fd).
//

import Foundation
import Darwin

// C-compatible signal handler. Must stick to async-signal-safe operations:
// no Foundation, no allocation beyond the accepted minimum.
private func posixSignalHandler(_ signalNumber: Int32) {
    guard CrashState.beginHandling() else { abort() }

    let fd = CrashState.openCrashFile()
    if fd >= 0 {
        crashWrite("signal\n", to: fd)
        crashWrite(String(signalNumber) + "\n", to: fd)

        var callStack = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
        let frameCount = backtrace(&callStack, Int32(callStack.count))
        if frameCount > 0 {
            backtrace_symbols_fd(&callStack, frameCount, fd)
        }
        close(fd)
    }

    // Restore default handlers and re-raise so the system crash reporter runs.
    SignalHandler.unregister()
    raise(signalNumber)
}

/// Registers handlers for common fatal signals.
enum SignalHandler {

    private static let signalsToTrap: [Int32] = [
        SIGABRT,
        SIGBUS,
        SIGFPE,
        SIGILL,
        SIGSEGV,
        SIGTRAP,
    ]

    static func register() {
        for sig in signalsToTrap {
            Darwin.signal(sig, posixSignalHandler)
        }
    }

    static func unregister() {
        for sig in signalsToTrap {
            Darwin.signal(sig, SIG_DFL)
        }
    }
}
