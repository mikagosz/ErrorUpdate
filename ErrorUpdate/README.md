# ErrorUpdate Framework

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://www.apple.com/macos)

## Overview

`ErrorUpdate` is a lightweight, zero-dependency Swift package for macOS applications that provides a comprehensive solution for error reporting and application updates.

### Features

- **Automatic Crash Reporting:** Captures native Objective-C exceptions and fatal signals (e.g. `SIGSEGV`) using async-signal-safe file writes; the crash is turned into a report on the next launch.
- **Manual Error Logging:** `ErrorUpdateManager.shared.logError()` reports non-fatal Swift errors with custom context.
- **Local Report Store:** Reports are persisted on disk and deduplicated (identical errors within 24 h merge into one entry with a counter).
- **Update Checking:** Periodically checks a remote server for new versions, with retry and exponential backoff.
- **Verified Downloads:** Updates are verified with SHA-256 and, optionally, an Ed25519 signature before installation. The app bundle's code signature is checked with `codesign` before it replaces the old version.
- **SwiftUI Integration:** `ErrorUpdateManager` is an `ObservableObject` — bind `pendingReports` and `availableUpdate` directly to your views. Ready-made dialogs (`UIPresenter`) are also included.
- **Customizable:** Use `ErrorUpdateDelegate` to hook into the error and update lifecycle.

## Installation

Add `ErrorUpdate` to your Xcode project using the Swift Package Manager:

1. In Xcode, open your project and navigate to **File > Add Package Dependencies...**
2. Enter the repository URL (or use **Add Local...** and select this package's folder).
3. Add the `ErrorUpdate` library to your app's target.

> **Note:** If your app target is also named `ErrorUpdate`, set a different
> **Product Module Name** in the target's build settings so the app can import the library.

## Basic Usage

For detailed instructions, see [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md).

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
            ErrorUpdateConfig(
                serverURL: URL(string: "https://your-server.com")!,
                appID: "com.yourcompany.appname",
                apiKey: "your-secret-key"
            )
        )

        // Start catching crashes
        ErrorUpdateManager.shared.setupCrashHandling()

        // Check for updates periodically (every hour by default)
        ErrorUpdateManager.shared.startPeriodicUpdateCheck()
    }
}
```

## Server API

The framework expects two endpoints under `serverURL`:

- `GET /api/error-update/version-check` — returns JSON:
  ```json
  {
    "latestVersion": "1.2.0",
    "downloadURL": "https://your-server.com/downloads/App-1.2.0.zip",
    "sha256": "<hex sha256 of the file>",
    "signature": "<base64 Ed25519 signature, optional>",
    "releaseNotes": "What's new…",
    "mandatory": false
  }
  ```
- `POST /api/error-update/report` — receives an `ErrorReport` as JSON.

Both requests carry `X-App-ID`, `X-API-Key` and `X-Current-Version` headers.

## Release Tooling

The package ships with a CLI helper:

```bash
# One-time: generate an Ed25519 signing key pair (private key stays local!)
swift run errorupdate-tool keygen --out ../keys

# For every release: compute SHA-256 + signature and produce the manifest
swift run errorupdate-tool release \
    --file MyApp-1.2.0.zip --version 1.2.0 \
    --url https://myserver.com/downloads/MyApp-1.2.0.zip \
    --key ../keys/errorupdate_private_key.txt \
    --notes "What's new" --out version-check
```

Upload `version-check` (as `<serverURL>/api/error-update/version-check`) and the
ZIP to any static file host — no dynamic server needed.

## Local Test Server

`TestServer/` in the repository root contains scripts that build the demo app,
package it as "version 9.9.9" and serve it from `http://127.0.0.1:8000`
(`prepare.sh` + `start.sh`), so the full update cycle can be tested without any
hosting. The end-to-end test (`EndToEndTests`) runs against it:

```bash
./TestServer/prepare.sh
./TestServer/start.sh &
cd ErrorUpdate
ERRORUPDATE_E2E_SERVER=http://127.0.0.1:8000 \
ERRORUPDATE_E2E_PUBKEY=$(cat ../keys/errorupdate_public_key.txt) \
swift test --filter EndToEndTests
```

## Requirements

- macOS 13+
- App Sandbox must be **disabled** for the update installer to replace the app bundle
  (error reporting works fine in sandboxed apps).
