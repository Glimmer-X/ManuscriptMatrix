import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

/// Compact publisher wordmarks for the rank rail. Publisher detection is a
/// presentation concern for now, so the persisted journal schema stays stable.
struct JournalPublisherMark: View {
    let journal: Journal
    var style: Style = .wordmark

    @Environment(\.colorScheme) private var colorScheme

    enum Style {
        case wordmark
        case dot
    }

    var body: some View {
        if style == .dot {
            Circle()
                .fill(Publisher(journal: journal)?.color(for: colorScheme) ?? Color.secondary.opacity(0.34))
                .frame(width: 7, height: 7)
                .shadow(
                    color: (Publisher(journal: journal)?.color(for: colorScheme) ?? .clear).opacity(0.28),
                    radius: 3
                )
                .accessibilityLabel(Publisher(journal: journal)?.accessibilityName ?? MMLocalization.string("其他出版商"))
        } else if let publisher = Publisher(journal: journal) {
            Group {
                switch publisher {
                case .nature:
                    Text("NATURE")
                        .font(.system(size: 6, weight: .bold, design: .serif))
                        .tracking(-0.15)
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                        .background(
                            colorScheme == .dark ? Color.white : Color.black,
                            in: RoundedRectangle(cornerRadius: 3, style: .continuous)
                        )

                case .ieee:
                    HStack(spacing: 2) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 5, weight: .bold))
                        Text("IEEE")
                            .font(.system(size: 7, weight: .black, design: .rounded))
                            .tracking(-0.1)
                    }
                    .foregroundStyle(Color(red: 0 / 255, green: 98 / 255, blue: 155 / 255))

                case .elsevier:
                    Text("ELSEVIER")
                        .font(.system(size: 5.5, weight: .bold, design: .rounded))
                        .tracking(-0.2)
                        .foregroundStyle(Color(red: 232 / 255, green: 120 / 255, blue: 24 / 255))

                case .acm:
                    Text("ACM")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .foregroundStyle(Color(red: 0 / 255, green: 133 / 255, blue: 202 / 255))

                case .isca:
                    Text("ISCA")
                        .font(.system(size: 7, weight: .black, design: .rounded))
                        .tracking(0.1)
                        .foregroundStyle(MMColor.jade)
                }
            }
            .frame(maxWidth: 42)
            .accessibilityLabel(publisher.accessibilityName)
        }
    }
}

private extension JournalPublisherMark {
    enum Publisher {
        case nature
        case ieee
        case elsevier
        case acm
        case isca

        init?(journal: Journal) {
            let name = journal.currentName
            let normalizedTags = journal.tags.map { $0.lowercased() }

            if name.hasPrefix("Nature ") || normalizedTags.contains(where: { $0.contains("nature portfolio") }) {
                self = .nature
            } else if name.hasPrefix("IEEE ") || name.hasPrefix("IEEE/") || name.hasPrefix("IEEE\\/ACM") {
                self = .ieee
            } else if name.hasPrefix("ACM ") {
                self = .acm
            } else if name.hasPrefix("AVSEC ") || normalizedTags.contains(where: { $0.contains("interspeech") || $0.contains("isca") }) {
                self = .isca
            } else if Self.elsevierTitles.contains(name) || normalizedTags.contains("elsevier") {
                self = .elsevier
            } else {
                return nil
            }
        }

        var accessibilityName: String {
            switch self {
            case .nature: "Nature Portfolio"
            case .ieee: "IEEE"
            case .elsevier: "Elsevier"
            case .acm: "ACM"
            case .isca: "ISCA"
            }
        }

        func color(for colorScheme: ColorScheme) -> Color {
            switch self {
            case .nature:
                colorScheme == .dark ? .white : .black
            case .ieee:
                Color(red: 0 / 255, green: 98 / 255, blue: 155 / 255)
            case .elsevier:
                Color(red: 232 / 255, green: 120 / 255, blue: 24 / 255)
            case .acm:
                Color(red: 0 / 255, green: 133 / 255, blue: 202 / 255)
            case .isca:
                MMColor.jade
            }
        }

        private static let elsevierTitles: Set<String> = [
            "Advances in Engineering Software",
            "Computer Physics Communications",
            "Digital Signal Processing",
            "Information Fusion",
            "Information Sciences",
            "Knowledge-Based Systems",
            "Pattern Recognition"
        ]
    }
}
