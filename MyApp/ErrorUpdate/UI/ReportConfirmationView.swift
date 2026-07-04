import SwiftUI

/// Modal view to confirm sending a single error report.
struct ReportConfirmationView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ErrorUpdateManager.shared
    @State private var email: String = ""
    @State private var showDetails = false
    @State private var sent = false

    let report: ErrorReport

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Potwierdź wysłanie")
                .font(.headline)

            Text("Typ błędu: \(report.errorType)")

            if let emailField = (report.contactEmail ?? email).isEmpty ? nil : (report.contactEmail ?? email) {
                Text("E-mail: \(emailField)")
            }

            TextField("Twój e-mail (opcjonalnie)", text: $email)
                .textFieldStyle(.roundedBorder)

            DisclosureGroup(isExpanded: $showDetails) {
                Text("Szczegóły techniczne:")
                    .font(.caption)
                ScrollView {
                    Text(report.stackTrace.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .padding(8)
                        .background(Color(.controlBackgroundColor))
                        .cornerRadius(6)
                }
            } label: {
                Text("Pokaż szczegóły techniczne")
            }

            HStack {
                Spacer()
                Button("Anuluj") { dismiss() }
                Button("Wyślij") {
                    sent = true
                    manager.logError(NSError(domain: "Manual", code: 0))
                    dismiss()
                }
            }
        }
        .padding()
        .frame(width: 400, height: 350)
        .overlay {
            if sent {
                Color.white.opacity(0.8)
                    .ignoresSafeArea()
                    .overlay {
                        Text("Wysłano!")
                            .font(.headline)
                    }
            }
        }
    }
}

// Convenience initializer using a sample report.
extension ReportConfirmationView {
    init(sampleReport: ErrorReport = ErrorReport(
        errorType: "Sample Error",
        message: "Something went wrong.",
        stackTrace: ["thread #1: main", "frame #0: MyApp.main()"],
        osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
        appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
    )) {
        self.report = sampleReport
    }
}

#if DEBUG
#Preview {
    ReportConfirmationView()
}
#endif
