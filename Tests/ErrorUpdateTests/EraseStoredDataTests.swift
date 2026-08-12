import Testing
@testable import ErrorUpdate
import Foundation

/// Framework pisze do katalogu użytkownika, więc musi umieć to zabrać z powrotem.
/// Bez tego raporty ze śladami stosu (ścieżki `/Users/<nazwa>/`, dane sprzętu)
/// zostają na dysku długo po usunięciu biblioteki z projektu — zmierzone
/// 2026-08-10: 56 KB w jednej aplikacji, 16 KB w drugiej.
///
/// Uwaga na kształt tych testów: `ErrorUpdateManager.shared` i katalog
/// `Application Support/<bundle id>/reports` są **wspólne dla wszystkich suit**,
/// a te biegną równolegle. Asercja „katalog jest pusty po skasowaniu" była przez
/// to chwiejna — inna suita dopisywała raport w trakcie. Dlatego sprzątanie
/// katalogu sprawdzamy na własnym, tymczasowym `ReportStore`, a przez singleton
/// tylko to, co jest wyłącznie nasze: pliki crashu i klucze z prefiksem.
@MainActor
@Suite(.serialized) struct EraseStoredDataTests {

    // MARK: 1. Magazyn raportów czyści swój katalog

    @Test func reportStore_eraseAll_removesEveryReport() throws {
        let katalog = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: katalog)
        defer { try? FileManager.default.removeItem(at: katalog) }

        for i in 0..<3 {
            store.save(ErrorReport(errorMessage: "błąd numer \(i)"))
        }
        _ = store.fetchAll()                       // domknięcie zapisów: fetchAll idzie tą samą kolejką
        #expect(store.fetchAll().count == 3)

        try store.eraseAll()

        #expect(store.fetchAll().isEmpty, "Po wyczyszczeniu magazyn ma być pusty")
        let pliki = try FileManager.default.contentsOfDirectory(atPath: katalog.path)
        #expect(pliki.isEmpty, "Na dysku nie może zostać żaden raport")
    }

    // MARK: 2. Magazyn zostaje zdatny do użytku

    @Test func reportStore_eraseAll_leavesStoreUsable() throws {
        let katalog = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: katalog)
        defer { try? FileManager.default.removeItem(at: katalog) }

        store.save(ErrorReport(errorMessage: "pierwszy"))
        _ = store.fetchAll()
        try store.eraseAll()

        store.save(ErrorReport(errorMessage: "po wyczyszczeniu"))
        #expect(store.fetchAll().count == 1, "Raportowanie ma działać dalej po wyczyszczeniu")
    }

    // MARK: 3. Kasowanie nie wyprzedza zapisu w locie

    /// `save(_:)` pisze asynchronicznie. Kasowanie poza kolejką magazynu potrafiło
    /// wyprzedzić trwający zapis i raport wracał tuż po usunięciu.
    @Test func reportStore_eraseAll_doesNotLoseRaceWithPendingSave() throws {
        let katalog = FileManager.default.temporaryDirectory
            .appendingPathComponent("erase-test-\(UUID().uuidString)", isDirectory: true)
        let store = try ReportStore(directory: katalog)
        defer { try? FileManager.default.removeItem(at: katalog) }

        for i in 0..<20 {
            store.save(ErrorReport(errorMessage: "zapis w locie \(i)"))
        }
        try store.eraseAll()                       // wchodzi na tę samą kolejkę, więc czeka na zapisy

        #expect(store.fetchAll().isEmpty, "Zapis rozpoczęty przed kasowaniem nie może go przeżyć")
    }

    // MARK: 4. Pliki crashu znikają

    @Test func eraseAllStoredData_removesCrashFiles() throws {
        let manager = ErrorUpdateManager.shared
        let crashURL = CrashCatcher.crashReportURL()
        let quarantine = crashURL.appendingPathExtension("unreadable")

        try Data("signal\n11\n".utf8).write(to: crashURL)
        try Data("anything\n".utf8).write(to: quarantine)

        manager.eraseAllStoredData()

        #expect(FileManager.default.fileExists(atPath: crashURL.path) == false)
        #expect(FileManager.default.fileExists(atPath: quarantine.path) == false)
    }

    // MARK: 5. Zmiata wszystkie klucze z prefiksem, także przyszłe

    @Test func eraseAllStoredData_sweepsPrefixedDefaults() {
        let manager = ErrorUpdateManager.shared
        let defaults = UserDefaults.standard

        defaults.set("9.9.9", forKey: SkippedVersionStore.defaultsKey)
        defaults.set("8.8.8", forKey: InstalledVersionStore.expectedVersionKey)
        defaults.set("klucz z przyszłości", forKey: "ErrorUpdate_KluczDodanyPozniej")
        defaults.set("nie ruszać", forKey: "CudzeUstawienie_NieNasze")

        manager.eraseAllStoredData()

        #expect(defaults.string(forKey: SkippedVersionStore.defaultsKey) == nil)
        #expect(defaults.string(forKey: InstalledVersionStore.expectedVersionKey) == nil)
        #expect(defaults.string(forKey: "ErrorUpdate_KluczDodanyPozniej") == nil,
                "Sprzątanie po prefiksie ma objąć klucze dodane po napisaniu tej metody")
        #expect(defaults.string(forKey: "CudzeUstawienie_NieNasze") == "nie ruszać",
                "Cudzych ustawień framework nie dotyka")

        defaults.removeObject(forKey: "CudzeUstawienie_NieNasze")
    }

    // MARK: 6. Sprzątanie zatrzymuje harmonogram

    /// Zmierzone na żywo w NK 2026-08-10: po kliknięciu „Usuń dane diagnostyczne"
    /// katalog raportów był pusty, ale `ErrorUpdate_LastUpdateCheckDate` **wrócił**
    /// minutę później — harmonogram chodził dalej i zapisał go z powrotem. Klucze
    /// znikały, a potem cicho się odtwarzały; obietnica z dokumentacji była prawdziwa
    /// przez kilkadziesiąt minut, nie na stałe.
    @Test func eraseAllStoredData_stopsPeriodicCheck() {
        let manager = ErrorUpdateManager.shared
        // Port 9 (discard) odrzuca połączenie od razu — natychmiastowy tik
        // z `start()` nie ma dokąd pójść i nic nie zapisze.
        manager.configure(serverURL: URL(string: "http://127.0.0.1:9")!)
        manager.startPeriodicUpdateCheck(interval: 3600)
        #expect(manager.isPeriodicUpdateCheckRunning, "Warunek wstępny: harmonogram chodzi")

        manager.eraseAllStoredData()

        #expect(manager.isPeriodicUpdateCheckRunning == false,
                "Po sprzątaniu harmonogram nie może odtworzyć skasowanych kluczy")
    }
}
