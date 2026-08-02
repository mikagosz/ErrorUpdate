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
            publicKey: Data(/* raw Ed25519 key */), // makes signatures mandatory
            allowUnsignedUpdates: false,            // true = accept unverified updates
            reportingOptIn: false,                  // true = auto-send reports to the server
            supportEmail: "support@yourcompany.com" // used by the email report dialog
        )
    )

    // ... rest of your setup
}
```

The app version is read automatically from `CFBundleShortVersionString`.

### Signature verification is required by default

`publicKey` is what makes an update trustworthy, so the framework refuses to
download anything it cannot verify:

| `publicKey` | `allowUnsignedUpdates` | Behaviour |
|---|---|---|
| set | either | Every update must carry a valid Ed25519 signature. A manifest without `signature` is **rejected**, not waved through. |
| empty | `false` (default) | Downloads fail with `unsignedUpdatesNotAllowed`. |
| empty | `true` | Downloads proceed with a checksum check only — no protection against a substituted update. |

Generate the key pair with `swift run errorupdate-tool keygen --out keys` and
sign every release with `--key`. Without a signature the checksum comes from the
same manifest as the download URL, so whoever can change one can change both.

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

At most 50 reports are kept on disk; past that the oldest are dropped.

### What you are collecting

A report contains the error message, the stack trace, app and OS versions,
CPU/RAM/free-disk figures, your `customContext`, and an email address if the
user typed one into the dialog.

The stack trace matters most for privacy: `Thread.callStackSymbols` embeds file
paths, and on macOS a path under `/Users/<name>/` reveals the account name.

With `reportingOptIn = true` all of it is uploaded automatically, with no prompt
at the moment of sending — that is a consent decision your privacy policy has to
cover. Leaving it `false` keeps reports local until the user sends one by mail
from the report dialog, where they can see what they are sending.

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

The downloaded file is verified in three steps, and installation stops at the
first one that fails:

1. **SHA-256** against the manifest — catches a corrupted transfer. It proves
   nothing about origin, because the checksum travels in the same manifest.
2. **Ed25519 signature** — the actual authenticity check. Mandatory whenever
   `publicKey` is configured; see the table in section 1.
3. **Identity of the bundle** — the new bundle must be signed (`codesign
   --verify --deep --strict`), carry the same `CFBundleIdentifier` as the
   running app, and satisfy that app's designated requirement (`codesign -R`).

The previous version is kept as a backup until the copy succeeds, and the
installed bundle keeps the name of the app it replaced.

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
- `serverURL` must be HTTPS or a loopback address; `configure()` refuses
  anything else and logs the reason to stderr. The `downloadURL` from the
  manifest is held to the same rule at download time.
- Configure `publicKey` for production. Without it the only way to get updates
  at all is `allowUnsignedUpdates: true`, which accepts whatever the server
  serves — a compromised host then owns your users' machines.
- `codesign -R` proves who signed an update only for apps signed with a
  certificate. An ad-hoc signature pins one build's `cdhash`, so the check is
  skipped (with a warning on stderr) and the Ed25519 signature is the only thing
  standing between your users and a substituted app. A self-signed certificate
  gives a stable requirement and costs nothing.
- Changing the signing certificate between releases makes the requirement match
  fail. Distribute that transition as a manual download.
- `CFBundleIdentifier` must not change between versions, and the installed
  bundle keeps the name of the app it replaces.
- Remember to replace placeholder values (server URL, API key) with production values.
