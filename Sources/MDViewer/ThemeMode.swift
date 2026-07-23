import Foundation

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var iconName: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// The `data-theme` attribute value to set on the HTML element, or nil for system mode.
    var htmlAttribute: String? {
        switch self {
        case .system: nil
        case .light: "light"
        case .dark: "dark"
        }
    }
}
