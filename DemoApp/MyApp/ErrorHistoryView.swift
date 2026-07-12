import SwiftUI
import ErrorUpdate

/// Shows a list of all saved error reports.
struct ErrorHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var manager = ErrorUpdateManager.shared

    var body: some View {
        VStack {
            HStack {
                Text("Historia błędów")
                    .font(.title2.bold())
                Spacer()
                Button("Zamknij") { dismiss() }
            }
            Divider()
            if manager.pendingReports.isEmpty {
                Text("Brak zgłoszonych błędów.")
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
                            Button("Usuń") {
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
    ErrorHistoryView()
}
#endif
