# ErrorUpdate Integration Guide

This guide provides a step-by-step walkthrough for integrating the `ErrorUpdate` framework into your macOS application.

## 1. Configuration

The first step is to configure the `ErrorUpdateManager` singleton. This should be done once, early in the application's lifecycle. The `applicationDidFinishLaunching` method in your `AppDelegate` is the ideal place for this.

```swift
import ErrorUpdate

// In your AppDelegate.swift
func applicationDidFinishLaunching(_ aNotification: Notification) {
    
    guard let serverURL = URL(string: "https://your-api-server.com") else {
        fatalError("Invalid server URL")
    }
    
    // Get the current app version from your Info.plist
    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

    ErrorUpdateManager.shared.configure(
        serverURL: serverURL,
        appID: "com.yourcompany.your-app-id",
        apiKey: "YOUR_API_KEY",
        currentVersion: currentVersion,
        userEmail: "user@example.com" // Optional: pre-fill user's email
    )
    
    // ... rest of your setup
}
```

## 2. Enabling Crash Handling

To automatically catch native crashes and exceptions, call `setupCrashHandling()` after configuration.

```swift
// In your AppDelegate.swift, after configure()
ErrorUpdateManager.shared.setupCrashHandling()
```

## 3. Manual Error Logging

To log non-fatal Swift errors, use the `logError` method. You can provide an optional `context` dictionary for more detailed reports.

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

## 4. Update Checking

### Manual Check

You can trigger an update check at any time, for example, from a "Check for Updates..." menu item.

```swift
// In a menu action or button handler
ErrorUpdateManager.shared.checkForUpdates()
```

### Periodic Check

To automatically check for updates in the background, start the periodic checker. An interval of 3600 seconds (1 hour) is a common choice.

```swift
// In your AppDelegate.swift, after configure()
ErrorUpdateManager.shared.startPeriodicUpdateCheck(interval: 3600)
```

## 5. Using the Delegate (Optional)

You can conform to the `ErrorUpdateDelegate` to receive callbacks and customize behavior.

```swift
class MyDelegate: ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {
        // Log to a local file, send to another analytics service, etc.
        print("Caught an error: \(report.errorMessage)")
    }
    
    func didDetectUpdate(_ info: UpdateInfo) {
        // Maybe you want to show a custom UI before the default one.
        print("Update detected: \(info.latestVersion)")
    }
    
    func updateDidFail(_ error: Error) {
        // Handle a failed download or installation.
        print("Update failed: \(error.localizedDescription)")
    }
}

// In your AppDelegate.swift
let myDelegate = MyDelegate()

func applicationDidFinishLaunching(_ aNotification: Notification) {
    // ... configure ...
    ErrorUpdateManager.shared.delegate = myDelegate
}
```

This covers the complete integration of the framework. Remember to replace placeholder values like the server URL and API key with your actual production values.
