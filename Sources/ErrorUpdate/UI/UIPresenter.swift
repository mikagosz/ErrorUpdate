//
//  UIPresenter.swift
//  ErrorUpdate
//

import SwiftUI
import AppKit

/// Presents the framework's SwiftUI dialogs in standalone windows.
@MainActor
public final class UIPresenter {

    // Prevents stacking multiple ErrorUpdate windows. Reset from the window's
    // willClose notification, so closing via the title bar also releases it.
    private static var isPresenting = false

    private var window: NSWindow?
    private var closeObserver: NSObjectProtocol?
    private let theme: ErrorUpdateTheme

    /// - Parameter theme: Appearance of the dialogs. Defaults to the framework's
    ///   neon look; pass `.system` to follow the host app's appearance, or build
    ///   your own `ErrorUpdateTheme`.
    public init(theme: ErrorUpdateTheme = .neon) {
        self.theme = theme
    }

    // MARK: - Error Report Presentation

    /// Presents the error report confirmation dialog.
    /// - Parameter supportEmail: Recipient address used when the user chooses to send.
    public func present(report: ErrorReport, supportEmail: String) {
        guard Self.beginPresenting() else { return }

        let view = ReportConfirmationView(
            report: report,
            onSend: { [weak self] userEmail in
                var reportToSend = report
                reportToSend.contactEmail = userEmail
                EmailComposer.send(report: reportToSend, to: supportEmail)
                self?.closeWindow()
            },
            onDiscard: { [weak self] in
                self?.closeWindow()
            }
        )

        display(view: view, title: "Application Error")
    }

    // MARK: - Update Presentation

    /// Presents the "update available" dialog wired to `ErrorUpdateManager`.
    public func present(updateInfo: UpdateInfo, currentVersion: String) {
        guard Self.beginPresenting() else { return }

        let view = UpdateAvailableWindowContent(
            updateInfo: updateInfo,
            currentVersion: currentVersion,
            onClose: { [weak self] in self?.closeWindow() }
        )

        // A mandatory update hides "Later", so leaving the window closable made
        // the obligation cosmetic — the user just clicked the red dot instead.
        // The app can still be quit; only dismissing the dialog is refused.
        display(view: view, title: "Update Available", isClosable: !updateInfo.mandatory)
    }

    // MARK: - Window Management

    private func display<V: View>(view: V, title: String, isClosable: Bool = true) {
        let hostingView = NSHostingView(rootView: view.errorUpdateTheme(theme))

        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if isClosable {
            styleMask.insert(.closable)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.title = title
        self.window = window

        // Release the presentation slot no matter how the window is closed.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in Self.isPresenting = false }
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeWindow() {
        window?.close()
        window = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        Self.isPresenting = false
    }

    private static func beginPresenting() -> Bool {
        guard !isPresenting else { return false }
        isPresenting = true
        return true
    }
}

/// Wraps `UpdateAvailableView`, driving download/install through the manager.
private struct UpdateAvailableWindowContent: View {
    let updateInfo: UpdateInfo
    let currentVersion: String
    let onClose: () -> Void

    @State private var isDownloading = false

    var body: some View {
        UpdateAvailableView(
            updateInfo: updateInfo,
            currentVersion: currentVersion,
            isDownloading: isDownloading,
            onInstall: {
                isDownloading = true
                Task { @MainActor in
                    let manager = ErrorUpdateManager.shared
                    if await manager.downloadUpdate() != nil {
                        await manager.installUpdate()
                    }
                    isDownloading = false
                }
            },
            onLater: onClose,
            onSkip: {
                SkippedVersionStore().skip(updateInfo.latestVersion)
                onClose()
            }
        )
    }
}
