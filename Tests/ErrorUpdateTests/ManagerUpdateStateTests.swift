import Testing
@testable import ErrorUpdate
import Foundation

// MARK: - Atrapa manifestu

/// Serwuje jeden ustalony manifest, niezależnie od adresu.
private final class StateManifestURLProtocol: URLProtocol {

    nonisolated(unsafe) private static var manifest = Data()
    private static let lock = NSLock()

    static func setManifest(latestVersion: String, available: Bool = true) {
        let json = """
        {
          "latestVersion": "\(latestVersion)",
          "available": \(available),
          "downloadURL": "https://example.com/update.zip",
          "sha256": "\(String(repeating: "0", count: 64))",
          "signature": "",
          "mandatory": false
        }
        """
        lock.lock()
        manifest = Data(json.utf8)
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        let data = Self.manifest
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Testy

/// Stan `availableUpdate` **w menedżerze**.
///
/// Luka zauważona 2026-08-10: [[Problem-automatyczne-sprawdzanie-kasuje-wykryta-aktualizacje]]
/// naprawił bezwarunkowe `availableUpdate = info` w menedżerze, ale test regresyjny
/// powstał piętro niżej — sprawdzał wyłącznie, że **checker** zwraca `.notChecked`.
/// Przywrócenie dawnego przypisania w menedżerze przechodziło na zielono.
///
/// Testy chodzą po **własnej instancji** menedżera i własnych `UserDefaults`,
/// bo singleton i klucze w `.standard` są wspólne dla wszystkich suit, a te biegną
/// równolegle.
@MainActor
@Suite(.serialized) struct ManagerUpdateStateTests {

    private func zrobMenedzera() -> (ErrorUpdateManager, UserDefaults) {
        let konfiguracjaSesji = URLSessionConfiguration.ephemeral
        konfiguracjaSesji.protocolClasses = [StateManifestURLProtocol.self]
        let sesja = URLSession(configuration: konfiguracjaSesji)

        let defaults = UserDefaults(suiteName: "ErrorUpdateManagerState-\(UUID().uuidString)")!
        let menedzer = ErrorUpdateManager()
        menedzer.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                              allowUnsignedUpdates: true),
            session: sesja,
            userDefaults: defaults
        )
        return (menedzer, defaults)
    }

    // MARK: 1. Znaleziona aktualizacja przeżywa sprawdzenie okresowe

    /// Dokładnie sekwencja z pierwotnego zgłoszenia: użytkownik klika „sprawdź",
    /// widzi wersję, a zaraz potem rusza sprawdzanie okresowe przy świeżym cache.
    @Test func znalezionaAktualizacja_przezywaSprawdzenieOkresowe() async {
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let (menedzer, _) = zrobMenedzera()

        await menedzer.checkForUpdates(force: true)
        #expect(menedzer.availableUpdate?.latestVersion == "2.0.0",
                "Warunek wstępny: wymuszone sprawdzenie ma znaleźć wersję")

        // Cache jest świeży po poprzednim sprawdzeniu, więc checker odpowie
        // „nie sprawdzałem" — i to nie jest odpowiedź „nie ma aktualizacji".
        await menedzer.checkForUpdates(force: false)

        #expect(menedzer.availableUpdate?.latestVersion == "2.0.0",
                "Sprawdzenie okresowe nie może skasować znalezionej aktualizacji")
    }

    // MARK: 2. Wycofane wydanie nadal gasi monit

    /// Druga strona tej samej naprawy: „nie sprawdzałem" zostawia stan w spokoju,
    /// ale odpowiedź serwera „nie oferuję tej wersji" **ma** go wyczyścić.
    /// Bez tego wersja z `if let` byłaby wystarczająca, a nie jest.
    @Test func wycofaneWydanie_gasiMonit() async {
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0")
        let (menedzer, defaults) = zrobMenedzera()

        await menedzer.checkForUpdates(force: true)
        #expect(menedzer.availableUpdate != nil, "Warunek wstępny: monit jest")

        // Serwer wycofuje wydanie; cache czyścimy, żeby pytanie naprawdę poszło.
        StateManifestURLProtocol.setManifest(latestVersion: "2.0.0", available: false)
        defaults.removeObject(forKey: "ErrorUpdate_LastUpdateCheckDate")

        await menedzer.checkForUpdates(force: false)

        #expect(menedzer.availableUpdate == nil,
                "Wycofane wydanie ma zgasić monit, a nie zostać na ekranie")
    }
}
