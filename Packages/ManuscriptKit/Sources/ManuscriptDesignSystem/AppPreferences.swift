import Foundation
import SwiftUI

public enum MMPreferenceKey {
    public static let appearance = "app.appearance"
    public static let interfaceLanguage = "app.interfaceLanguage"
}

public enum MMAppearancePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

public enum MMInterfaceLanguage: String, CaseIterable, Identifiable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    public var id: String { rawValue }
    public var locale: Locale { Locale(identifier: rawValue) }
}

/// Resolves dynamic presentation strings from the same standard localized
/// resources used by SwiftUI's `LocalizedStringKey` views. Static Text/Button
/// literals localize automatically; values assembled in code use this helper.
public enum MMLocalization {
    public static var language: MMInterfaceLanguage {
        let rawValue = UserDefaults.standard.string(forKey: MMPreferenceKey.interfaceLanguage)
        return MMInterfaceLanguage(rawValue: rawValue ?? "") ?? .simplifiedChinese
    }

    public static var locale: Locale { language.locale }

    public static func string(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: locale, arguments: arguments)
    }
}
