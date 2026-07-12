//
//  main.swift
//  errorupdate-tool
//
//  Command-line helper for the ErrorUpdate framework:
//    keygen  — generates an Ed25519 key pair for signing updates
//    release — computes SHA-256 + signature of an update file and
//              writes the version-check JSON manifest for the server
//

import Foundation
import CryptoKit

// MARK: - Helpers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("Error: " + message + "\n").utf8))
    exit(1)
}

func value(for flag: String) -> String? {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
    return args[index + 1]
}

func hasFlag(_ flag: String) -> Bool {
    CommandLine.arguments.contains(flag)
}

func printUsage() {
    print("""
    errorupdate-tool — release helper for the ErrorUpdate framework

    USAGE:
      errorupdate-tool keygen [--out <directory>]
          Generates an Ed25519 key pair:
            errorupdate_private_key.txt  (base64, KEEP SECRET, do not commit)
            errorupdate_public_key.txt   (base64, embed in your app)

      errorupdate-tool release --file <App.zip|App.dmg> --version <X.Y.Z>
                               --url <download URL> [--key <private key file>]
                               [--notes <release notes>] [--mandatory]
                               [--out <manifest path>]
          Computes the SHA-256 checksum (and Ed25519 signature when --key is
          given) of the update file and writes the version-check JSON manifest.
          Default --out: ./version-check

    EXAMPLE:
      errorupdate-tool keygen --out keys
      errorupdate-tool release \\
          --file MyApp-1.2.0.zip --version 1.2.0 \\
          --url https://myserver.com/downloads/MyApp-1.2.0.zip \\
          --key keys/errorupdate_private_key.txt \\
          --notes "Poprawki błędów" --out www/api/error-update/version-check
    """)
}

func sha256Hex(of url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

// MARK: - Commands

func runKeygen() {
    let outDir = URL(fileURLWithPath: value(for: "--out") ?? ".")
    try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let privateKeyURL = outDir.appendingPathComponent("errorupdate_private_key.txt")
    let publicKeyURL = outDir.appendingPathComponent("errorupdate_public_key.txt")

    if FileManager.default.fileExists(atPath: privateKeyURL.path) {
        fail("\(privateKeyURL.path) already exists — refusing to overwrite an existing private key.")
    }

    let key = Curve25519.Signing.PrivateKey()
    let privateBase64 = key.rawRepresentation.base64EncodedString()
    let publicBase64 = key.publicKey.rawRepresentation.base64EncodedString()

    do {
        try privateBase64.write(to: privateKeyURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateKeyURL.path)
        try publicBase64.write(to: publicKeyURL, atomically: true, encoding: .utf8)
    } catch {
        fail("could not write key files: \(error.localizedDescription)")
    }

    print("""
    Wygenerowano parę kluczy Ed25519:
      klucz prywatny: \(privateKeyURL.path)   <-- TRZYMAJ W TAJEMNICY, nie commituj
      klucz publiczny: \(publicKeyURL.path)

    W aplikacji skonfiguruj klucz publiczny tak:

        ErrorUpdateConfig(
            serverURL: URL(string: "https://twoj-serwer.com")!,
            publicKey: Data(base64Encoded: "\(publicBase64)")!
        )
    """)
}

func runRelease() {
    guard let filePath = value(for: "--file") else { fail("--file is required") }
    guard let version = value(for: "--version") else { fail("--version is required") }
    guard let downloadURL = value(for: "--url") else { fail("--url is required") }

    let fileURL = URL(fileURLWithPath: filePath)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
        fail("file not found: \(fileURL.path)")
    }

    let sha256: String
    do {
        sha256 = try sha256Hex(of: fileURL)
    } catch {
        fail("could not read \(fileURL.path): \(error.localizedDescription)")
    }

    var signature = ""
    if let keyPath = value(for: "--key") {
        guard let keyBase64 = try? String(contentsOf: URL(fileURLWithPath: keyPath), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let keyData = Data(base64Encoded: keyBase64),
              let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
            fail("could not load private key from \(keyPath)")
        }
        guard let fileData = try? Data(contentsOf: fileURL),
              let sig = try? key.signature(for: fileData) else {
            fail("could not sign \(fileURL.path)")
        }
        signature = sig.base64EncodedString()
    }

    let manifest: [String: Any] = [
        "latestVersion": version,
        "available": true,
        "releaseNotes": value(for: "--notes") ?? "",
        "downloadURL": downloadURL,
        "sha256": sha256,
        "signature": signature,
        "mandatory": hasFlag("--mandatory"),
    ]

    let outPath = value(for: "--out") ?? "version-check"
    let outURL = URL(fileURLWithPath: outPath)
    try? FileManager.default.createDirectory(at: outURL.deletingLastPathComponent(), withIntermediateDirectories: true)

    do {
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outURL)
    } catch {
        fail("could not write manifest: \(error.localizedDescription)")
    }

    print("""
    Manifest zapisany: \(outURL.path)
      wersja:  \(version)
      sha256:  \(sha256)
      podpis:  \(signature.isEmpty ? "(brak — użyj --key aby podpisać)" : "Ed25519 OK")
    """)
}

// MARK: - Entry point

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    printUsage()
    exit(1)
}

switch arguments[1] {
case "keygen":
    runKeygen()
case "release":
    runRelease()
case "help", "--help", "-h":
    printUsage()
default:
    printUsage()
    fail("unknown command: \(arguments[1])")
}
