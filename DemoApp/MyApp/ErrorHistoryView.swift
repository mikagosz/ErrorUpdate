import SwiftUI
import ErrorUpdate

/// Shows a list of all saved error reports.
struct ErrorHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ErrorUpdateManager.shared
    /// Passed in rather than created here, so the sheet speaks the language the
    /// picker in the main window is set to.
    let loc: Localization

    var body: some View {
        VStack {
            HStack {
                Text(loc.t("Historia błędów", "Error history"))
                    .font(.title2.bold())
                Spacer()
                Button(loc.t("Zamknij", "Close")) { dismiss() }
            }
            Divider()
            if manager.pendingReports.isEmpty {
                Text(loc.t("Brak zgłoszonych błędów.", "No errors reported."))
                    .foregroundStyle(.secondary)
                    .padding()
                Spacer()
            } else {
                List(manager.pendingReports) { report in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(report.errorMessage)
                                .font(.headline)
                                .lineLimit(2)
                            Spacer()
                            if report.count > 1 {
                                Text("×\(report.count)")
                                    .font(.caption.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Capsule().fill(.orange.opacity(0.3)))
                            }
                        }
                        HStack {
                            Text(report.errorType.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(report.timestamp, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(report.timestamp, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(loc.t("Usuń", "Delete")) {
                                manager.discardReport(report.id)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear { manager.refreshPendingReports() }
    }
}

#if DEBUG
#Preview {
    ErrorHistoryView(loc: Localization())
}
#endif
