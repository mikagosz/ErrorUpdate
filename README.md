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

> Status: **0.2.x (beta)** — used in the author's own apps. Feedback and issues welcome.
>
> 0.2.0 is a security release and **changes behaviour in ways that can stop
> updates**: signatures became mandatory, plain HTTP is refused, and an update
> must now match the running app's bundle identifier and signing identity. Read
> [Requirements & Limitations](#requirements--limitations) before upgrading.
> The check → download → install cycle has been run end to end against a live
> server, in both directions: a legitimate update installs, and a package with a
> valid SHA-256 **and** a valid Ed25519 signature is still rejected when its code
> signature comes from a different identity. Still beta because `relaunch` and the
> crash handlers have not been exercised for real — the first restarts the app,
> the second needs an actual fatal signal — and because nobody outside the
> author's own apps uses it yet.

## Features

- **Automatic Crash Reporting:** Captures native Objective-C exceptions and fatal signals (e.g. `SIGSEGV`) using async-signal-safe file writes; the crash is turned into a report on the next launch.
- **Manual Error Logging:** `ErrorUpdateManager.shared.logError()` reports non-fatal Swift errors with custom context.
- **Local Report Store:** Reports are persisted on disk and deduplicated (identical errors within 24 h merge into one entry with a counter).
- **Update Checking:** Periodically checks a remote server for new versions, with retry and exponential backoff.
- **Verified Downloads:** Authenticity comes from the Ed25519 signature — once a public key is configured, an update without a valid signature is refused, and a manifest that omits the signature cannot turn the check off. SHA-256 catches a corrupted transfer only, since the checksum arrives from the same manifest as the download URL.
- **Same-App, Same-Signer Install:** Before an update replaces the running app, its `CFBundleIdentifier` must match and its code signature must satisfy the running app's designated requirement. See the limitations below for what this cannot do for ad-hoc signed apps.
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
    .package(url: "https://github.com/mikagosz/ErrorUpdate.git", from: "0.2.0"),
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
    "available": true,
    "downloadURL": "https://your-server.com/downloads/App-1.2.0.zip",
    "sha256": "<hex sha256 of the file>",
    "signature": "<base64 Ed25519 signature, required when the app configures a public key>",
    "releaseNotes": "What's new…",
    "mandatory": false
  }
  ```
- `POST /api/error-update/report` — receives an `ErrorReport` as JSON
  (optional; without a dynamic server, reports stay local and can be emailed by the user).

Requests carry `X-App-ID`, `X-API-Key` and `X-Current-Version` headers.

`available` defaults to `true` when absent; set it to `false` (or pass
`--unavailable` to the release tool) to publish a manifest without offering the
update yet. Apps will not report it until the flag flips back.

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

The demo app is ad-hoc signed by default, which means the installer skips the
signing-identity check (see the limitations below). To exercise the full
verification path, pass your own certificate — the identity is never committed:

```bash
ERRORUPDATE_SIGNING_IDENTITY=<fingerprint> ./TestServer/prepare.sh
```

Find the fingerprint with `security find-identity -p codesigning` (omit `-v`:
a self-signed root is not "valid" by that filter, yet signs perfectly well).

The same variable enables an opt-in test that a bundle signed by that
certificate is accepted as an update to another bundle signed by it — the path
every real integrator depends on, which cannot be covered without a certificate:

```bash
ERRORUPDATE_SIGNING_IDENTITY=<fingerprint> swift test
```

The end-to-end test runs the whole cycle (check → download → verify → install)
against that server:

```bash
ERRORUPDATE_E2E_SERVER=http://127.0.0.1:8000 \
ERRORUPDATE_E2E_PUBKEY=$(cat keys/errorupdate_public_key.txt) \
swift test --filter EndToEndTests
```

## What a Report Contains

Every stored report carries:

| Field | Notes |
|---|---|
| `errorMessage` | Exception reason or `localizedDescription` — may quote user data your app put in the error |
| `stackTrace` | `Thread.callStackSymbols`. **On macOS these frames include file paths, and a path under `/Users/<name>/` discloses the account name.** |
| `appVersion`, `osVersion` | — |
| `systemInfo` | CPU model, RAM, free disk space |
| `customContext` | Whatever your app passes to `logError(_:context:)` |
| `contactEmail` | Only when the user types it into the report dialog |

Reports stay on the user's disk until they are sent or discarded. **With
`reportingOptIn: true` all of the above is uploaded to your server
automatically, without asking the user each time** — so treat that switch as a
consent decision and describe the collection in your privacy policy. The email
route (`UIPresenter`) is different: the user sees the report and presses send.

If you cannot disclose account names, strip the home-directory prefix from
`stackTrace` before sending, or keep `reportingOptIn: false` and let users
submit reports by mail.

## Requirements & Limitations

- macOS 13+
- The update installer replaces the app bundle on disk, so it does **not** work
  inside the App Sandbox (error reporting works fine in sandboxed apps).
  Apps distributed through the App Store must use App Store updates instead.
- **Downloads are capped at `maxDownloadBytes` (1 GB by default).** The transfer
  is cancelled as soon as it passes the limit, or immediately when the server
  announces a larger `Content-Length` — verification can only run on a file that
  already exists, so the size has to be bounded while it arrives.
- **HTTPS is required.** `configure()` refuses a plain-HTTP `serverURL`, and a
  download URL that is not HTTPS is rejected even when the manifest itself
  arrived over HTTPS. Loopback (`localhost`, `127.0.0.1`, `::1`) stays allowed
  so the bundled test server works.
- **Signatures are mandatory once `publicKey` is set.** An update whose manifest
  has no `signature`, or whose signature does not verify, is rejected — the
  server cannot switch verification off by omitting the field.
- **Running without a public key requires `allowUnsignedUpdates: true`.**
  In that mode an update is only checked against a checksum the same server
  supplies, which protects against a corrupted transfer and nothing else.
  Anyone who can serve the manifest can serve the app.
- **`codesign` proves origin only for apps signed with a certificate.** The
  installer requires the update to satisfy the running app's designated
  requirement. For an ad-hoc signed app that requirement pins one build's
  `cdhash`, which no later version can ever satisfy, so the check is skipped
  with a warning on stderr — for ad-hoc apps authenticity rests entirely on the
  Ed25519 signature. A self-signed certificate is enough to get a stable
  requirement; no paid account is needed.
- **The installed app keeps the name of the app it replaces.** Renaming the
  bundle between releases has no effect on disk; the `CFBundleIdentifier` must
  stay the same across versions or the update is rejected.
- Changing the signing certificate (expiry, or moving from ad-hoc to a
  certificate) breaks the requirement match. Ship that transition as a manual
  download, not as an update.

## License

[MIT](LICENSE)
