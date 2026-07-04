//
//  UIPresenter.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import SwiftUI
import AppKit

/// Handles the presentation of SwiftUI views for user interaction.
@available(macOS 11.0, *)
class UIPresenter {
    
    // Simple debouncing to prevent showing multiple windows at once.
    private static var isPresenting = false
    
    private var window: NSWindow?
    
    // MARK: - Error Report Presentation
    
    /// Presents the error report confirmation view in a new window.
    func present(report: ErrorReport) {
        guard Self.ensureSingleWindow() else { return }
        
        let view = ReportConfirmationView(
            report: report,
            onSend: { [weak self] userEmail in
                // The user confirmed. `userEmail` is provided if the checkbox was ticked.
                // We would update the report here before sending.
                print("User consented to send report. Email: \(userEmail ?? "not provided")")
                
                if !EmailComposer.send(report: report) {
                    // Fallback if mailto: fails
                    EmailComposer.copyToClipboard(report: report)
                    // TODO: Show an alert informing the user it's been copied.
                }
                
                self?.closeWindow()
            },
            onDiscard: { [weak self] in
                print("User discarded error report.")
                self?.closeWindow()
            }
        )
        
        display(view: view, title: "Application Error")
    }
    
    // MARK: - Update Presentation
    
    /// Presents the update available view in a new window.
    func present(updateInfo: UpdateInfo, currentVersion: String) {
        guard Self.ensureSingleWindow() else { return }

        // These would be managed by a state object in a real app
        let downloadProgress = Binding.constant(0.0)
        let isDownloading = Binding.constant(false)

        let view = UpdateAvailableView(
            updateInfo: updateInfo,
            currentVersion: currentVersion,
            downloadProgress: downloadProgress,
            isDownloading: isDownloading,
            onInstall: {
                print("User chose to install update.")
                // TODO: Connect this to the UpdateDownloader and UpdateInstaller
            },
            onLater: { [weak self] in
                print("User chose 'Later'.")
                self?.closeWindow()
            },
            onSkip: { [weak self] in
                print("User chose 'Never Ask Again'.")
                // TODO: Set a flag in UserDefaults.
                self?.closeWindow()
            }
        )
        
        display(view: view, title: "Update Available")
    }
    
    // MARK: - Window Management
    
    private func display<V: View>(view: V, title: String) {
        let hostingView = NSHostingView(rootView: view)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window?.center()
        window?.setFrameAutosaveName(title)
        window?.isReleasedWhenClosed = false
        window?.contentView = hostingView
        window?.title = title
        
        // Ensure the window is brought to the front
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func closeWindow() {
        window?.close()
        window = nil
        Self.isPresenting = false
    }
    
    private static func ensureSingleWindow() -> Bool {
        guard !isPresenting else {
            print("UI is already being presented. Skipping new presentation.")
            return false
        }
        isPresenting = true
        return true
    }
}
