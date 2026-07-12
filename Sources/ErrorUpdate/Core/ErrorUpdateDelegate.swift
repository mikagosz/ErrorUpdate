//
//  ErrorUpdateDelegate.swift
//  ErrorUpdate
//

import Foundation

/// A delegate protocol for receiving callbacks from the ErrorUpdate framework.
/// All methods are called on the main actor and have default empty implementations.
@MainActor
public protocol ErrorUpdateDelegate: AnyObject {

    /// Called after an error has been caught and a report has been generated.
    func didCatchError(_ report: ErrorReport)

    /// Called when an update has been detected.
    func didDetectUpdate(_ info: UpdateInfo)

    /// Called when the update process (check, download or install) fails.
    func updateDidFail(_ error: Error)
}

public extension ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {}
    func didDetectUpdate(_ info: UpdateInfo) {}
    func updateDidFail(_ error: Error) {}
}
