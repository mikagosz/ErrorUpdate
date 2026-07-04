//
//  SampleContentView.swift
//  ErrorUpdate Example
//
//  Created by Gemini on 2026-07-04.
//

import SwiftUI
import ErrorUpdate

struct SampleContentView: View {
    
    enum SampleError: Error, LocalizedError {
        case fileNotFound
        var errorDescription: String? { "The requested file could not be found." }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("ErrorUpdate Framework Demo")
                .font(.title)
            
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
                ErrorUpdateManager.shared.checkForUpdates()
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
