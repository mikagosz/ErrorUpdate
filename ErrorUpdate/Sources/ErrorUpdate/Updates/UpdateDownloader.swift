//
//  UpdateDownloader.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation
import CryptoKit

/// Handles the download and verification of update files.
class UpdateDownloader: NSObject, URLSessionDownloadDelegate {
    
    typealias ProgressHandler = (Double) -> Void
    typealias CompletionHandler = (Result<URL, Error>) -> Void
    
    enum DownloadError: Error {
        case verificationFailed
        case fileMoveFailed
        case unexpectedError
    }
    
    private var session: URLSession!
    private var progressHandler: ProgressHandler?
    private var completionHandler: CompletionHandler?
    private var expectedSHA256: String = ""
    private var downloadTask: URLSessionDownloadTask?
    
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.default
        self.session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
    }

    /// Downloads an update file from a given URL.
    /// - Parameters:
    ///   - url: The URL to download the update from.
    ///   - sha256: The expected SHA256 checksum of the file for verification.
    ///   - progress: A closure to be called with the download progress (0.0 to 1.0).
    ///   - completion: A closure to be called with the result, containing the URL to the verified file.
    func downloadUpdate(from url: URL, sha256: String, progress: @escaping ProgressHandler, completion: @escaping CompletionHandler) {
        self.progressHandler = progress
        self.completionHandler = completion
        self.expectedSHA256 = sha256.lowercased()
        
        // Clean up any old downloads before starting a new one.
        cleanup()
        
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
    
    // MARK: - URLSessionDownloadDelegate
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        progressHandler?(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            // 1. Verify the checksum
            let downloadedSHA256 = try self.sha256(for: location)
            guard downloadedSHA256.lowercased() == self.expectedSHA256 else {
                completionHandler?(.failure(DownloadError.verificationFailed))
                return
            }
            
            // 2. Move the verified file to a permanent cache location
            let destinationURL = try self.cacheDirectory().appendingPathComponent(location.lastPathComponent)
            try FileManager.default.moveItem(at: location, to: destinationURL)
            
            completionHandler?(.success(destinationURL))
            
        } catch {
            completionHandler?(.failure(error))
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            completionHandler?(.failure(error))
        }
    }

    // MARK: - File Management & Verification
    
    private func cacheDirectory() throws -> URL {
        let fileManager = FileManager.default
        let cacheURL = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let downloaderCacheURL = cacheURL.appendingPathComponent("com.gemini.ErrorUpdate")
        
        if !fileManager.fileExists(atPath: downloaderCacheURL.path) {
            try fileManager.createDirectory(at: downloaderCacheURL, withIntermediateDirectories: true, attributes: nil)
        }
        
        return downloaderCacheURL
    }

    /// Cleans up any files in the downloader's cache directory.
    func cleanup() {
        do {
            let cacheDir = try cacheDirectory()
            let fileManager = FileManager.default
            let items = try fileManager.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil)
            for item in items {
                try fileManager.removeItem(at: item)
            }
        } catch {
            print("Error cleaning up cache: \(error)")
        }
    }
    
    /// Calculates the SHA256 checksum of a file at a given URL.
    private func sha256(for fileURL: URL) throws -> String {
        let fileData = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: fileData)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Cancels the ongoing download task.
    func cancel() {
        downloadTask?.cancel()
    }
}
