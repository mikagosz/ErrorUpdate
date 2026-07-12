import SwiftUI
import AppKit
import ErrorUpdate

// AppDelegate to configure the framework on launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ErrorUpdateManager.shared.configure(
            ErrorUpdateConfig(
                // Serwer testowy: TestServer/prepare.sh + TestServer/start.sh
                // W produkcji podmień na własny adres HTTPS.
                serverURL: URL(string: "http://127.0.0.1:8000")!,
                // Klucz publiczny Ed25519 z keys/errorupdate_public_key.txt
                publicKey: Data(base64Encoded: "7//lOtdipV7KeuhNZ/wksRLeE9mgtJmMd4oXGfxhaME=") ?? Data()
            )
        )
        ErrorUpdateManager.shared.setupCrashHandling()
    }
}

@main
struct MyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("ErrorUpdate", id: "main") {
            ContentView()
        }
        .windowToolbarStyle(.unified)
    }
}

struct ContentView: View {
    @ObservedObject private var manager = ErrorUpdateManager.shared
    @State private var isCheckingForUpdate = false
    @State private var isDownloading = false
    @State private var showingErrorHistory = false

    private var currentVersion: String { manager.currentVersion ?? "N/A" }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Header
            HStack(spacing: 12) {
                Image("logo do okna")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 36, height: 36)
                    .foregroundStyle(.secondary)

                Text("ErrorUpdate")
                    .font(.system(size: 32, weight: .bold))
            }
            .padding(.bottom, 10)

            // Updates Section
            VStack(alignment: .leading) {
                Text("Aktualizacje")
                    .font(.title2.bold())

                HStack {
                    Button("Sprawdź dostępność") {
                        Task {
                            isCheckingForUpdate = true
                            await manager.checkForUpdates()
                            isCheckingForUpdate = false
                        }
                    }
                    .disabled(isCheckingForUpdate)

                    if isCheckingForUpdate {
                        ProgressView().scaleEffect(0.5, anchor: .leading)
                    }

                    Spacer()

                    if let update = manager.availableUpdate {
                        Text("Dostępna wersja \(update.latestVersion)")
                            .foregroundStyle(.secondary)
                    }

                    Button(isDownloading ? "Pobieranie…" : "Pobierz") {
                        Task {
                            isDownloading = true
                            await manager.downloadUpdate()
                            isDownloading = false
                        }
                    }
                    .disabled(manager.availableUpdate == nil || isDownloading)
                }
            }

            Divider()

            // Errors Section
            VStack(alignment: .leading) {
                Text("Błędy programu")
                    .font(.title2.bold())

                HStack {
                    Button("Historia błędów") { showingErrorHistory = true }

                    if manager.pendingReportsCount > 0 {
                        Text("\(manager.pendingReportsCount)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.red.opacity(0.8)))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button("Zgłoś przykładowy błąd") {
                        enum SampleError: Error, LocalizedError {
                            case manualReport
                            var errorDescription: String? { "Przykładowy błąd zgłoszony ręcznie" }
                        }
                        ErrorUpdateManager.shared.logError(SampleError.manualReport)
                    }
                }
            }

            Spacer() // Pushes content to the top
        }
        .padding(30)
        .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity, minHeight: 300, idealHeight: 350, maxHeight: .infinity)
        .sheet(isPresented: $showingErrorHistory) {
            ErrorHistoryView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Image("logo do okna")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 18, height: 18)
            }
        }
    }
}

#if DEBUG
#Preview {
    ContentView()
}
#endif
