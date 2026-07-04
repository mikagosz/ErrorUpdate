//
//  UpdateAvailableView.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import SwiftUI

@available(macOS 11.0, *)
public struct UpdateAvailableView: View {
    
    // MARK: - Properties
    
    let updateInfo: UpdateInfo
    let currentVersion: String
    
    // State for the download process
    @Binding var downloadProgress: Double // 0.0 to 1.0
    @Binding var isDownloading: Bool
    
    // Actions to be provided by the presenter
    var onInstall: () -> Void
    var onLater: () -> Void
    var onSkip: () -> Void
    
    // MARK: - Neon Theme Colors
    
    private struct NeonStyle {
        static let backgroundColor = Color.black.opacity(0.9)
        static let primaryTextColor = Color(red: 0.9, green: 0.9, blue: 0.9)
        static let titleColor = Color(red: 0.3, green: 1.0, blue: 0.9) // Cyan
        static let accentColor = Color(red: 0.2, green: 0.8, blue: 1.0) // Light Blue
        static let borderColor = Color.white.opacity(0.2)
        static let detailsBackgroundColor = Color.black.opacity(0.5)
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 20) {
            header
            
            Divider().background(NeonStyle.borderColor)
            
            releaseNotesSection
            
            if isDownloading {
                progressView
            }
            
            Divider().background(NeonStyle.borderColor)
            
            actions
        }
        .padding(30)
        .background(NeonStyle.backgroundColor)
        .frame(minWidth: 450, maxWidth: 600)
        .cornerRadius(15)
        .shadow(color: NeonStyle.accentColor.opacity(0.4), radius: 10, x: 0, y: 0)
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(NeonStyle.borderColor, lineWidth: 1)
        )
    }
    
    // MARK: - Subviews
    
    private var header: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .font(.largeTitle)
                .foregroundColor(NeonStyle.accentColor)
            
            VStack(alignment: .leading) {
                Text("Update Available")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(NeonStyle.titleColor)
                
                Text("Version \(updateInfo.latestVersion) is now available. You have \(currentVersion).")
                    .font(.callout)
                    .foregroundColor(NeonStyle.primaryTextColor)
            }
        }
    }
    
    private var releaseNotesSection: some View {
        ScrollView {
            Text(updateInfo.releaseNotes)
                .foregroundColor(NeonStyle.primaryTextColor)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NeonStyle.detailsBackgroundColor)
        .cornerRadius(8)
        .frame(minHeight: 100, maxHeight: 200)
    }
    
    private var progressView: some View {
        VStack {
            ProgressView(value: downloadProgress)
                .progressViewStyle(LinearProgressViewStyle())
            Text(String(format: "Downloading... %.0f%%", downloadProgress * 100))
                .font(.caption)
                .foregroundColor(NeonStyle.primaryTextColor)
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

@available(macOS 11.0, *)
struct UpdateAvailableView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleUpdate = UpdateInfo(
            latestVersion: "1.1.0",
            available: true,
            releaseNotes: "• Added new feature X.
• Fixed a bug that caused a crash when saving files.
• Improved performance and memory usage.",
            downloadURL: URL(string: "https://example.com")!,
            sha256: "abcde12345",
            mandatory: false
        )
        
        let mandatoryUpdate = UpdateInfo(
            latestVersion: "2.0.0",
            available: true,
            releaseNotes: "This is a critical security update that must be installed.",
            downloadURL: URL(string: "https://example.com")!,
            sha256: "abcde12345",
            mandatory: true
        )
        
        Group {
            UpdateAvailableView(
                updateInfo: sampleUpdate,
                currentVersion: "1.0.0",
                downloadProgress: .constant(0.65),
                isDownloading: .constant(true),
                onInstall: {}, onLater: {}, onSkip: {}
            )
            
            UpdateAvailableView(
                updateInfo: mandatoryUpdate,
                currentVersion: "1.0.0",
                downloadProgress: .constant(0.0),
                isDownloading: .constant(false),
                onInstall: {}, onLater: {}, onSkip: {}
            )
        }
    }
}
