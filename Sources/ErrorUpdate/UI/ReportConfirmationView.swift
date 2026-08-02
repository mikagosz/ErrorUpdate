//
//  ReportConfirmationView.swift
//  ErrorUpdate
//

import SwiftUI

public struct ReportConfirmationView: View {

    // MARK: - Properties

    let report: ErrorReport

    @State private var includeEmail: Bool = false
    @State private var userEmail: String = ""
    @State private var showDetails: Bool = false

    // Actions to be provided by the presenter
    var onSend: (String?) -> Void
    var onDiscard: () -> Void

    public init(report: ErrorReport, onSend: @escaping (String?) -> Void, onDiscard: @escaping () -> Void) {
        self.report = report
        self.onSend = onSend
        self.onDiscard = onDiscard
    }

    /// Set with `.errorUpdateTheme(_:)`; defaults to the framework's neon look.
    @Environment(\.errorUpdateTheme) private var theme

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 20) {
            header

            Divider().background(theme.border)

            content

            if showDetails {
                detailsSection
            }

            Divider().background(theme.border)

            actions
        }
        .padding(30)
        .frame(minWidth: 450, maxWidth: 600)
        .modifier(ErrorUpdateChrome(theme: theme, glow: theme.errorAccent))
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(theme.errorAccent)

            VStack(alignment: .leading) {
                Text("Application Error Detected")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(theme.title)

                Text("An unexpected error occurred. Sending a report helps us fix the issue.")
                    .font(.callout)
                    .foregroundColor(theme.primaryText)
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text(report.errorMessage)
                .font(.headline)
                .foregroundColor(theme.primaryText)

            Toggle(isOn: $includeEmail) {
                Text("Include email for response")
            }
            .toggleStyle(CheckboxToggleStyle())
            .foregroundColor(theme.primaryText)

            if includeEmail {
                TextField("your.email@example.com", text: $userEmail)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(theme.secondaryBackground)
                    .cornerRadius(5)
            }
        }
    }

    private var detailsSection: some View {
        ScrollView {
            Text(ReportBuilder.formatAsPlainText(report: report))
                .font(.system(.body, design: .monospaced))
                .foregroundColor(theme.primaryText)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.secondaryBackground)
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
                onSend(includeEmail && !userEmail.isEmpty ? userEmail : nil)
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Previews

struct ReportConfirmationView_Previews: PreviewProvider {
    static var previews: some View {
        let sampleReport = ErrorReport(
            errorMessage: "Could not save file to the designated path.",
            stackTrace: [
                "0   MyApp                               0x0000000100003d40 main + 0",
                "1   libdyld.dylib                       0x00007fff203f5f3d start + 1"
            ],
            appVersion: "1.0.0-preview",
            customContext: ["screen": "MainWindow", "action": "saveFile"]
        )

        ReportConfirmationView(report: sampleReport, onSend: { _ in }, onDiscard: {})
    }
}
