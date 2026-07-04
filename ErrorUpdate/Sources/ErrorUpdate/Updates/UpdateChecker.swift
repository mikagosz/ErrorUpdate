//
//  UpdateChecker.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// Checks for new application versions on the server.
class UpdateChecker {
    
    private let serverClient: ServerClient
    private let currentVersion: String
    private let userDefaults: UserDefaults
    
    private let cacheInterval: TimeInterval = 3600 // 1 hour
    private let lastCheckDateKey = "ErrorUpdate_LastUpdateCheckDate"
    
    init(serverClient: ServerClient, currentVersion: String, userDefaults: UserDefaults = .standard) {
        self.serverClient = serverClient
        self.currentVersion = currentVersion
        self.userDefaults = userDefaults
    }
    
    /// Checks for updates, respecting the cache interval.
    /// - Parameter completion: A closure called with the result. It returns `UpdateInfo` if a new version is available, or `nil` otherwise.
    func checkForUpdates(completion: @escaping (Result<UpdateInfo?, Error>) -> Void) {
        
        // Check if we should perform a check based on the cache interval
        if let lastCheckDate = userDefaults.object(forKey: lastCheckDateKey) as? Date {
            if Date().timeIntervalSince(lastCheckDate) < cacheInterval {
                print("Update check skipped (checked recently).")
                completion(.success(nil))
                return
            }
        }
        
        serverClient.fetchVersionInfo { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let updateInfo):
                // Update the last check date
                self.userDefaults.set(Date(), forKey: self.lastCheckDateKey)
                
                // Compare versions
                if self.isVersion(updateInfo.latestVersion, greaterThan: self.currentVersion) {
                    completion(.success(updateInfo))
                } else {
                    completion(.success(nil)) // No new version available
                }
                
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Compares two semantic version strings.
    /// - Returns: `true` if `newVersion` is greater than `oldVersion`.
    private func isVersion(_ newVersion: String, greaterThan oldVersion: String) -> Bool {
        let newComponents = newVersion.split(separator: ".").compactMap { Int($0) }
        let oldComponents = oldVersion.split(separator: ".").compactMap { Int($0) }
        
        // Compare component by component
        let comparisonCount = min(newComponents.count, oldComponents.count)
        for i in 0..<comparisonCount {
            if newComponents[i] > oldComponents[i] {
                return true
            }
            if newComponents[i] < oldComponents[i] {
                return false
            }
        }
        
        // If all common components are equal, the longer version number is greater
        // e.g., 1.0.1 > 1.0
        return newComponents.count > oldComponents.count
    }
}
