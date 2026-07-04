//
//  ReportConfirmationView.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import SwiftUI

@available(macOS 11.0, *)
public struct ReportConfirmationView: View {
    
    // MARK: - Properties
    
    let report: ErrorReport
    
    @State private var includeEmail: Bool = false
    @State private var userEmail: String = ""
    @State private var showDetails: Bool = false
    
    // Actions to be provided by the presenter
    var onSend: (String?) -> Void
    var onDiscard: () -> Void
    
    // MARK: - Neon Theme Colors
    
    private struct NeonStyle {
        static let backgroundColor = Color.black.opacity(0.9)
        static let primaryTextColor = Color(red: 0.9, green: 0.9, blue: 0.9)
        static let titleColor = Color(red: 0.3, green: 1.0, blue: 0.9) // Cyan
        static let accentColor = Color(red: 1.0, green: 0.2, blue: 0.8) // Magenta
        static let borderColor = Color.white.opacity(0.2)
        static let detailsBackgroundColor = Color.black.opacity(0.5)
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(spacing: 20) {
            header
            
            Divider().background(NeonStyle.borderColor)
            
            content
            
            if showDetails {
                detailsSection
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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(NeonStyle.accentColor)
            
            VStack(alignment: .leading) {
                Text("Application Error Detected")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(NeonStyle.titleColor)
                
                Text("An unexpected error occurred. Sending a report helps us fix the issue.")
                    .font(.callout)
                    .foregroundColor(NeonStyle.primaryTextColor)
            }
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(report.errorMessage)
                .font(.headline)
                .foregroundColor(NeonStyle.primaryTextColor)
            
            Toggle(isOn: $includeEmail) {
                Text("Include email for response")
            }
            .toggleStyle(CheckboxToggleStyle())
            .foregroundColor(NeonStyle.primaryTextColor)
            
            if includeEmail {
                TextField("your.email@example.com", text: $userEmail)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(NeonStyle.detailsBackgroundColor)
                    .cornerRadius(5)
            }
        }
    }
    
    private var detailsSection: some View {
        ScrollView {
            Text(ReportBuilder.formatAsPlainText(report: report))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(NeonStyle.primaryTextColor)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(NeonStyle.detailsBackgroundColor)
        .cornerRadius(8)
        .frame(maxHeight: 200)
    }
    
    private var actions: some View {
        HStack {
            Button("Show Details") {
                withAnimation {
                    showDetails.toggle()
                }
            }
            
            Spacer()
            
            Button("Discard") {
                onDiscard()
            }
            
            Button("Send Report") {
                onSend(includeEmail ? userEmail : nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Previews

@available(macOS 11.0, *)
struct ReportConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleReport = ErrorReport(
            timestamp: Date(),
            appVersion: "1.0.0-preview",
            osVersion: "macOS 14.5",
            errorType: .swiftError,
            errorMessage: "Could not save file to the designated path.",
            stackTrace: [
                "0   MyApp                               0x0000000100003d40 main + 0",
                "1   libdyld.dylib                       0x00007fff203f5f3d start + 1"
            ],
            systemInfo: SystemInfo.current(),
            customContext: ["screen": "MainWindow", "action": "saveFile"],
            userEmail: nil,
            consentEmail: false
        )
        
        ReportConfirmationView(report: sampleReport, onSend: { _ in }, onDiscard: {})
    }
}
