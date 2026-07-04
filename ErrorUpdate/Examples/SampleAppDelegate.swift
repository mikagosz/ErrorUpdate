//
//  SampleAppDelegate.swift
//  ErrorUpdate Example
//
//  Created by Gemini on 2026-07-04.
//

import AppKit
import ErrorUpdate

class SampleAppDelegate: NSObject, NSApplicationDelegate {
    
    private let errorUpdateDelegate = ExampleDelegate()
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        guard let serverURL = URL(string: "https://your-api-server.com") else {
            fatalError("Invalid server URL")
        }
        
        let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"

        // 1. Configure the manager
        ErrorUpdateManager.shared.configure(
            serverURL: serverURL,
            appID: "com.yourcompany.example-app",
            apiKey: "YOUR_API_KEY",
            currentVersion: currentVersion
        )
        
        // 2. (Optional) Set the delegate
        ErrorUpdateManager.shared.delegate = errorUpdateDelegate
        
        // 3. Enable crash handling
        ErrorUpdateManager.shared.setupCrashHandling()
        
        // 4. Start checking for updates automatically (e.g., every 2 hours)
        ErrorUpdateManager.shared.startPeriodicUpdateCheck(interval: 7200)
    }
}

// Optional delegate implementation
class ExampleDelegate: ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {
        print("--- DELEGATE: Did Catch Error ---")
        print("Error: \(report.errorMessage)")
        print("---------------------------------")
    }
    
    func didDetectUpdate(_ info: UpdateInfo) {
        print("--- DELEGATE: Did Detect Update ---")
        print("Version: \(info.latestVersion)")
        print("---------------------------------")
    }
    
    func updateDidFail(_ error: Error) {
        print("--- DELEGATE: Update Did Fail ---")
        print("Error: \(error.localizedDescription)")
        print("--------------------------------")
    }
}
