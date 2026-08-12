import Testing
import Foundation

// The repository is English: README, API, doc comments, test names, failure messages.
// The demo app is deliberately bilingual, and that is a feature — see its language
// switch — so `DemoApp/` and `TestServer/` are out of scope here.
//
// This is enforced by a test rather than written down somewhere, because writing it
// down was already tried. A commit dated 2026-08-09 ("English throughout") left
// `Sources/` and `Tests/` with zero Polish characters; by 2026-08-12 there were 139
// lines of Polish comments across 8 files, and the two worst offenders were files
// created *after* that commit. Five releases went out in between and none of them
// noticed. A rule nobody executes is not a rule.
//
// Deliberate limitation, stated so nobody mistakes a green test for proof of English:
// this catches Polish *diacritics*, not Polish. A sentence written without them slips
// through. Widening it to word lists would trade a real signal for false positives on
// identifiers, so the narrow check stays.
//
// This file contains no Polish characters of its own — the alphabet below is built
// from Unicode scalars on purpose, so the scanner cannot flag itself and no path
// needs to be excluded. An exclusion list is a hole; not being detectable is not.

/// Polish-specific letters, spelled as scalars so this source file stays clean.
private let polishLetters: Set<Character> = {
    let scalars: [UInt32] = [
        0x0105, 0x0107, 0x0119, 0x0142, 0x0144, 0x00F3, 0x015B, 0x017A, 0x017C,  // lower
        0x0104, 0x0106, 0x0118, 0x0141, 0x0143, 0x00D3, 0x015A, 0x0179, 0x017B,  // upper
    ]
    return Set(scalars.compactMap(Unicode.Scalar.init).map(Character.init))
}()

/// Repository root, derived from this file's location: `<root>/Tests/ErrorUpdateTests/`.
private var repositoryRoot: URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // ErrorUpdateTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // <root>
}

private func swiftFiles(under directory: String) -> [URL] {
    let base = repositoryRoot.appendingPathComponent(directory, isDirectory: true)
    guard let walker = FileManager.default.enumerator(
        at: base,
        includingPropertiesForKeys: nil
    ) else { return [] }

    return walker
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" }
        .sorted { $0.path < $1.path }
}

/// Lines carrying Polish letters, as "path:line" for a message you can act on.
private func polishLines(in file: URL) -> [String] {
    guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
    let name = file.path.replacingOccurrences(of: repositoryRoot.path + "/", with: "")

    return text.split(separator: "\n", omittingEmptySubsequences: false)
        .enumerated()
        .filter { $0.element.contains(where: polishLetters.contains) }
        .map { "\(name):\($0.offset + 1)" }
}

@Suite struct RepositoryLanguageTests {

    @Test func libraryAndTestsAreEnglish() throws {
        let offenders = (swiftFiles(under: "Sources") + swiftFiles(under: "Tests"))
            .flatMap(polishLines)

        #expect(
            offenders.isEmpty,
            """
            \(offenders.count) line(s) carry Polish characters. The library and its \
            tests are English; only the demo app is bilingual.
            \(offenders.joined(separator: "\n"))
            """
        )
    }

    /// Guards the scanner itself: a green result must mean "nothing found", never
    /// "nothing looked at". Without this, a broken path would read as success.
    @Test func scannerActuallyReadsTheRepository() throws {
        #expect(swiftFiles(under: "Sources").count > 5)
        #expect(swiftFiles(under: "Tests").count > 5)

        let probe = "wersja niezgodna z pakietem"   // no diacritics: must NOT match
        #expect(!probe.contains(where: polishLetters.contains))

        let scalar = try #require(Unicode.Scalar(0x0142))   // the letter L with stroke
        #expect(polishLetters.contains(Character(scalar)))
    }
}
