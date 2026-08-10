import SwiftUI
import AppKit
import ErrorUpdate

// AppDelegate to configure the framework on launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        ErrorUpdateManager.shared.configure(
            ErrorUpdateConfig(
                // Test server: TestServer/prepare.sh + TestServer/start.sh
                // In production, point this at your own HTTPS address.
                serverURL: URL(string: "http://127.0.0.1:8000")!,
                // Ed25519 public key from keys/errorupdate_public_key.txt
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
    @State private var loc = Localization()
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
                Text(loc.t("Aktualizacje", "Updates"))
                    .font(.title2.bold())

                HStack {
                    Button(loc.t("Sprawdź dostępność", "Check for updates")) {
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
                        Text(loc.t("Dostępna wersja \(update.latestVersion)", "Version \(update.latestVersion) available"))
                            .foregroundStyle(.secondary)
                    }

                    Button(isDownloading ? loc.t("Pobieranie…", "Downloading…") : loc.t("Pobierz", "Download")) {
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
                Text(loc.t("Błędy programu", "Errors"))
                    .font(.title2.bold())

                HStack {
                    Button(loc.t("Historia błędów", "Error history")) { showingErrorHistory = true }

                    if manager.pendingReportsCount > 0 {
                        Text("\(manager.pendingReportsCount)")
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.red.opacity(0.8)))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button(loc.t("Zgłoś przykładowy błąd", "Report a sample error")) {
                        // Reports travel to a server and may be read by someone
                        // who does not share the app's UI language, so this one
                        // string stays English regardless of the picker.
                        enum SampleError: Error, LocalizedError {
                            case manualReport
                            var errorDescription: String? { "Sample error, reported by hand" }
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
            ErrorHistoryView(loc: loc)
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Picker("", selection: $loc.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .help(loc.t("Język interfejsu", "Interface language"))

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
