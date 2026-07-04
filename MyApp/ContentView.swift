import SwiftUI
import Combine
import AppKit

// AppDelegate to configure the framework on launch
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        #if DEBUG
        ErrorUpdateManager.shared.configure(
            serverURL: URL(string: "https://example.com")! // <-- REPLACE
        )
        #endif
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

// ViewModel to manage the state of our view
class ContentViewModel: ObservableObject {
    @Published var updateInfo: UpdateInfo?
    @Published var isCheckingForUpdate = false
    
    let currentVersion = ErrorUpdateManager.shared.currentVersion ?? "N/A"
    
    func checkForUpdate() async {
        isCheckingForUpdate = true
        await ErrorUpdateManager.shared.checkForUpdates()
        isCheckingForUpdate = false
    }
}

struct ContentView: View {
    @StateObject private var viewModel = ContentViewModel()
    @State private var showingErrorHistory = false

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
                        Task { await viewModel.checkForUpdate() }
                    }
                        .disabled(viewModel.isCheckingForUpdate)
                    
                    if viewModel.isCheckingForUpdate {
                        ProgressView().scaleEffect(0.5, anchor: .leading)
                    }
                    
                    Spacer()
                    
                    Button("Pobierz") { /* Download action */ }
                        .disabled(viewModel.updateInfo == nil)
                }
            }
            
            Divider()

            // Errors Section
            VStack(alignment: .leading) {
                Text("Błędy programu")
                    .font(.title2.bold())
                
                HStack {
                    Button("Historia błędów") { showingErrorHistory = true }
                    Spacer()
                    Button("Wyślij raport") {
                        enum SampleError: Error, LocalizedError { case manualReport }
                        ErrorUpdateManager.shared.logError(SampleError.manualReport)
                    }
                }
            }
            
            Spacer() // Pushes content to the top
        }
        .padding(30)
        .frame(minWidth: 400, idealWidth: 450, maxWidth: .infinity, minHeight: 300, idealHeight: 350, maxHeight: .infinity)
        .sheet(isPresented: $showingErrorHistory) {
            if #available(macOS 11.0, *) {
                ErrorHistoryView()
            }
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
