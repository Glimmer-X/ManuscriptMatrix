import SwiftUI

public struct MMPill: View {
    private let text: String
    private let foreground: Color
    private let background: Color
    private let systemImage: String?

    public init(
        _ text: String,
        foreground: Color,
        background: Color,
        systemImage: String? = nil
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(MMLocalization.string(text))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(background, in: Capsule())
    }
}

public struct MMSectionLabel: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(MMLocalization.string(title).uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .tracking(1.3)
            .foregroundStyle(MMColor.secondaryInk)
    }
}

public struct MMIconButton: View {
    private let systemName: String
    private let help: String
    private let action: () -> Void

    public init(systemName: String, help: String, action: @escaping () -> Void) {
        self.systemName = systemName
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MMColor.elevated.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .stroke(MMColor.hairline, lineWidth: 0.7)
        }
        .help(MMLocalization.string(help))
    }
}
