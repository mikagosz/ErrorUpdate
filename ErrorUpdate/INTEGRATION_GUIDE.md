# ErrorUpdate Integration Guide

This guide provides a step-by-step walkthrough for integrating the `ErrorUpdate` framework into your macOS application.

## 1. Configuration

Configure the `ErrorUpdateManager` singleton once, early in the application's lifecycle — `applicationDidFinishLaunching` is the ideal place.

```swift
import ErrorUpdate

// In your AppDelegate.swift
func applicationDidFinishLaunching(_ aNotification: Notification) {

    ErrorUpdateManager.shared.configure(
        ErrorUpdateConfig(
            serverURL: URL(string: "https://your-api-server.com")!,
            appID: "com.yourcompany.your-app-id",   // default: bundle identifier
            apiKey: "YOUR_API_KEY",                 // optional
            publicKey: Data(/* raw Ed25519 key */), // optional, verifies update signatures
            reportingOptIn: false,                  // true = auto-send reports to the server
            supportEmail: "support@yourcompany.com" // used by the email report dialog
        )
    )

    // ... rest of your setup
}
```

The app version is read automatically from `CFBundleShortVersionString`.

## 2. Enabling Crash Handling

To automatically catch native crashes and exceptions, call `setupCrashHandling()` after configuration.

```swift
ErrorUpdateManager.shared.setupCrashHandling()
```

When the app crashes, a raw crash file is written using async-signal-safe calls.
On the **next launch**, `configure()` converts it into an `ErrorReport` and stores it.

## 3. Manual Error Logging

To log non-fatal Swift errors, use `logError`. You can provide an optional `context` dictionary for more detailed reports.

```swift
do {
    try saveData()
} catch {
    ErrorUpdateManager.shared.logError(error, context: [
        "screen": "Settings",
        "action": "savePreferences"
    ])
}
```

Reports are stored locally (deduplicated within 24 h) and exposed via the
`pendingReports` published property. With `reportingOptIn = true` they are also
sent to the server; delivered reports are removed from the store.

```swift
// Send everything that's still pending (e.g. on app start):
await ErrorUpdateManager.shared.sendPendingReports()
```

## 4. Update Checking

### Manual Check

```swift
// In a menu action or button handler:
Task {
    await ErrorUpdateManager.shared.checkForUpdates() // force = true, ignores the 1h cache
}
```

The result lands in the published `availableUpdate` property.

### Periodic Check

```swift
ErrorUpdateManager.shared.startPeriodicUpdateCheck(interval: 3600)
```

Periodic checks respect a 1-hour cache to avoid hammering the server.

### Download & Install

```swift
Task {
    if await ErrorUpdateManager.shared.downloadUpdate() != nil {
        await ErrorUpdateManager.shared.installUpdate() // verifies codesign, swaps the bundle, relaunches
    }
}
```

The downloaded file is verified against the server-provided SHA-256 checksum and,
when `publicKey` is configured, its Ed25519 signature. Before installation the new
bundle's code signature is verified with `codesign`. The previous version is kept
as a backup until the copy succeeds.

## 5. SwiftUI Integration

`ErrorUpdateManager` is a `@MainActor ObservableObject`:

```swift
struct StatusView: View {
    @ObservedObject var manager = ErrorUpdateManager.shared

    var body: some View {
        VStack {
            Text("Pending reports: \(manager.pendingReportsCount)")
            if let update = manager.availableUpdate {
                Text("Update available: \(update.latestVersion)")
            }
        }
    }
}
```

You can also use the bundled dialogs:

```swift
let presenter = UIPresenter()
presenter.present(report: report, supportEmail: "support@yourcompany.com")
presenter.present(updateInfo: info, currentVersion: "1.0.0")
```

## 6. Using the Delegate (Optional)

Conform to `ErrorUpdateDelegate` to receive callbacks. All methods are optional
and called on the main actor.

```swift
class MyDelegate: ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {
        print("Caught an error: \(report.errorMessage)")
    }

    func didDetectUpdate(_ info: UpdateInfo) {
        print("Update detected: \(info.latestVersion)")
    }

    func updateDidFail(_ error: Error) {
        print("Update failed: \(error.localizedDescription)")
    }
}

// Keep a strong reference — the manager holds the delegate weakly.
let myDelegate = MyDelegate()
ErrorUpdateManager.shared.delegate = myDelegate
```

## Notes & Limitations

- The update installer replaces the app bundle on disk, which does **not** work
  inside the App Sandbox. Error reporting works fine in sandboxed apps.
- Ed25519 signature verification is skipped when `publicKey` is empty — configure
  it for production so a compromised server cannot serve a tampered update.
- Remember to replace placeholder values (server URL, API key) with production values.
