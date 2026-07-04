# ErrorUpdate Framework

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-macOS-lightgrey.svg)](https://www.apple.com/macos)

## Overview

`ErrorUpdate` is a lightweight, zero-dependency Swift package for macOS applications that provides a comprehensive solution for error reporting and application updates.

### Features

- **Automatic Crash Reporting:** Captures native Objective-C exceptions and fatal signals (e.g., `SIGSEGV`).
- **Manual Error Logging:** A simple API (`ErrorLogger.log()`) to report non-fatal Swift errors with custom context.
- **Update Checking:** Automatically checks a remote server for new application versions.
- **Interactive UI:** Presents SwiftUI dialogs to users for sending reports and installing updates.
- **Customizable:** Use the `ErrorUpdateDelegate` to hook into the error and update lifecycle.

## Installation

You can add `ErrorUpdate` to your Xcode project using the Swift Package Manager.

1. In Xcode, open your project and navigate to **File > Add Packages...**
2. In the "Search or Enter Package URL" field, enter the repository URL for this package.
3. Choose your desired dependency rule (e.g., "Up to Next Major Version").
4. Click "Add Package" and select the `ErrorUpdate` library to be added to your app's target.

## Basic Usage

For detailed instructions, please see the `INTEGRATION_GUIDE.md`.

```swift
import SwiftUI
import ErrorUpdate

@main
struct YourApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ErrorUpdateManager.shared.configure(
            serverURL: URL(string: "https://your-server.com")!,
            appID: "com.yourcompany.appname",
            apiKey: "your-secret-key",
            currentVersion: "1.0.0"
        )
        
        // Start catching crashes
        ErrorUpdateManager.shared.setupCrashHandling()
        
        // Check for updates periodically (e.g., every hour)
        ErrorUpdateManager.shared.startPeriodicUpdateCheck(interval: 3600)
    }
}
```
