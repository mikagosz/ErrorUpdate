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

    /// Called when an install finished but left the app on the old version —
    /// see ``IneffectiveUpdate``. Fires once on the launch that detects it, and
    /// again whenever the server keeps offering that same version.
    ///
    /// This is a packaging mistake on the release side, not a runtime error, so
    /// it is deliberately not routed through ``updateDidFail(_:)``.
    ///
    /// The detecting call happens inside `configure(_:)`, which usually runs
    /// before the delegate is assigned — so the launch-time case may only be
    /// visible through `ErrorUpdateManager.ineffectiveUpdate`, which keeps it.
    func updateDidNotTakeEffect(_ report: IneffectiveUpdate)
}

public extension ErrorUpdateDelegate {
    func didCatchError(_ report: ErrorReport) {}
    func didDetectUpdate(_ info: UpdateInfo) {}
    func updateDidFail(_ error: Error) {}
    func updateDidNotTakeEffect(_ report: IneffectiveUpdate) {}
}
