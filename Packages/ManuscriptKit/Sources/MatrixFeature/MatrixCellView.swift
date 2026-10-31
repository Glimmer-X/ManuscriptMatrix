import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct MatrixCellView: View, Equatable {
    @Environment(\.displayDate) private var displayDate
    @ObservedObject var store: BoardCommandService
    let manuscript: Manuscript
    let journal: Journal
    let projection: ManuscriptProjection
    let target: TargetChoice?
    let events: [SubmissionEvent]
    let density: MatrixDensity
    let onInspect: () -> Void

    @State private var showsActions = false

    private var latestTerminalEvent: SubmissionEvent? {
        events.first { $0.kind.endsLiveSubmission }
    }

    private var rejectionDecisionDays: Int? {
        guard let event = latestTerminalEvent else { return nil }
        return event.rejectionDecisionDays(in: events)
    }

    nonisolated static func == (lhs: MatrixCellView, rhs: MatrixCellView) -> Bool {
        lhs.manuscript == rhs.manuscript &&
            lhs.journal == rhs.journal &&
            lhs.projection == rhs.projection &&
            lhs.target == rhs.target &&
            lhs.events == rhs.events &&
            lhs.density == rhs.density
    }

    var body: some View {
        Button {
            showsActions = true
        } label: {
            Group {
                if density == .overview {
                    CompactMatrixMarker(
                        status: compactStatus,
                        color: compactColor,
                        icon: compactIcon,
                        elapsedText: compactElapsedText
                    )
                    .transition(.scale(scale: 0.74).combined(with: .opacity))
                } else if projection.activeJournalID == journal.id {
                    LiveSubmissionCard(
                        manuscript: manuscript,
                        projection: projection,
                        priorTerminalCount: events.filter { $0.kind.endsLiveSubmission }.count
                    )
                } else if let target {
                    TargetMarker(manuscript: manuscript, target: target)
                } else if let event = latestTerminalEvent {
                    HistoricalTrace(
                        event: event,
                        currentJournalName: journal.currentName,
                        decisionDays: rejectionDecisionDays
                    )
                } else {
                    EmptyMatrixCell()
                }
            }
            .padding(density == .overview ? 5 : 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(MMColor.hairline.opacity(0.72))
                .frame(width: 1)
                .allowsHitTesting(false)
        }
        .popover(isPresented: $showsActions, arrowEdge: .trailing) {
            CellActionPanel(
                store: store,
                manuscript: manuscript,
                journal: journal,
                projection: projection,
                target: target,
                events: events,
                onInspect: {
                    showsActions = false
                    onInspect()
                },
                onComplete: { showsActions = false }
            )
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var compactStatus: CompactMatrixMarker.Status {
        if projection.activeJournalID == journal.id { return .live }
        if target != nil { return .target }
        if latestTerminalEvent != nil { return .history }
        return .empty
    }

    private var compactColor: Color {
        if projection.activeJournalID == journal.id { return projection.status.color }
        if target != nil { return MMColor.jade }
        if let event = latestTerminalEvent { return event.kind.color }
        return MMColor.secondaryInk
    }

    private var compactIcon: String? {
        if projection.activeJournalID == journal.id { return projection.status.icon }
        if let event = latestTerminalEvent { return event.kind.icon }
        return nil
    }

    private var compactElapsedText: String? {
        if projection.activeJournalID == journal.id,
           let startedAt = projection.latestActionAt {
            return MMDateText.elapsed(from: startedAt, to: displayDate)
        }
        if let event = latestTerminalEvent {
            return MMDateText.elapsed(from: event.occurredAt, to: displayDate)
        }
        return nil
    }

    private var accessibilityLabel: String {
        if projection.activeJournalID == journal.id {
            let elapsed = projection.latestActionAt.map { ", \(MMDateText.elapsed(from: $0, to: displayDate)) elapsed" } ?? ""
            return "\(manuscript.shortTitle), \(projection.status.displayName), at \(journal.currentName)\(elapsed)"
        }
        if let target {
            return "\(manuscript.shortTitle), target priority \(target.priority), \(journal.currentName)"
        }
        if let event = latestTerminalEvent {
            let decisionDuration = rejectionDecisionDays.map { ", decision took \($0) days" } ?? ""
            return "\(manuscript.shortTitle), \(event.kind.displayName), \(journal.currentName), \(MMDateText.elapsed(from: event.occurredAt, to: displayDate)) ago\(decisionDuration)"
        }
        return "\(manuscript.shortTitle), \(journal.currentName), no record"
    }
}

private struct CompactMatrixMarker: View {
    enum Status {
        case live
        case target
        case history
        case empty
    }

    let status: Status
    let color: Color
    let icon: String?
    let elapsedText: String?

    @State private var hovering = false

    var body: some View {
        if status == .empty {
            Circle()
                .fill(Color.clear)
                .frame(width: 5, height: 5)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            interactiveMarker
                .scaleEffect(hovering ? 1.08 : 1)
                .animation(.snappy(duration: 0.2, extraBounce: 0.08), value: hovering)
                .onHover { hovering = $0 }
        }
    }

    @ViewBuilder
    private var interactiveMarker: some View {
        ZStack {
            switch status {
            case .live:
                elapsedBadge(backgroundOpacity: 0.22, borderOpacity: 0.72)
                    .shadow(color: color.opacity(hovering ? 0.36 : 0.16), radius: hovering ? 7 : 3, y: 1)

            case .target:
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.2))
                    .frame(width: 64, height: 22)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(color.opacity(0.9), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    }

            case .history:
                elapsedBadge(backgroundOpacity: 0.1, borderOpacity: 0.34)

            case .empty:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func elapsedBadge(backgroundOpacity: Double, borderOpacity: Double) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .bold))
            }
            Text(elapsedText ?? "—")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .frame(width: 66, height: 24)
        .background(color.opacity(backgroundOpacity), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(color.opacity(borderOpacity), lineWidth: 0.8)
        }
    }
}

