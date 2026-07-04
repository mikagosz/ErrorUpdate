import SwiftUI

/// Main control panel view for the ErrorUpdate framework.
struct ErrorUpdateContentView: View {
    @ObservedObject private var manager = ErrorUpdateManager.shared
    @State private var isChecking = false
    @State private var showingErrorHistory = false
    @State private var showingConfirmSheet = false
    @State private var showingUpdateSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                Image("PanelIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)
                Text("ErrorUpdate")
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.bottom, 10)

            // Updates section
            VStack(alignment: .leading) {
                Text("Aktualizacje")
                    .font(.title2.bold())
                HStack {
                    Button("Sprawdź dostępność") {
                        Task {
                            isChecking = true
                            await manager.checkForUpdates()
                            isChecking = false
                            showingUpdateSheet = true
                        }
                    }
                    .disabled(isChecking)

                    if isChecking {
                        ProgressView().scaleEffect(0.5, anchor: .leading)
                    }

                    Spacer()

                    Button("Pobierz") {
                        Task {
                            await manager.downloadUpdate()
                        }
                    }
                    .disabled(manager.availableUpdate == nil)
                }
            }

            Divider()

            // Errors section
            VStack(alignment: .leading) {
                Text("Błędy programu")
                    .font(.title2.bold())
                HStack {
                    Button("Historia błędów") {
                        showingErrorHistory = true
                    }
                    Spacer()
                    Button("Wyślij raport") {
                        showingConfirmSheet = true
                    }
                }
            }

            Spacer()
        }
        .padding(30)
        .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity,
               minHeight: 300, idealHeight: 350, maxHeight: .infinity)
        .sheet(isPresented: $showingErrorHistory) {
            ErrorHistoryView()
        }
        .sheet(isPresented: $showingConfirmSheet) {
            ReportConfirmationView()
        }
        .sheet(isPresented: $showingUpdateSheet) {
            if let info = manager.availableUpdate {
                UpdateAvailableView(info: info)
            }
        }
    }
}

#if DEBUG
#Preview {
    ErrorUpdateContentView()
}
#endif
