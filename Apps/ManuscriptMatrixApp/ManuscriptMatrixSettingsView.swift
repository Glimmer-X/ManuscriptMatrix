import ManuscriptDesignSystem
import SwiftUI

struct ManuscriptMatrixSettingsView: View {
    @AppStorage(MMPreferenceKey.appearance) private var appearanceRawValue = MMAppearancePreference.system.rawValue
    @AppStorage(MMPreferenceKey.interfaceLanguage) private var languageRawValue = MMInterfaceLanguage.simplifiedChinese.rawValue

    var body: some View {
        VStack(spacing: 0) {
            brandHeader

            Divider()

            Form {
                Picker("外观", selection: $appearanceRawValue) {
                    Text("跟随系统").tag(MMAppearancePreference.system.rawValue)
                    Text("浅色").tag(MMAppearancePreference.light.rawValue)
                    Text("深色").tag(MMAppearancePreference.dark.rawValue)
                }

                Picker("界面语言", selection: $languageRawValue) {
                    Text("中文").tag(MMInterfaceLanguage.simplifiedChinese.rawValue)
                    Text("English").tag(MMInterfaceLanguage.english.rawValue)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
        }
        .frame(width: 430, height: 330)
        .background(MMColor.canvas)
        .environment(\.locale, interfaceLanguage.locale)
        .preferredColorScheme(appearance.colorScheme)
    }

    private var brandHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.black)
                Image(systemName: "square.grid.3x3.middle.filled")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 68, height: 68)

            VStack(alignment: .leading, spacing: 5) {
                Text("Manuscript Matrix")
                    .font(.system(size: 19, weight: .semibold))
                Text("投稿策略、时间与历史")
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.secondaryInk)
                Text(MMLocalization.format("版本 %@（%@）", version, build))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(MMColor.secondaryInk)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 24)
    }

    private var appearance: MMAppearancePreference {
        MMAppearancePreference(rawValue: appearanceRawValue) ?? .system
    }

    private var interfaceLanguage: MMInterfaceLanguage {
        MMInterfaceLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }
}
