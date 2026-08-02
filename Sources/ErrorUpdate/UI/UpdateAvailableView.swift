//
//  UpdateAvailableView.swift
//  ErrorUpdate
//

import SwiftUI

public struct UpdateAvailableView: View {

    // MARK: - Properties

    let updateInfo: UpdateInfo
    let currentVersion: String
    let isDownloading: Bool

    var onInstall: () -> Void
    var onLater: () -> Void
    var onSkip: () -> Void

    public init(
        updateInfo: UpdateInfo,
        currentVersion: String,
        isDownloading: Bool = false,
        onInstall: @escaping () -> Void,
        onLater: @escaping () -> Void,
        onSkip: @escaping () -> Void
    ) {
        self.updateInfo = updateInfo
        self.currentVersion = currentVersion
        self.isDownloading = isDownloading
        self.onInstall = onInstall
        self.onLater = onLater
        self.onSkip = onSkip
    }

    /// Set with `.errorUpdateTheme(_:)`; defaults to the framework's neon look.
    @Environment(\.errorUpdateTheme) private var theme

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 20) {
            header

            Divider().background(theme.border)

            releaseNotesSection

            if isDownloading {
                progressView
            }

            Divider().background(theme.border)

            actions
        }
        .padding(30)
        .frame(minWidth: 450, maxWidth: 600)
        .modifier(ErrorUpdateChrome(theme: theme, glow: theme.accent))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.largeTitle)
                .foregroundColor(theme.accent)

            VStack(alignment: .leading) {
                Text("Update Available")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(theme.title)

                Text("Version \(updateInfo.latestVersion) is now available. You have \(currentVersion).")
                    .font(.callout)
                    .foregroundColor(theme.primaryText)
            }
        }
    }

    private var releaseNotesSection: some View {
        ScrollView {
            Text(updateInfo.releaseNotes)
                .foregroundColor(theme.primaryText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.secondaryBackground)
        .cornerRadius(8)
        .frame(minHeight: 100, maxHeight: 200)
    }

    private var progressView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
            Text("Downloading update…")
                .font(.caption)
                .foregroundColor(theme.primaryText)
        }
    }

    private var actions: some View {
        HStack {
            if !updateInfo.mandatory {
                Button("Never Ask Again") {
                    onSkip()
                }

                Spacer()

                Button("Later") {
                    onLater()
                }
            } else {
                Text("This update is mandatory.")
                    .font(.caption)
                    .foregroundColor(.gray)
                Spacer()
            }

            Button("Install Now") {
                onInstall()
            }
            .disabled(isDownloading)
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Previews

struct UpdateAvailableView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleUpdate = UpdateInfo(
            latestVersion: "1.1.0",
            releaseNotes: "• Added new feature X.\n• Fixed a bug that caused a crash when saving files.\n• Improved performance and memory usage.",
            downloadURL: URL(string: "https://example.com")!,
            sha256: "abcde12345"
        )

        let mandatoryUpdate = UpdateInfo(
            latestVersion: "2.0.0",
            releaseNotes: "This is a critical security update that must be installed.",
            downloadURL: URL(string: "https://example.com")!,
            sha256: "abcde12345",
            mandatory: true
        )

        Group {
            UpdateAvailableView(
                updateInfo: sampleUpdate,
                currentVersion: "1.0.0",
                isDownloading: true,
                onInstall: {}, onLater: {}, onSkip: {}
            )

            UpdateAvailableView(
                updateInfo: mandatoryUpdate,
                currentVersion: "1.0.0",
                onInstall: {}, onLater: {}, onSkip: {}
            )
        }
    }
}
