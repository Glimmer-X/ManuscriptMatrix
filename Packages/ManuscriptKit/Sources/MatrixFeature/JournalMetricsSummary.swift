import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

/// A compact, non-pill presentation for structured journal metrics.
/// The board and journal library share this view so their hierarchy stays aligned.
struct JournalMetricsSummary: View {
    enum Density {
        case overview
        case matrix
        case library
    }

    let journal: Journal
    var density: Density = .matrix

    var body: some View {
        VStack(alignment: .leading, spacing: secondarySpacing) {
            if density == .library {
                labeledPrimaryLine
            } else {
                compactPrimaryLine
            }

            if density != .overview {
                ForEach(secondaryLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: secondaryFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(MMColor.secondaryInk)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var compactPrimaryLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: primarySpacing) {
            compactValue(impactFactorText, color: MMColor.ink)
            compactDivider
            compactValue(ccfValue, color: ccfColor)
            compactDivider
            compactValue(casValue, color: casColor)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }

    private var labeledPrimaryLine: some View {
        HStack(alignment: .center, spacing: primarySpacing) {
            primaryMetric(label: "IF", value: impactFactorText, color: MMColor.ink)
            metricDivider
            primaryMetric(label: "CCF", value: ccfValue, color: ccfColor)
            metricDivider
            primaryMetric(label: MMLocalization.string("中科院"), value: casValue, color: casColor)
        }
        .lineLimit(1)
    }

    private func compactValue(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: primaryValueSize, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(color)
    }

    private var compactDivider: some View {
        Text("·")
            .font(.system(size: density == .overview ? 8 : 10, weight: .bold, design: .rounded))
            .foregroundStyle(MMColor.hairline.opacity(0.9))
    }

    private func primaryMetric(label: String, value: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: density == .overview ? 2 : 3) {
            Text(label)
                .font(.system(size: primaryLabelSize, weight: .bold, design: .rounded))
                .tracking(density == .overview ? 0.15 : 0.45)
                .foregroundStyle(MMColor.secondaryInk)
            Text(value)
                .font(.system(size: primaryValueSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(MMColor.hairline)
            .frame(width: 1, height: density == .overview ? 10 : 13)
    }

    private var impactFactorText: String {
        journal.metrics.impactFactor?.formatted(.number.precision(.fractionLength(1))) ?? "—"
    }

    private var ccfValue: String {
        latestPartition(schemes: ["CCF"])?.value ?? "—"
    }

    private var casValue: String {
        let value = latestPartition(schemes: ["CAS", "中科院"])?.value ?? "—"
        return topLabel == nil ? value : "\(value) TOP"
    }

    private var ccfColor: Color {
        switch ccfValue.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "A": MMColor.amber
        case "B": MMColor.indigo
        case "C": MMColor.graphite
        default: MMColor.secondaryInk
        }
    }

    private var casColor: Color {
        let value = latestPartition(schemes: ["CAS", "中科院"])?.value ?? ""
        if value.contains("1") { return MMColor.jade }
        if value.contains("2") { return MMColor.indigo }
        if value.contains("3") { return MMColor.amber }
        return MMColor.graphite
    }

    private var secondaryLines: [String] {
        var lines: [String] = []

        let headline = [
            latestPartition(schemes: ["JCR"]).map { "JCR \(compactAnnualLabel($0))" },
            latestPartition(schemes: ["新锐"]).map { "\(MMLocalization.string("新锐")) \(compactAnnualLabel($0))" }
        ]
        .compactMap { $0 }
        .joined(separator: "  ·  ")
        if !headline.isEmpty { lines.append(headline) }

        let cas = matchingPartitions(schemes: ["CAS", "中科院"])
            .prefix(2)
            .map { compactAnnualLabel($0) }
            .joined(separator: " / ")
        if !cas.isEmpty { lines.append(MMLocalization.format("中科院历年  %@", cas)) }

        return lines
    }

    private var topLabel: String? {
        journal.tags.contains(where: { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "top" || normalized == "top期刊" || normalized == "中科院top"
        }) ? "TOP" : nil
    }

    private func latestPartition(schemes: Set<String>) -> JournalPartition? {
        matchingPartitions(schemes: schemes).first
    }

    private func matchingPartitions(schemes: Set<String>) -> [JournalPartition] {
        journal.metrics.partitions
            .filter { partition in
                schemes.contains { $0.caseInsensitiveCompare(partition.scheme) == .orderedSame }
            }
            .sorted { ($0.year ?? 0) > ($1.year ?? 0) }
    }

    private func compactAnnualLabel(_ partition: JournalPartition) -> String {
        if let year = partition.year {
            return "\(year) \(partition.value)"
        }
        return partition.value
    }

    private var primaryLabelSize: CGFloat {
        switch density {
        case .overview: 6.5
        case .matrix: 7.5
        case .library: 7
        }
    }

    private var primaryValueSize: CGFloat {
        switch density {
        case .overview: 9.5
        case .matrix: 13
        case .library: 11.5
        }
    }

    private var primarySpacing: CGFloat {
        switch density {
        case .overview: 4
        case .matrix: 5
        case .library: 8
        }
    }

    private var secondarySpacing: CGFloat {
        switch density {
        case .overview: 0
        case .matrix: 3
        case .library: 2
        }
    }

    private var secondaryFontSize: CGFloat {
        switch density {
        case .overview: 0
        case .matrix: 8.7
        case .library: 8
        }
    }
}
