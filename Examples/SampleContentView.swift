//
//  SampleContentView.swift
//  ErrorUpdate Example
//

import SwiftUI
import ErrorUpdate

struct SampleContentView: View {

    enum SampleError: Error, LocalizedError {
        case fileNotFound
        var errorDescription: String? { "The requested file could not be found." }
    }

    @ObservedObject private var manager = ErrorUpdateManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Text("ErrorUpdate Framework Demo")
                .font(.title)

            Text("Pending reports: \(manager.pendingReportsCount)")
                .foregroundStyle(.secondary)

            Button("Log a Swift Error") {
                ErrorUpdateManager.shared.logError(SampleError.fileNotFound, context: ["userAction": "loadFile"])
            }

            Button("Trigger a Native Exception (Crash)") {
                let array = NSArray()
                _ = array.object(at: 99) // This will cause an NSException
            }

            Button("Trigger a Fatal Signal (Crash)") {
                var nullPointer: UnsafeMutablePointer<Int>? = nil
                nullPointer!.pointee = 42 // This will cause a SIGSEGV
            }

            Button("Check for Updates Manually") {
                Task { await ErrorUpdateManager.shared.checkForUpdates() }
            }

            if let update = manager.availableUpdate {
                Text("Update available: \(update.latestVersion)")
                Button("Download & Install") {
                    Task {
                        if await ErrorUpdateManager.shared.downloadUpdate() != nil {
                            await ErrorUpdateManager.shared.installUpdate()
                        }
                    }
                }
            }
        }
        .padding(40)
        .frame(minWidth: 400, minHeight: 300)
    }
}

struct SampleContentView_Previews: PreviewProvider {
    static var previews: some View {
        SampleContentView()
    }
}
