//
//  SystemInfoCollector.swift
//  ErrorUpdate
//
//  Created by Gemini on 2026-07-04.
//

import Foundation

/// A utility for collecting information about the user's system.
///
/// This class primarily serves as a designated architectural component for gathering system-wide details.
/// The core logic is implemented in the `SystemInfo.current()` static factory method.
class SystemInfoCollector {
    
    /// Gathers current system information.
    /// - Returns: A `SystemInfo` struct populated with current data.
    static func collect() -> SystemInfo {
        return SystemInfo.current()
    }
    
    // MARK: - Note on Other Contextual Data
    
    /// **Custom Context:**
    /// The collection of app-specific custom context (e.g., screen name, application state)
    /// is handled directly when an error is logged. The `logError` and `handleCrash` methods
    /// provide a `context` parameter, which is then passed into the `ErrorReport` model.
    
    /// **Timestamps:**
    /// Timestamps are captured at the moment an error report is created and are stored in the
    /// `timestamp` property of the `ErrorReport` model. The `ServerClient` is configured to
    /// encode dates in the ISO 8601 format for transmission.

}
