import Testing
@testable import ErrorUpdate
import Foundation

// MARK: - Atrapa serwera raportów

/// Zapamiętuje wysłane raporty i odpowiada tak, jak każe `nextStatusCode`.
private final class ReportURLProtocol: URLProtocol {

    nonisolated(unsafe) private static var bodies: [Data] = []
    nonisolated(unsafe) private static var statusCode = 200
    private static let lock = NSLock()

    static func reset(statusCode: Int = 200) {
        lock.lock()
        bodies = []
        self.statusCode = statusCode
        lock.unlock()
    }

    static var wyslaneRaporty: [Data] {
        lock.lock(); defer { lock.unlock() }
        return bodies
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path.contains("report") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // httpBody bywa puste po przejściu przez URLSession — treść siedzi wtedy
        // w strumieniu, i tylko stamtąd da się ją odczytać.
        if let body = request.httpBody {
            Self.lock.lock(); Self.bodies.append(body); Self.lock.unlock()
        } else if let stream = request.httpBodyStream {
            stream.open()
            var dane = Data()
            var bufor = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let ile = stream.read(&bufor, maxLength: bufor.count)
                if ile <= 0 { break }
                dane.append(contentsOf: bufor[0..<ile])
            }
            stream.close()
            Self.lock.lock(); Self.bodies.append(dane); Self.lock.unlock()
        }

        Self.lock.lock()
        let kod = Self.statusCode
        Self.lock.unlock()

        let response = HTTPURLResponse(url: request.url!, statusCode: kod,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Testy

/// Wysyłka zaległych raportów na serwer.
///
/// Do 2026-08-10 **ani jednego testu**: `TestServer` obsługiwał wyłącznie
/// `version-check`, więc `sendPendingReports()` nie miał dokąd pójść, a cztery
/// wszczepienia frameworka w prawdziwe aplikacje tej ścieżki nie dotknęły.
/// Kolejka po nieudanej wysyłce była sprawdzona, udana — nie.
@MainActor
@Suite(.serialized) struct SendReportsTests {

    private func zrobMenedzera(magazyn: ReportStore) throws -> ErrorUpdateManager {
        let konfiguracja = URLSessionConfiguration.ephemeral
        konfiguracja.protocolClasses = [ReportURLProtocol.self]

        let menedzer = ErrorUpdateManager()
        menedzer.configure(
            ErrorUpdateConfig(serverURL: URL(string: "https://example.com")!,
                              allowUnsignedUpdates: true),
            session: URLSession(configuration: konfiguracja),
            userDefaults: UserDefaults(suiteName: "ErrorUpdateSend-\(UUID().uuidString)")!
        )
        // Własny magazyn w katalogu tymczasowym: domyślny jest wspólny dla
        // wszystkich suit, a te biegną równolegle. Musi to być **ta sama**
        // instancja, do której pisze test — dwa `ReportStore` na jednym katalogu
        // mają osobne pamięci podręczne i nie widzą swoich zapisów.
        menedzer.useReportStoreForTesting(magazyn)
        return menedzer
    }

    private func katalogTymczasowy() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("send-test-\(UUID().uuidString)", isDirectory: true)
    }

    // MARK: 1. Udana wysyłka opróżnia kolejkę

    @Test func udanaWysylka_opronzniaKolejkeIDocieraNaSerwer() async throws {
        ReportURLProtocol.reset(statusCode: 200)
        let katalog = katalogTymczasowy()
        defer { try? FileManager.default.removeItem(at: katalog) }

        let magazyn = try ReportStore(directory: katalog)
        magazyn.save(ErrorReport(errorMessage: "raport do wysłania"))
        _ = magazyn.fetchAll()                    // domknięcie zapisu
        let menedzer = try zrobMenedzera(magazyn: magazyn)
        #expect(menedzer.pendingReportsCount == 1, "Warunek wstępny: jeden raport w kolejce")

        await menedzer.sendPendingReports()

        #expect(menedzer.pendingReportsCount == 0,
                "Po przyjęciu przez serwer raport nie ma prawa zostać w kolejce")

        let wyslane = ReportURLProtocol.wyslaneRaporty
        #expect(wyslane.count == 1, "Serwer ma dostać dokładnie jeden raport")
        let tresc = String(data: wyslane.first ?? Data(), encoding: .utf8) ?? ""
        #expect(tresc.contains("raport do wysłania"),
                "Na serwer ma dolecieć treść raportu, nie pusty szkielet")
    }

    // MARK: 2. Odmowa serwera zostawia raport w kolejce

    /// Ta strona była już sprawdzona pomiarem (serwer bez endpointu), ale nie
    /// testem — a to ona decyduje, czy zgłoszenie użytkownika nie przepadnie.
    @Test func odmowaSerwera_zostawiaRaportWKolejce() async throws {
        ReportURLProtocol.reset(statusCode: 500)
        let katalog = katalogTymczasowy()
        defer { try? FileManager.default.removeItem(at: katalog) }

        let magazyn = try ReportStore(directory: katalog)
        magazyn.save(ErrorReport(errorMessage: "raport, który ma przeżyć"))
        _ = magazyn.fetchAll()
        let menedzer = try zrobMenedzera(magazyn: magazyn)

        await menedzer.sendPendingReports()

        #expect(menedzer.pendingReportsCount == 1,
                "Raport odrzucony przez serwer zostaje do kolejnej próby")
    }
}
