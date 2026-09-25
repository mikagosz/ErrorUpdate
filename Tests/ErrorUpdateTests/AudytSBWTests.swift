import Testing
@testable import ErrorUpdate
import Foundation
import Darwin

/// Fixes after the SBW audit of 2026-09-24 that have no natural home elsewhere.
@Suite(.serialized) struct AudytSBWTests {

    private func decode(_ address: String) throws -> UpdateInfo {
        let json = #"{"latestVersion":"2.0","downloadURL":"\#(address)","sha256":"00"}"#
        return try JSONDecoder().decode(UpdateInfo.self, from: Data(json.utf8))
    }

    /// A host that opens `downloadURL` itself never passes the downloader's check.
    @Test(arguments: ["file:///etc/passwd", "smb://server/share/App.zip",
                      "http://example.com/App.zip", "obsidian://open?vault=x"])
    func manifestWithUnsafeDownloadURL_isRejected(_ address: String) {
        #expect(throws: DecodingError.self) { try decode(address) }
    }

    @Test(arguments: ["https://example.com/App.zip", "http://127.0.0.1:8000/App.zip"])
    func manifestWithSafeDownloadURL_decodes(_ address: String) throws {
        #expect(try decode(address).downloadURL.absoluteString == address)
    }

    /// A stack overflow raises SIGSEGV on the stack that just ran out; without an
    /// alternate stack the handler cannot run and no crash file is written.
    @MainActor @Test func signalHandlers_runOnAlternateStack() {
        SignalHandler.register()
        defer { SignalHandler.unregister() }

        var current = stack_t()
        #expect(sigaltstack(nil, &current) == 0)
        #expect(current.ss_sp != nil, "No alternate signal stack is installed")
        #expect(current.ss_size >= 64 * 1024)

        var action = sigaction()
        #expect(sigaction(SIGSEGV, nil, &action) == 0)
        #expect(action.sa_flags & SA_ONSTACK != 0, "SIGSEGV must be handled on the alternate stack")
    }
}
