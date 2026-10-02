//
//  RelaunchHelper.swift
//  ErrorUpdate
//

import Foundation

/// Opens the updated app only after the old process has ended.
///
/// `open -n` right before `NSApp.terminate` starts the new copy while the old
/// one is still shutting down. For a menu bar app that means two icons and two
/// global key monitors at once, measured in the author's apps; every app using
/// 1.0.1 carried its own copy of this helper to avoid it.
///
/// The helper is `/bin/sh` polling `kill -0` every 0.2 s. launchd adopts it when
/// the app quits. After `limitSeconds` it gives up and does **not** open the app:
/// quitting may have been cancelled (an unsaved document, a delegate saying
/// no), and a second copy next to a live first one is what this exists to prevent.
enum RelaunchHelper {

    static let defaultLimitSeconds = 60

    /// Arguments for `/bin/sh`. The pid, the path and the opener go in as
    /// positional parameters, never pasted into the script, so no character in
    /// the path can change what the helper runs.
    static func arguments(
        waitingFor pid: Int32,
        app: URL,
        opener: String = "/usr/bin/open",
        limitSeconds: Int = defaultLimitSeconds
    ) -> [String] {
        let steps = max(1, limitSeconds) * 5
        let script = """
            i=0
            while /bin/kill -0 "$1" 2>/dev/null; do
              i=$((i + 1))
              [ "$i" -gt \(steps) ] && exit 1
              /bin/sleep 0.2
            done
            exec "$3" "$2"
            """
        return ["-c", script, "sh", String(pid), app.path, opener]
    }

    /// Starts the helper and returns at once.
    @discardableResult
    static func start(
        waitingFor pid: Int32,
        app: URL,
        opener: String = "/usr/bin/open",
        limitSeconds: Int = defaultLimitSeconds
    ) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments(waitingFor: pid, app: app, opener: opener, limitSeconds: limitSeconds)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }
}
