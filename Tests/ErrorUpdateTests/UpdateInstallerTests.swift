import Testing
@testable import ErrorUpdate
import Foundation

/// Checks that the installer refuses updates that are not the same application,
/// and not from the same signer, as the app being replaced.
@Suite struct UpdateInstallerTests {

    // MARK: - Fixtures

    /// Builds a minimal `.app` and returns its URL.
    /// - Parameter signingIdentity: `-` (default) signs ad-hoc; pass a certificate
    ///   fingerprint to produce a bundle with a stable designated requirement.
    private func makeApp(
        named name: String,
        bundleID: String,
        in directory: URL,
        signingIdentity: String = "-"
    ) throws -> URL {
        let appURL = directory.appendingPathComponent("\(name).app")
        let macOSDir = appURL.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOSDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleName": name,
            "CFBundleExecutable": name,
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: appURL.appendingPathComponent("Contents/Info.plist"))

        let executable = macOSDir.appendingPathComponent(name)
        try "#!/bin/sh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", signingIdentity, appURL.path])
        return appURL
    }

    /// Packs a bundle into a `.zip` the installer can consume.
    private func zip(_ appURL: URL, to zipURL: URL) throws {
        try run("/usr/bin/ditto", ["-c", "-k", "--keepParent", appURL.path, zipURL.path])
    }

    /// Packs a bundle into a `.dmg` the installer can consume.
    private func dmg(_ appURL: URL, to dmgURL: URL) throws {
        let stagingDir = dmgURL.deletingLastPathComponent().appendingPathComponent("dmg-staging")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: appURL, to: stagingDir.appendingPathComponent(appURL.lastPathComponent))

        try run("/usr/bin/hdiutil", [
            "create", dmgURL.path,
            "-volname", "ErrorUpdateTest",
            "-srcfolder", stagingDir.path,
            "-fs", "HFS+", "-quiet",
        ])
    }

    private func run(_ command: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "\(command) \(arguments) failed")
    }

    private func temporaryDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorUpdate_installer_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: 1. Archiwum z inną aplikacją → odrzucenie

    @Test func install_differentBundleIdentifier_rejected() throws {
        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let currentApp = try makeApp(named: "Current", bundleID: "com.example.current", in: workDir)
        let intruder = try makeApp(named: "Intruder", bundleID: "com.example.intruder", in: workDir)

        let zipURL = workDir.appendingPathComponent("update.zip")
        try zip(intruder, to: zipURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: currentApp)
        do {
            _ = try installer.install(zipURL, into: installDir)
            Issue.record("Expected the foreign bundle to be rejected")
        } catch let error as UpdateInstaller.InstallerError {
            guard case .bundleIdentifierMismatch(let expected, let found) = error else {
                Issue.record("Expected .bundleIdentifierMismatch, got \(error)")
                return
            }
            #expect(expected == "com.example.current")
            #expect(found == "com.example.intruder")
        }

        // Nic nie wylądowało obok aplikacji bieżącej.
        let installed = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
        #expect(installed.isEmpty, "Nothing should have been installed, found \(installed)")
    }

    // MARK: 2. Ta sama aplikacja, oba podpisy ad-hoc → instalacja przechodzi
    //
    // Podpis ad-hoc pinuje cdhash jednego builda, więc żaden nowy build nigdy go
    // nie spełni. Wymaganie zgodności zablokowałoby każdą aktualizację, dlatego
    // ta ścieżka jest świadomie przepuszczana (z ostrzeżeniem na stderr), a cała
    // autentyczność opiera się na podpisie Ed25519.

    @Test func install_sameIdentifierBothAdHoc_succeeds() throws {
        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let currentApp = try makeApp(named: "Current", bundleID: "com.example.current", in: workDir)

        let newVersionDir = workDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: newVersionDir, withIntermediateDirectories: true)
        let newApp = try makeApp(named: "Current", bundleID: "com.example.current", in: newVersionDir)

        let zipURL = workDir.appendingPathComponent("update.zip")
        try zip(newApp, to: zipURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: currentApp)
        let installedApp = try installer.install(zipURL, into: installDir)
        #expect(FileManager.default.fileExists(
            atPath: installedApp.appendingPathComponent("Contents/Info.plist").path))
    }

    // MARK: 3. Nazwa katalogu docelowego pochodzi z aplikacji bieżącej

    @Test func install_renamedBundleInArchive_keepsCurrentAppName() throws {
        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let currentApp = try makeApp(named: "Current", bundleID: "com.example.current", in: workDir)

        // Ta sama aplikacja (ten sam identyfikator), ale w archiwum pod inną nazwą.
        let newVersionDir = workDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: newVersionDir, withIntermediateDirectories: true)
        let renamed = try makeApp(named: "Renamed", bundleID: "com.example.current", in: newVersionDir)

        let zipURL = workDir.appendingPathComponent("update.zip")
        try zip(renamed, to: zipURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: currentApp)
        let installedApp = try installer.install(zipURL, into: installDir)

        #expect(installedApp.lastPathComponent == "Current.app",
                "Instalacja ma zastąpić aplikację bieżącą, nie stanąć obok jako Renamed.app")
        let installed = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
        #expect(installed == ["Current.app"], "Znaleziono \(installed)")
    }

    // MARK: 4. Instalacja z obrazu .dmg (montowanego tylko do odczytu)

    @Test(.timeLimit(.minutes(1)))
    func install_fromDiskImage_succeedsAndUnmounts() throws {
        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let currentApp = try makeApp(named: "Current", bundleID: "com.example.current", in: workDir)

        let newVersionDir = workDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: newVersionDir, withIntermediateDirectories: true)
        let newApp = try makeApp(named: "Current", bundleID: "com.example.current", in: newVersionDir)

        let dmgURL = workDir.appendingPathComponent("update.dmg")
        try dmg(newApp, to: dmgURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: currentApp)
        let installedApp = try installer.install(dmgURL, into: installDir)

        #expect(installedApp.lastPathComponent == "Current.app")
        #expect(FileManager.default.fileExists(
            atPath: installedApp.appendingPathComponent("Contents/Info.plist").path))

        // Obraz ma zostać odmontowany, a punkt montowania sprzątnięty.
        let leftovers = try FileManager.default.contentsOfDirectory(
            atPath: FileManager.default.temporaryDirectory.path)
            .filter { $0.hasPrefix("ErrorUpdate_mount_") }
        #expect(leftovers.isEmpty, "Pozostały punkty montowania: \(leftovers)")
    }

    // MARK: 5. Aplikacja podpisana certyfikatem, aktualizacja podpisana ad-hoc → odrzucenie
    //
    // Aplikacja systemowa służy tu za stabilnie podpisany punkt odniesienia:
    // jej wymaganie projektowe to `identifier "com.apple.calculator" and anchor
    // apple`. Podrobiony pakiet z tym samym identyfikatorem przechodzi kontrolę
    // identyfikatora, a musi polec na kontroli tożsamości podpisującego.

    // MARK: 5. Ścieżka pozytywna: aktualizacja podpisana TYM SAMYM certyfikatem
    //
    // Wymaga certyfikatu do podpisu kodu, więc jest opcjonalny — bez niego
    // zestaw pokrywa wyłącznie odrzucenia, a to jest ten wariant, który musi
    // działać u każdego integratora. Uruchomienie:
    //
    //   ERRORUPDATE_SIGNING_IDENTITY=$(security find-identity -p codesigning \
    //       | grep "Local Developer" | awk '{print $2}') swift test
    //
    // Wersja podpisana ad-hoc nigdy tu nie wystarczy: jej designated requirement
    // pinuje cdhash jednego builda, więc kolejne wydanie nie może go spełnić.

    private static var signingIdentity: String? {
        ProcessInfo.processInfo.environment["ERRORUPDATE_SIGNING_IDENTITY"]
    }

    @Test(.enabled(if: signingIdentity != nil), .timeLimit(.minutes(1)))
    func install_updateSignedBySameCertificate_isAccepted() throws {
        let identity = try #require(Self.signingIdentity)

        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let currentApp = try makeApp(named: "Current", bundleID: "com.example.current",
                                     in: workDir, signingIdentity: identity)

        // Osobny build tej samej aplikacji — inna zawartość, ten sam certyfikat.
        let newVersionDir = workDir.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: newVersionDir, withIntermediateDirectories: true)
        let newApp = try makeApp(named: "Current", bundleID: "com.example.current",
                                 in: newVersionDir, signingIdentity: identity)
        let resourcesDir = newApp.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
        try "// wersja 2\n".write(to: resourcesDir.appendingPathComponent("version.txt"),
                                  atomically: true, encoding: .utf8)
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", identity, newApp.path])

        // Dowód, że punkt odniesienia jest stabilny, a nie przypadkiem ad-hoc.
        #expect(!designatedRequirement(of: currentApp).contains("cdhash"),
                "Certyfikat miał dać wymaganie oparte na certyfikacie, nie na cdhash")
        #expect(designatedRequirement(of: currentApp) == designatedRequirement(of: newApp),
                "Dwa buildy tym samym certyfikatem muszą mieć identyczne wymaganie")

        let zipURL = workDir.appendingPathComponent("update.zip")
        try zip(newApp, to: zipURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: currentApp)
        let installedApp = try installer.install(zipURL, into: installDir)

        #expect(FileManager.default.fileExists(
            atPath: installedApp.appendingPathComponent("Contents/Resources/version.txt").path),
                "Zainstalowana ma być nowa wersja")
    }

    private func designatedRequirement(of appURL: URL) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-d", "-r-", appURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""
        guard let line = output.split(separator: "\n").first(where: { $0.contains("designated =>") }),
              let range = line.range(of: "designated =>") else { return "" }
        return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
    }

    // MARK: 6. Aplikacja podpisana certyfikatem, aktualizacja podpisana ad-hoc → odrzucenie

    private static let referenceApp = URL(fileURLWithPath: "/System/Applications/Calculator.app")

    @Test(.enabled(if: FileManager.default.fileExists(atPath: referenceApp.path)))
    func install_adHocImpostorAgainstCertifiedApp_rejected() throws {
        let workDir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workDir) }

        let impostor = try makeApp(named: "Calculator", bundleID: "com.apple.calculator", in: workDir)
        let zipURL = workDir.appendingPathComponent("update.zip")
        try zip(impostor, to: zipURL)

        let installDir = workDir.appendingPathComponent("install")
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)

        let installer = UpdateInstaller(currentAppURL: Self.referenceApp)
        do {
            _ = try installer.install(zipURL, into: installDir)
            Issue.record("Expected the ad-hoc impostor to be rejected")
        } catch let error as UpdateInstaller.InstallerError {
            guard case .signingIdentityMismatch = error else {
                Issue.record("Expected .signingIdentityMismatch, got \(error)")
                return
            }
        }

        let installed = try FileManager.default.contentsOfDirectory(atPath: installDir.path)
        #expect(installed.isEmpty, "Nothing should have been installed, found \(installed)")
    }
}
