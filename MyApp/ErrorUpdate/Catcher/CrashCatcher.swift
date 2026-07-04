import Foundation
import Darwin
import os.lock

// Use os_unfair_lock to prevent re-entrancy, which is async-signal-safe.
private var crashLock = OSAllocatedUnfairLock()

// The C-style function that will be set as the uncaught exception handler.
private func uncaughtExceptionHandler(_ exception: NSException) {
    // Acquire the lock. If already held, it means we're re-entering during a crash.
    crashLock.lock()
    defer { crashLock.unlock() }

    // Check if we're already in a crash handling state.
    // We use a simple counter to be more robust than a flag.
    // This is a simplified check for async-signal-safety.
    // In a full production system, a more robust re-entrancy guard might be needed
    // that doesn't involve dynamic state, but for this context, it's acceptable.
    guard CrashCatcher.isHandlingCrash == 0 else {
        abort() // Abort if re-entering
    }
    CrashCatcher.isHandlingCrash = 1

    let reportPath = CrashCatcher.crashReportURL().path
    let fileDescriptor = open(reportPath, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    
    guard fileDescriptor >= 0 else {
        // Cannot open file, nothing we can do that is safe.
        // Unregister and re-raise.
        NSSetUncaughtExceptionHandler(nil)
        exception.raise()
        return
    }
    
    defer { close(fileDescriptor) }

    // Write a simple header indicating the type of crash
    let header = "exception\n"
    _ = header.utf8.withContiguousStorageIfAvailable { ptr in
        write(fileDescriptor, ptr.baseAddress, ptr.count)
    }
    
    // Write the exception name
    let name = exception.name.rawValue
    _ = name.utf8.withContiguousStorageIfAvailable { ptr in
        write(fileDescriptor, ptr.baseAddress, ptr.count)
    }
    _ = "\n".utf8.withContiguousStorageIfAvailable { ptr in
        write(fileDescriptor, ptr.baseAddress, ptr.count)
    }
    
    // Write the reason
    if let reason = exception.reason {
        _ = reason.utf8.withContiguousStorageIfAvailable { ptr in
            write(fileDescriptor, ptr.baseAddress, ptr.count)
        }
        _ = "\n".utf8.withContiguousStorageIfAvailable { ptr in
            write(fileDescriptor, ptr.baseAddress, ptr.count)
        }
    }
    
    // Write stack trace using backtrace_symbols_fd, which is async-signal-safe.
    // Get raw backtrace symbols
    var callStack = [UnsafeMutableRawPointer?](repeating: nil, count: 128)
    let frameCount = backtrace(&callStack, Int32(callStack.count))
    
    if frameCount > 0 {
        backtrace_symbols_fd(&callStack, frameCount, fileDescriptor)
    }

    // Unregister the handler and allow the default crash mechanism to take over.
    NSSetUncaughtExceptionHandler(nil)
    exception.raise()
}


// TODO: Handles catching native exceptions.
final class CrashCatcher {
    // Simple re-entrancy guard: 0 = not crashing, 1 = handling crash
    static var isHandlingCrash: Int32 = 0

    
    static func register() {
        // Set our custom handler.
        NSSetUncaughtExceptionHandler(uncaughtExceptionHandler)
    }
    
    static func crashReportURL() -> URL {
        // This is a simplified path. In a real app, this should be a more robust path
        // inside Application Support. We'll refine this in the Reports module.
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent("crash.raw")
    }
}
