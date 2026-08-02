//
//  ErrorUpdateTheme.swift
//  ErrorUpdate
//

import SwiftUI

/// Colours and chrome for the framework's built-in dialogs.
///
/// These windows are shown to *your* users, so the host app has to be able to
/// make them look like its own. `.neon` keeps the framework's original look;
/// `.system` steps out of the way and uses standard macOS materials.
public struct ErrorUpdateTheme: Sendable {

    /// How much chrome the dialog draws around itself.
    public enum Chrome: Sendable {
        /// Rounded card with a border and a coloured glow.
        case card
        /// No card: plain background, native window look.
        case plain
    }

    public var background: Color
    public var secondaryBackground: Color
    public var primaryText: Color
    public var title: Color
    /// Accent for the update dialog (icon, glow).
    public var accent: Color
    /// Accent for the error-report dialog, which usually wants a warmer colour.
    public var errorAccent: Color
    public var border: Color
    public var chrome: Chrome

    public init(
        background: Color,
        secondaryBackground: Color,
        primaryText: Color,
        title: Color,
        accent: Color,
        errorAccent: Color,
        border: Color,
        chrome: Chrome = .card
    ) {
        self.background = background
        self.secondaryBackground = secondaryBackground
        self.primaryText = primaryText
        self.title = title
        self.accent = accent
        self.errorAccent = errorAccent
        self.border = border
        self.chrome = chrome
    }

    /// The framework's original look: dark card, cyan title, neon glow.
    public static let neon = ErrorUpdateTheme(
        background: Color.black.opacity(0.9),
        secondaryBackground: Color.black.opacity(0.5),
        primaryText: Color(red: 0.9, green: 0.9, blue: 0.9),
        title: Color(red: 0.3, green: 1.0, blue: 0.9),
        accent: Color(red: 0.2, green: 0.8, blue: 1.0),
        errorAccent: Color(red: 1.0, green: 0.2, blue: 0.8),
        border: Color.white.opacity(0.2),
        chrome: .card
    )

    /// Standard macOS appearance: follows the user's light/dark setting and the
    /// app's accent colour, with no card chrome of its own.
    public static let system = ErrorUpdateTheme(
        background: Color.clear,
        secondaryBackground: Color(nsColor: .textBackgroundColor),
        primaryText: Color(nsColor: .labelColor),
        title: Color(nsColor: .labelColor),
        accent: Color.accentColor,
        errorAccent: Color(nsColor: .systemRed),
        border: Color(nsColor: .separatorColor),
        chrome: .plain
    )
}

// MARK: - Chrome

/// Draws (or deliberately omits) the card background, border and glow.
struct ErrorUpdateChrome: ViewModifier {
    let theme: ErrorUpdateTheme
    let glow: Color

    func body(content: Content) -> some View {
        switch theme.chrome {
        case .card:
            content
                .background(theme.background)
                .cornerRadius(15)
                .shadow(color: glow.opacity(0.4), radius: 10, x: 0, y: 0)
                .overlay(
                    RoundedRectangle(cornerRadius: 15)
                        .stroke(theme.border, lineWidth: 1)
                )
        case .plain:
            // No background of our own: the window material shows through, so
            // the dialog matches whatever appearance the host app runs in.
            content
        }
    }
}

// MARK: - Environment

private struct ErrorUpdateThemeKey: EnvironmentKey {
    static let defaultValue: ErrorUpdateTheme = .neon
}

public extension EnvironmentValues {
    /// Theme used by `UpdateAvailableView` and `ReportConfirmationView`.
    var errorUpdateTheme: ErrorUpdateTheme {
        get { self[ErrorUpdateThemeKey.self] }
        set { self[ErrorUpdateThemeKey.self] = newValue }
    }
}

public extension View {
    /// Applies a theme to the framework's dialogs below this view.
    func errorUpdateTheme(_ theme: ErrorUpdateTheme) -> some View {
        environment(\.errorUpdateTheme, theme)
    }
}
