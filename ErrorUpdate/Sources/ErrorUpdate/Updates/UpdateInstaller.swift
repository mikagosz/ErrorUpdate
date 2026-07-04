//
//  UpdateInstaller.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation
import AppKit

/// Handles the installation of a downloaded update file.
class UpdateInstaller {
    
    enum InstallerError: Error {
        case unsupportedFileFormat
        case taskFailed(command: String, exitCode: Int32, output: String)
        case couldNotFindAppBundle
        case installationFailed(Error)
        case couldNotGetApplicationSupportDirectory
    }

    /// Installs an update from a local file URL.
    /// - Parameter downloadedFileURL: The URL of the downloaded `.dmg` or `.zip` file.
    /// - Parameter completion: A closure to be called with the result.
    func installUpdate(from downloadedFileURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        let fileExtension = downloadedFileURL.pathExtension.lowercased()
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                switch fileExtension {
                case "dmg":
                    try self.installDmg(at: downloadedFileURL)
                case "zip":
                    try self.installZip(at: downloadedFileURL)
                default:
                    throw InstallerError.unsupportedFileFormat
                }
                
                // TODO: Relaunch the application.
                // This is a complex task that requires a helper process or a script.
                // For now, we will just signal success.
                print("Installation successful. App relaunch needed.")
                
                DispatchQueue.main.async {
                    completion(.success(()))
                }
                
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    // MARK: - DMG Installation
    
    private func installDmg(at dmgURL: URL) throws {
        // 1. Attach DMG
        let attachResult = try runTask(command: "/usr/bin/hdiutil", arguments: ["attach", "-nobrowse", "-mountpoint", "/Volumes/ErrorUpdateInstaller", dmgURL.path])
        
        let mountPoint = "/Volumes/ErrorUpdateInstaller"
        
        // Ensure cleanup happens even if subsequent steps fail
        defer {
            do {
                try runTask(command: "/usr/bin/hdiutil", arguments: ["detach", mountPoint])
            } catch {
                print("Failed to detach DMG: \(error)")
            }
        }

        // 2. Find .app bundle
        guard let appURL = try findAppBundle(in: URL(fileURLWithPath: mountPoint)) else {
            throw InstallerError.couldNotFindAppBundle
        }
        
        // 3. Copy .app to /Applications
        let appName = appURL.lastPathComponent
        let destinationURL = URL(fileURLWithPath: "/Applications/\(appName)")
        
        // TODO: Backup existing application before replacing.
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: appURL, to: destinationURL)
    }
    
    // MARK: - ZIP Installation
    
    private func installZip(at zipURL: URL) throws {
        // 1. Unzip to a temporary directory
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        try runTask(command: "/usr/bin/unzip", arguments: [zipURL.path, "-d", tempDir.path])
        
        // 2. Find .app bundle in the unzipped contents
        guard let appURL = try findAppBundle(in: tempDir) else {
            throw InstallerError.couldNotFindAppBundle
        }

        // 3. Copy .app to /Applications
        let appName = appURL.lastPathComponent
        let destinationURL = URL(fileURLWithPath: "/Applications/\(appName)")

        // TODO: Backup existing application before replacing.

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: appURL, to: destinationURL)
    }

    // MARK: - Helpers
    
    @discardableResult
    private func runTask(command: String, arguments: [String]) throws -> String {
        let process = Process()
        process.launchPath = command
        process.arguments = arguments
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        process.launch()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw InstallerError.taskFailed(command: command, exitCode: process.terminationStatus, output: output)
        }
        
        return output
    }
    
    private func findAppBundle(in directory: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
        return contents.first { $0.pathExtension == "app" }
    }
}
