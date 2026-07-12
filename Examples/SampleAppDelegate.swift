//
//  SampleAppDelegate.swift
//  ErrorUpdate Example
//

import AppKit
import ErrorUpdate

class SampleAppDelegate: NSObject, NSApplicationDelegate {

    private let errorUpdateDelegate = ExampleDelegate()

    func applicationDidFinishLaunching(_ aNotification: Notification) {

        guard let serverURL = URL(string: "https://your-api-server.com") else {
            fatalError("Invalid server URL")
        }

        // 1. Configure the manager
        ErrorUpdateManager.shared.configure(
            ErrorUpdateConfig(
                serverURL: serverURL,
                appID: "com.yourcompany.example-app",
                apiKey: "YOUR_API_KEY",
                publicKey: Data(), // optional Ed25519 public key for update signatures
                reportingOptIn: false, // set true to auto-send reports to the server
                supportEmail: "support@yourcompany.com"
            )
        )

        // 2. (Optional) Set the delegate
        ErrorUpdateManager.shared.delegate = errorUpdateDelegate

        // 3. Enable crash handling (crash reports are stored on next launch)
        ErrorUpdateManager.shared.setupCrashHandling()

        // 4. Start checking for updates automatically (e.g., every 2 hours)
        ErrorUpdateManager.shared.startPeriodicUpdateCheck(interval: 7200)
    }
}

// Optional delegate implementation (all methods are optional)
class ExampleDelegate: ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {
        print("Delegate: caught error \(report.errorMessage)")
    }

    func didDetectUpdate(_ info: UpdateInfo) {
        print("Delegate: update available \(info.latestVersion)")
    }

    func updateDidFail(_ error: Error) {
        print("Delegate: update failed \(error.localizedDescription)")
    }
}
