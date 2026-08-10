import Foundation
import SwiftUI

/// UI language of the demo app. Persisted in `UserDefaults`; switching it updates
/// the interface live, with no restart.
enum AppLanguage: String, CaseIterable, Identifiable {
    case pl, en

    var id: String { rawValue }

    /// Native name shown in the language picker.
    var displayName: String {
        switch self {
        case .pl: return "Polski"
        case .en: return "English"
        }
    }
}

/// Runtime localization for the demo.
///
/// The framework itself carries no user-facing strings in any language other than
/// English, so this exists purely for the sample app — a Polish reader gets Polish,
/// everyone else gets English, and neither has to translate the demo to work out
/// what the library does.
@Observable
final class Localization {
    static let key = "ErrorUpdateDemo_Language"

    var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.key) }
    }

    init() {
        let stored = UserDefaults.standard.string(forKey: Self.key)
        // No stored choice: follow the system, so a Polish Mac opens in Polish
        // and every other Mac opens in English.
        let systemIsPolish = Locale.preferredLanguages.first?.hasPrefix("pl") ?? false
        language = AppLanguage(rawValue: stored ?? "") ?? (systemIsPolish ? .pl : .en)
    }

    /// Returns the Polish or English variant for the current UI language.
    func t(_ pl: String, _ en: String) -> String {
        language == .pl ? pl : en
    }
}
