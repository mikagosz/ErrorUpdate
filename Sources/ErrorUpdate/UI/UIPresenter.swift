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
        // `NSHostingController` rather than an `NSHostingView` assigned as
        // `contentView`: a view plugged in directly inherited the window's fixed frame
        // (480×300) with no way to push it open. The report dialog expands its details
        // section by another ~200 points, so "Show Details" revealed **nothing** — the
        // content simply did not fit a window that could not even be resized.
        // A controller with `preferredContentSize` reports the content size to the
        // window, and the window follows it.
        let hostingController = NSHostingController(rootView: view.errorUpdateTheme(theme))
        hostingController.sizingOptions = [.preferredContentSize]

        // `.resizable` stays as a safety valve: with unusual font sizes the content
        // can still be revealed by hand.
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView, .resizable]
        if isClosable {
            styleMask.insert(.closable)
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: styleMask,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentViewController = hostingController
        window.title = title
        // With the controller in place the window knows its content size, so only now
        // does centring use the real size rather than the pre-fit 480×300.
        window.setContentSize(hostingController.view.fittingSize)
        window.center()
        self.window = window

        // Release the presentation slot no matter how the window is closed.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { _ in
            Task { @MainActor in Self.isPresenting = false }
        }

        // No `ignoringOtherApps`: the check runs on a timer, so the window can
        // appear while someone is typing in another app — and a Return meant for
        // that app would land on "Install Now". The window waits in front of this
        // app's windows; macOS brings it forward when the user switches here.
        window.makeKeyAndOrderFront(nil)
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
