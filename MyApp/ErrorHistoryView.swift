import SwiftUI

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
            if manager.pendingReportsCount == 0 {
                Text("Brak zgłoszonych błędów.")
                    .foregroundStyle(.secondary)
                    .padding()
            } else {
                List {
                    ForEach(0..<manager.pendingReportsCount) { _ in
                        Text("Raport błędu (lista demo)")
                    }
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
}

#if DEBUG
#Preview {
    ErrorHistoryView()
}
#endif
