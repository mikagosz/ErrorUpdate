import Testing
@testable import ErrorUpdate
import Foundation

@Suite struct URLSecurityTests {

    @Test func httpsIsAccepted() {
        #expect(URLSecurity.isAcceptable(URL(string: "https://example.com/api")!))
        #expect(URLSecurity.isAcceptable(URL(string: "HTTPS://EXAMPLE.COM/api")!))
    }

    @Test func plainHTTPIsRejected() {
        #expect(!URLSecurity.isAcceptable(URL(string: "http://example.com/api")!))
        #expect(!URLSecurity.isAcceptable(URL(string: "http://192.168.1.10/api")!))
        // Nazwa hosta tylko zawierająca "localhost" to nie jest loopback.
        #expect(!URLSecurity.isAcceptable(URL(string: "http://localhost.evil.com/api")!))
        #expect(!URLSecurity.isAcceptable(URL(string: "http://notlocalhost/api")!))
    }

    @Test func loopbackOverHTTPIsAccepted() {
        // Serwer testowy z repozytorium i aplikacja demo stoją właśnie tutaj.
        #expect(URLSecurity.isAcceptable(URL(string: "http://127.0.0.1:8000")!))
        #expect(URLSecurity.isAcceptable(URL(string: "http://localhost:8000/api")!))
        #expect(URLSecurity.isAcceptable(URL(string: "http://[::1]:8000")!))
        #expect(URLSecurity.isAcceptable(URL(string: "http://app.localhost:8000")!))
    }

    @Test func otherSchemesAreRejected() {
        #expect(!URLSecurity.isAcceptable(URL(string: "ftp://example.com/update.zip")!))
        #expect(!URLSecurity.isAcceptable(URL(fileURLWithPath: "/tmp/update.zip")))
    }
}
