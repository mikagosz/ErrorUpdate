//
//  CrashCatcher.swift
//  ErrorUpdate
//
//  Catches uncaught NSExceptions and writes a raw crash file that is
//  turned into an ErrorReport on the next launch (see ErrorUpdateManager).
//

import Foundation
import Darwin

// Shared crash-handling state. Accessed from exception and signal handlers,
// so it must not depend on actors or locks that could deadlock mid-crash.
enum CrashState {
    // Guarded by `lock`; `nonisolated(unsafe)` because handlers run on the
    // crashing thread outside any actor.
    nonisolated(unsafe) private(set) static var isHandlingCrash = false
    nonisolated(unsafe) private static var lock = os_unfair_lock()

    /// Path to the crash file as a C string, precomputed at registration time
    /// so signal handlers never need to call into Foundation.
    nonisolated(unsafe) static var crashFilePath: [CChar] = []

    /// Returns `true` the first time it is called during a crash; `false` on re-entry.
    static func beginHandling() -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        if isHandlingCrash { return false }
        isHandlingCrash = true
        return true
    }

    /// Opens the crash file using only async-signal-safe calls.
    static func openCrashFile() -> Int32 {
        guard !crashFilePath.isEmpty else { return -1 }
        return crashFilePath.withUnsafeBufferPointer { buffer in
            open(buffer.baseAddress!, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        }
    }
}

/// Writes a string to a file descriptor. Safe to use in the NSException handler;
/// in signal handlers it is technically not async-signal-safe (may allocate),
/// which is an accepted trade-off for readable crash files.
func crashWrite(_ string: String, to fd: Int32) {
    var text = string
    text.withUTF8 { buffer in
        guard let base = buffer.baseAddress else { return }
        _ = write(fd, base, buffer.count)
    }
}

// The uncaught exception handler runs in a normal (non-signal) context,
// so using Foundation here is safe.
private func uncaughtExceptionHandler(_ exception: NSException) {
    guard CrashState.beginHandling() else { abort() }

    let fd = CrashState.openCrashFile()
    if fd >= 0 {
        crashWrite("exception\n", to: fd)
        crashWrite(exception.name.rawValue + "\n", to: fd)
        crashWrite((exception.reason ?? "No reason provided") + "\n", to: fd)
        for frame in exception.callStackSymbols {
            crashWrite(frame + "\n", to: fd)
        }
        close(fd)
    }

    // Restore default handling and let the process terminate normally.
    NSSetUncaughtExceptionHandler(nil)
    SignalHandler.unregister()
    exception.raise()
}

/// Handles catching of uncaught Objective-C exceptions.
enum CrashCatcher {

    /// Location of the raw crash file written by the handlers.
    static func crashReportURL() -> URL {
        let baseDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = baseDir.appendingPathComponent(Bundle.main.bundleIdentifier ?? "ErrorUpdate")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("crash.raw")
    }

    static func register() {
        // Precompute the C path so signal handlers can open the file safely.
        CrashState.crashFilePath = Array(crashReportURL().path.utf8CString)
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }

    static func unregister() {
        NSSetUncaughtExceptionHandler(nil)
    }
}
