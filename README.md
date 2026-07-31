<p align="center">
  <img src="docs/assets/errorupdate-icon.png" width="160" alt="ErrorUpdate icon">
</p>

## ErrorUpdate

**Crash reporting and self-updates for macOS apps outside the App Store.**
No paid Apple Developer account required.

[![Swift Package Manager](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![Swift 6.4](https://img.shields.io/badge/Swift-6.4-F05138?logo=swift&logoColor=white)](https://swift.org)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey.svg)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A lightweight, zero-dependency Swift package that adds **crash/error reporting**
and **self-updating** to macOS apps distributed outside the App Store.

> Status: **0.1.x (beta)** — used in the author's own apps. Feedback and issues welcome.

## Features

- **Automatic Crash Reporting:** Captures native Objective-C exceptions and fatal signals (e.g. `SIGSEGV`) using async-signal-safe file writes; the crash is turned into a report on the next launch.
- **Manual Error Logging:** `ErrorUpdateManager.shared.logError()` reports non-fatal Swift errors with custom context.
- **Local Report Store:** Reports are persisted on disk and deduplicated (identical errors within 24 h merge into one entry with a counter).
- **Update Checking:** Periodically checks a remote server for new versions, with retry and exponential backoff.
- **Verified Downloads:** Updates are verified with SHA-256 and, optionally, an Ed25519 signature before installation. The app bundle's code signature is checked with `codesign` before it replaces the old version (works with ad-hoc signed apps — no paid account needed).
- **Safe Install & Relaunch:** The previous version is kept as a backup until the copy succeeds; the app can relaunch into the new version.
- **SwiftUI Integration:** `ErrorUpdateManager` is an `ObservableObject` — bind `pendingReports` and `availableUpdate` directly to your views. Ready-made dialogs (`UIPresenter`) are also included.
- **Static Hosting Friendly:** The "server" is just two static files — works with GitHub Pages/Releases or any file host.
- **Release CLI:** `errorupdate-tool` generates signing keys and release manifests.

## Installation

In Xcode: **File → Add Package Dependencies...** and enter this repository's URL,
then add the `ErrorUpdate` library to your app target.

Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mikagosz/ErrorUpdate.git", from: "0.1.0"),
]
```

> **Note:** If your app target is also named `ErrorUpdate`, set a different
> **Product Module Name** in the target's build settings so the app can import the library.

## Basic Usage

For detailed instructions, see [INTEGRATION_GUIDE.md](INTEGRATION_GUIDE.md).
A complete working app is in [DemoApp/](DemoApp/).

```swift
import SwiftUI
import ErrorUpdate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ErrorUpdateManager.shared.configure(
            ErrorUpdateConfig(
                serverURL: URL(string: "https://your-server.com")!,
                publicKey: Data(base64Encoded: "YOUR-ED25519-PUBLIC-KEY")!
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

The framework expects two endpoints under `serverURL` — both can be plain static files:

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
- `POST /api/error-update/report` — receives an `ErrorReport` as JSON
  (optional; without a dynamic server, reports stay local and can be emailed by the user).

Requests carry `X-App-ID`, `X-API-Key` and `X-Current-Version` headers.

## Release Tooling

```bash
# One-time: generate an Ed25519 signing key pair (private key stays local!)
swift run errorupdate-tool keygen --out keys

# For every release: compute SHA-256 + signature and produce the manifest
swift run errorupdate-tool release \
    --file MyApp-1.2.0.zip --version 1.2.0 \
    --url https://myserver.com/downloads/MyApp-1.2.0.zip \
    --key keys/errorupdate_private_key.txt \
    --notes "What's new" --out version-check
```

Upload `version-check` (as `<serverURL>/api/error-update/version-check`) and the
ZIP to any static file host.

## Local Test Server

[TestServer/](TestServer/) contains scripts that build the demo app, package it
as "version 9.9.9" and serve it from `http://127.0.0.1:8000`, so the full update
cycle can be tested without any hosting:

```bash
./TestServer/prepare.sh
./TestServer/start.sh
# then run DemoApp and click "Check for updates"
```

The end-to-end test runs the whole cycle (check → download → verify → install)
against that server:

```bash
ERRORUPDATE_E2E_SERVER=http://127.0.0.1:8000 \
ERRORUPDATE_E2E_PUBKEY=$(cat keys/errorupdate_public_key.txt) \
swift test --filter EndToEndTests
```

## Requirements & Limitations

- macOS 13+
- The update installer replaces the app bundle on disk, so it does **not** work
  inside the App Sandbox (error reporting works fine in sandboxed apps).
  Apps distributed through the App Store must use App Store updates instead.
- Ed25519 signature verification is skipped when no public key is configured —
  always configure it for production.

## License

[MIT](LICENSE)
