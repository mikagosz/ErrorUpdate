//
//  ErrorUpdateDelegate.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// A delegate protocol for receiving callbacks from the ErrorUpdate framework.
public protocol ErrorUpdateDelegate: AnyObject {
    
    /// Called after an error has been caught and a report has been generated.
    /// - Parameter report: The generated `ErrorReport`.
    func didCatchError(_ report: ErrorReport)
    
    /// Called when an update has been detected.
    /// - Parameter info: The `UpdateInfo` for the available update.
    func didDetectUpdate(_ info: UpdateInfo)
    
    /// Called when the update process (download or install) fails.
    /// - Parameter error: The error that occurred during the update process.
    func updateDidFail(_ error: Error)
}