private struct LiveSubmissionCard: View {
    @Environment(\.displayDate) private var displayDate
    let manuscript: Manuscript
    let projection: ManuscriptProjection
    let priorTerminalCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(projection.status.displayName.uppercased(), systemImage: projection.status.icon)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .tracking(0.7)
                        .foregroundStyle(projection.status.color)
                    Text(manuscript.shortTitle)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MMColor.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 3)
                if let start = projection.latestActionAt {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(MMDateText.elapsed(from: start, to: displayDate))
                            .font(.system(size: 21, weight: .medium, design: .rounded))
                            .foregroundStyle(projection.status.color)
                        Text("已过")
                            .font(.system(size: 8, weight: .semibold, design: .rounded))
                            .foregroundStyle(MMColor.secondaryInk)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack {
                Text("当前投稿")
                Spacer()
                if priorTerminalCount > 0 {
                    Text(MMLocalization.format("曾投稿 %d 次", priorTerminalCount))
                }
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(MMColor.secondaryInk)
        }
        .padding(11)
        .background(projection.status.wash, in: RoundedRectangle(cornerRadius: MMLayout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MMLayout.cardRadius)
                .stroke(projection.status.color.opacity(0.28), lineWidth: 0.8)
        }
        .shadow(color: projection.status.color.opacity(0.08), radius: 6, y: 2)
    }
}

private struct TargetMarker: View {
    let manuscript: Manuscript
    let target: TargetChoice

    var body: some View {
        HStack(spacing: 10) {
            Text(String(format: "%02d", target.priority))
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .foregroundStyle(MMColor.jade)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 4) {
                Text("目标顺位")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(MMColor.jade)
                Text(manuscript.shortTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MMColor.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(MMColor.jadeWash.opacity(0.55), in: RoundedRectangle(cornerRadius: MMLayout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: MMLayout.cardRadius)
                .stroke(MMColor.jade.opacity(0.62), style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
        }
    }
}

private struct HistoricalTrace: View {
    @Environment(\.displayDate) private var displayDate
    let event: SubmissionEvent
    let currentJournalName: String
    let decisionDays: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: event.kind.icon)
                    .foregroundStyle(event.kind.color)
                Text(event.kind.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(MMColor.ink)
                Spacer()
                Text(MMDateText.relativePast(from: event.occurredAt, to: displayDate))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(MMColor.secondaryInk)
            }
            if event.journalNameSnapshot != currentJournalName {
                Text(MMLocalization.format("当时名称：%@", event.journalNameSnapshot))
                    .font(.system(size: 9))
                    .foregroundStyle(MMColor.secondaryInk)
                    .lineLimit(1)
            } else {
                Text("历史记录")
                    .font(.system(size: 9))
                    .foregroundStyle(MMColor.secondaryInk)
            }
            if let decisionDays {
                Text(MMLocalization.format("决策历时 %d 天", decisionDays))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(event.kind.color)
                    .monospacedDigit()
            }
        }
        .padding(11)
        .background(MMColor.surface.opacity(0.68), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(event.kind.color.opacity(0.24), lineWidth: 0.8)
        }
    }
}

private struct EmptyMatrixCell: View {
    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MMColor.secondaryInk.opacity(0.14))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
