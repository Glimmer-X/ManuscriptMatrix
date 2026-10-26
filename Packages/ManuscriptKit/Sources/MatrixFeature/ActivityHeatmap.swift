import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct ActivityHeatmap: View {
    let board: BoardSnapshot
    var referenceDate: Date = .now

    @State private var hoveredDate: Date?

    private let calendar = Calendar.current
    private let columnCount = 10
    private let rowCount = 9
    private let cellGap: CGFloat = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("90 天活动")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.1)
                .foregroundStyle(Color.white.opacity(0.42))

            Grid(horizontalSpacing: cellGap, verticalSpacing: cellGap) {
                ForEach(0..<rowCount, id: \.self) { row in
                    GridRow {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let index = row * columnCount + column
                            dayCell(days[index])
                        }
                    }
                }
            }
            .frame(width: gridWidth, height: gridHeight)
            .overlay(alignment: .topLeading) {
                if let hoveredDate,
                   let index = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: hoveredDate) }) {
                    activityPopover(for: hoveredDate)
                        .position(x: gridWidth / 2, y: popoverY(for: index / columnCount))
                        .transition(
                            .asymmetric(
                                insertion: .scale(scale: 0.78).combined(with: .opacity),
                                removal: .scale(scale: 0.88).combined(with: .opacity)
                            )
                        )
                        .allowsHitTesting(false)
                        .zIndex(10)
                }
            }
            .animation(.spring(response: 0.2, dampingFraction: 0.76), value: hoveredDate)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var cellSize: CGFloat {
        (MMLayout.sidebarWidth - 40 - CGFloat(columnCount - 1) * cellGap) / CGFloat(columnCount)
    }

    private var gridWidth: CGFloat {
        CGFloat(columnCount) * cellSize + CGFloat(columnCount - 1) * cellGap
    }

    private var gridHeight: CGFloat {
        CGFloat(rowCount) * cellSize + CGFloat(rowCount - 1) * cellGap
    }

    private var days: [Date] {
        let today = calendar.startOfDay(for: referenceDate)
        let firstDay = calendar.date(byAdding: .day, value: -(columnCount * rowCount - 1), to: today) ?? today
        return (0..<(columnCount * rowCount)).compactMap {
            calendar.date(byAdding: .day, value: $0, to: firstDay)
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let activity = activity(on: date)
        let isHovered = hoveredDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
        return RoundedRectangle(cornerRadius: 2.5)
            .fill(activity.color)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5)
                    .stroke(
                        isHovered ? Color.white.opacity(0.9) : Color.white.opacity(activity.isEmpty ? 0.04 : 0.1),
                        lineWidth: isHovered ? 1.2 : 0.6
                    )
            }
            .scaleEffect(isHovered ? 1.18 : 1)
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(.spring(response: 0.18, dampingFraction: 0.76)) {
                    if inside {
                        hoveredDate = date
                    } else if let hoveredDate, calendar.isDate(hoveredDate, inSameDayAs: date) {
                        self.hoveredDate = nil
                    }
                }
            }
            .accessibilityLabel(activity.accessibilityText(for: date))
    }

    private func activityPopover(for date: Date) -> some View {
        let activity = activity(on: date)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(activity.accentColor).frame(width: 6, height: 6)
                Text(DayActivity.dateFormatter.string(from: date))
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
                Text("\(activity.total)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(activity.accentColor)
            }
            Text(activity.summaryText)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.68))
                .lineLimit(2)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(width: 176, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.13), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.4), radius: 13, y: 7)
        .foregroundStyle(Color.white)
    }

    private func popoverY(for row: Int) -> CGFloat {
        let cellCenter = CGFloat(row) * (cellSize + cellGap) + cellSize / 2
        return row < rowCount / 2
            ? min(gridHeight - 30, cellCenter + 42)
            : max(30, cellCenter - 42)
    }

    private func activity(on date: Date) -> DayActivity {
        let events = board.submissionEvents.filter {
            !$0.isVoided && calendar.isDate($0.occurredAt, inSameDayAs: date)
        }
        return DayActivity(events: events)
    }
}

private struct DayActivity {
    let submitted: Int
    let revisions: Int
    let rejected: Int
    let accepted: Int
    let withdrawn: Int

    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = MMLocalization.locale
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }

    init(events: [SubmissionEvent]) {
        submitted = events.filter { $0.kind == .submitted || $0.kind == .resubmitted }.count
        revisions = events.filter {
            $0.kind == .majorRevision || $0.kind == .minorRevision || $0.kind == .rejectAndResubmit
        }.count
        rejected = events.filter { $0.kind == .rejected }.count
        accepted = events.filter { $0.kind == .accepted }.count
        withdrawn = events.filter { $0.kind == .withdrawn }.count
    }

    var isEmpty: Bool { total == 0 }
    var total: Int { submitted + revisions + rejected + accepted + withdrawn }

    var accentColor: Color {
        if rejected > 0 { return MMColor.vermilion }
        if revisions > 0 { return MMColor.amber }
        if accepted > 0 { return MMColor.jade }
        if submitted > 0 { return MMColor.indigo }
        if withdrawn > 0 { return MMColor.graphite }
        return Color.white.opacity(0.42)
    }

    var color: Color {
        guard !isEmpty else { return Color.white.opacity(0.055) }
        return accentColor.opacity(min(1, 0.52 + Double(total) * 0.14))
    }

    var summaryText: String {
        guard !isEmpty else { return MMLocalization.string("这一天没有投稿事件") }
        var parts: [String] = []
        if submitted > 0 { parts.append("Submitted \(submitted)") }
        if revisions > 0 { parts.append("Revision \(revisions)") }
        if rejected > 0 { parts.append("Rejected \(rejected)") }
        if accepted > 0 { parts.append("Accepted \(accepted)") }
        if withdrawn > 0 { parts.append("Withdrawn \(withdrawn)") }
        return parts.joined(separator: " · ")
    }

    func accessibilityText(for date: Date) -> String {
        "\(Self.dateFormatter.string(from: date))：\(summaryText)"
    }
}
