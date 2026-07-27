import Foundation

enum L10n {
    static func string(_ key: String, fallback: String) -> String {
        Bundle.main.localizedString(forKey: key, value: fallback, table: nil)
    }

    static func format(
        _ key: String,
        fallback: String,
        _ arguments: CVarArg...
    ) -> String {
        let format = string(key, fallback: fallback)
        return String(format: format, locale: Locale.current, arguments: arguments)
    }
}

enum AppLanguage: String, CaseIterable {
    case english
    case simplifiedChinese
    case traditionalChinese
    case japanese
    case korean
    case spanish
    case french
    case german

    static var current: AppLanguage {
        let selectedLanguage = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        let identifier = selectedLanguage
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if identifier.hasPrefix("zh-hant")
            || identifier.hasPrefix("zh-tw")
            || identifier.hasPrefix("zh-hk")
            || identifier.hasPrefix("zh-mo") {
            return .traditionalChinese
        }
        if identifier.hasPrefix("zh") { return .simplifiedChinese }
        if identifier.hasPrefix("ja") { return .japanese }
        if identifier.hasPrefix("ko") { return .korean }
        if identifier.hasPrefix("es") { return .spanish }
        if identifier.hasPrefix("fr") { return .french }
        if identifier.hasPrefix("de") { return .german }
        return .english
    }

    var promptName: String {
        switch self {
        case .english: return "English"
        case .simplifiedChinese: return "Simplified Chinese"
        case .traditionalChinese: return "Traditional Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }
}
