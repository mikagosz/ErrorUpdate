import Testing
@testable import ErrorUpdate
import Foundation

/// A downloaded package must disappear after a successful install.
///
/// Measured 2026-08-10 in a host app: after updating 1.1.0 → 1.1.1, the **whole 17 MB
/// file** was still sitting in `$TMPDIR/ErrorUpdate_download/<uuid>/`. The downloader
/// only cleaned up after a failure, and on success nobody took it away — and the system
/// only clears `$TMPDIR` on restart, so every further update piled on another package.
@Suite(.serialized) struct DownloadCleanupTests {

    /// This app's own folder inside the shared `ErrorUpdate_download`.
    private var root: URL { UpdateDownloader.downloadRoot }

    /// Reproduces what the downloader does: one directory per download, file inside.
    private func makeDownload(named name: String = "MyApp-1.1.1.zip") throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(name)
        try Data("package".utf8).write(to: file)
        return file
    }

    // MARK: 1. The package and its directory go after an install

    @Test func removeDownloadArtifacts_removesPackageAndDirectory() throws {
        let file = try makeDownload()
        let directory = file.deletingLastPathComponent()

        ErrorUpdateManager.removeDownloadArtifacts(of: file)

        #expect(FileManager.default.fileExists(atPath: file.path) == false,
                "The package must not survive a successful install")
        #expect(FileManager.default.fileExists(atPath: directory.path) == false,
                "The download directory goes as a whole too")
    }

    // MARK: 2. The shared directory only goes once it is empty

    @Test func removeDownloadArtifacts_keepsRootWhileAnotherDownloadRuns() throws {
        let first = try makeDownload()
        let second = try makeDownload(named: "MyApp-1.1.2.zip")
        defer { try? FileManager.default.removeItem(at: second.deletingLastPathComponent()) }

        ErrorUpdateManager.removeDownloadArtifacts(of: first)

        #expect(FileManager.default.fileExists(atPath: second.path),
                "Cleaning up one download must not take another one that is still running")
        #expect(FileManager.default.fileExists(atPath: root.path),
                "The shared directory stays as long as anything is in it")
    }

    // MARK: 3. It will not touch a path that is not ours

    /// The method is handed a URL from outside, so it has to refuse to delete anything
    /// that does not sit directly inside our own `ErrorUpdate_download`.
    @Test func removeDownloadArtifacts_refusesToDeleteForeignDirectory() throws {
        let foreign = FileManager.default.temporaryDirectory
            .appendingPathComponent("foreign-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let file = foreign.appendingPathComponent("important.txt")
        try Data("do not touch".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: foreign) }

        ErrorUpdateManager.removeDownloadArtifacts(of: file)

        #expect(FileManager.default.fileExists(atPath: file.path),
                "Cleaning up after ourselves must not be aimable at someone else's directory")
    }
}
