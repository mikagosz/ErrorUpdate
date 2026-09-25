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

    /// Size of the alternate signal stack. A stack overflow raises SIGSEGV on
    /// the very stack that just ran out, so a handler without a stack of its
    /// own faults again on its first call and the process dies without a crash
    /// file — the one failure (runaway recursion) this library then never
    /// reported. 64 KB covers the handler with room to spare.
    private static let alternateStackSize = 64 * 1024

    /// Allocated once and never freed: the kernel keeps pointing at it for the
    /// life of the thread. `nonisolated(unsafe)` because only `register()` —
    /// called during setup — writes it.
    nonisolated(unsafe) private static var alternateStack: UnsafeMutableRawPointer?

    static func register() {
        installAlternateStack()
        for sig in signalsToTrap {
            var action = sigaction()
            action.__sigaction_u.__sa_handler = posixSignalHandler
            action.sa_flags = SA_ONSTACK
            sigemptyset(&action.sa_mask)
            sigaction(sig, &action, nil)
        }
    }

    /// The alternate stack belongs to the thread that installs it, so an
    /// overflow on the main thread — where SwiftUI recursion happens — is the
    /// case covered. Other threads fall back to their own stack as before.
    private static func installAlternateStack() {
        guard alternateStack == nil, let memory = malloc(alternateStackSize) else { return }
        var stack = stack_t()
        stack.ss_sp = memory
        stack.ss_size = alternateStackSize
        stack.ss_flags = 0
        if sigaltstack(&stack, nil) == 0 {
            alternateStack = memory
        } else {
            free(memory)
        }
    }

    static func unregister() {
        for sig in signalsToTrap {
            Darwin.signal(sig, SIG_DFL)
        }
    }
}
