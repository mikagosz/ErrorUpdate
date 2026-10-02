//
//  OperationWatch.swift
//  ErrorUpdate
//

import Foundation

/// A running operation that should end within a limit. Call ``end()`` when it
/// does; if the limit passes first, one report is filed.
///
/// Why it exists: a memory cleanup in one of the author's apps once sat at 95 %
/// for 24 hours on a `waitUntilExit()` without a limit. Nothing crashed and
/// the UI kept working, so neither the crash handlers nor a main-thread hang
/// check could see it. Only the operation itself knows how long is too long.
public final class OperationWatch: @unchecked Sendable {

    /// What an overdue operation reports.
    public struct Overdue: Sendable, Equatable {
        public let name: String
        public let limit: TimeInterval
        /// The call stack where the operation was started — the stuck code is
        /// usually below it.
        public let startedFrom: [String]
    }

    public let name: String
    public let limit: TimeInterval
    private let lock = NSLock()
    private var ended = false

    /// Starts watching. `onOverdue` runs once, on a background queue, only if
    /// ``end()`` has not been called within `limit` seconds.
    init(name: String, limit: TimeInterval, onOverdue: @escaping @Sendable (Overdue) -> Void) {
        self.name = name
        self.limit = limit
        let overdue = Overdue(name: name, limit: limit, startedFrom: Array(Thread.callStackSymbols.dropFirst()))
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) { [self] in
            lock.lock()
            let alreadyEnded = ended
            ended = true
            lock.unlock()
            if !alreadyEnded { onOverdue(overdue) }
        }
    }

    /// Marks the operation as finished. Safe to call more than once and from any thread.
    public func end() {
        lock.lock()
        ended = true
        lock.unlock()
    }
}
