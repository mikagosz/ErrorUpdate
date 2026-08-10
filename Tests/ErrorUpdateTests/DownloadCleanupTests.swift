import Testing
@testable import ErrorUpdate
import Foundation

/// Pobrana paczka ma zniknąć po udanej instalacji.
///
/// Zmierzone 2026-08-10 w MI: po aktualizacji 1.1.0 → 1.1.1 w
/// `$TMPDIR/ErrorUpdate_download/<uuid>/` został **cały plik 17 MB**. Downloader
/// sprzątał wyłącznie po błędzie, a po sukcesie nikt tego nie zabierał — a `$TMPDIR`
/// system czyści dopiero po restarcie, więc każda kolejna aktualizacja dokłada
/// następną paczkę.
@Suite(.serialized) struct DownloadCleanupTests {

    private var korzen: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ErrorUpdate_download")
    }

    /// Odtwarza to, co robi downloader: katalog per pobranie, plik w środku.
    private func zrobPobranie(nazwa: String = "MyApp-1.1.1.zip") throws -> URL {
        let katalog = korzen.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: katalog, withIntermediateDirectories: true)
        let plik = katalog.appendingPathComponent(nazwa)
        try Data("paczka".utf8).write(to: plik)
        return plik
    }

    // MARK: 1. Po instalacji znika paczka i jej katalog

    @Test func removeDownloadArtifacts_usuwaPaczkeIKatalog() throws {
        let plik = try zrobPobranie()
        let katalog = plik.deletingLastPathComponent()

        ErrorUpdateManager.removeDownloadArtifacts(of: plik)

        #expect(FileManager.default.fileExists(atPath: plik.path) == false,
                "Paczka po udanej instalacji nie ma prawa zostać")
        #expect(FileManager.default.fileExists(atPath: katalog.path) == false,
                "Katalog pobrania też idzie w całości")
    }

    // MARK: 2. Wspólny katalog znika dopiero, gdy jest pusty

    @Test func removeDownloadArtifacts_zostawiaKorzenGdyTrwaInnePobranie() throws {
        let pierwsze = try zrobPobranie()
        let drugie = try zrobPobranie(nazwa: "MyApp-1.1.2.zip")
        defer { try? FileManager.default.removeItem(at: drugie.deletingLastPathComponent()) }

        ErrorUpdateManager.removeDownloadArtifacts(of: pierwsze)

        #expect(FileManager.default.fileExists(atPath: drugie.path),
                "Sprzątanie jednego pobrania nie może zabrać drugiego, trwającego")
        #expect(FileManager.default.fileExists(atPath: korzen.path),
                "Wspólny katalog zostaje, dopóki coś w nim jest")
    }

    // MARK: 3. Cudzej ścieżki nie tyka

    /// Metoda dostaje URL z zewnątrz, więc musi odmówić kasowania czegokolwiek,
    /// co nie leży bezpośrednio w naszym `ErrorUpdate_download`.
    @Test func removeDownloadArtifacts_odmawiaKasowaniaObcegoKatalogu() throws {
        let obcy = FileManager.default.temporaryDirectory
            .appendingPathComponent("cudze-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: obcy, withIntermediateDirectories: true)
        let plik = obcy.appendingPathComponent("wazne.txt")
        try Data("nie ruszać".utf8).write(to: plik)
        defer { try? FileManager.default.removeItem(at: obcy) }

        ErrorUpdateManager.removeDownloadArtifacts(of: plik)

        #expect(FileManager.default.fileExists(atPath: plik.path),
                "Sprzątanie po sobie nie może dać się nakierować na cudzy katalog")
    }
}
