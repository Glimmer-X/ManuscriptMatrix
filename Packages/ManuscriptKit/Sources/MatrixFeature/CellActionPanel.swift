import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct CellActionPanel: View {
    @Environment(\.displayDate) private var displayDate
    @ObservedObject var store: BoardCommandService
    let manuscript: Manuscript
    let journal: Journal
    let projection: ManuscriptProjection
    let target: TargetChoice?
    let events: [SubmissionEvent]
    let onInspect: () -> Void
    let onComplete: () -> Void

    @State private var pendingEvent: SubmissionEventKind?
    @State private var errorMessage: String?

    private var isLive: Bool { projection.activeJournalID == journal.id }
    private var rejectionDecisionDays: Int? {
        guard let rejection = events.first(where: { $0.kind.endsLiveSubmission }),
              rejection.kind == .rejected else { return nil }
        return rejection.rejectionDecisionDays(in: events)
    }
    private var latestRevisionEvent: SubmissionEvent? {
        guard isLive,
              let event = projection.latestEvent,
              event.journalID == journal.id,
              event.kind == .majorRevision || event.kind == .minorRevision || event.kind == .rejectAndResubmit
        else { return nil }
        return event
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(manuscript.shortTitle)
                    .font(.system(size: 14, weight: .semibold))
                Text(journal.currentName)
                    .font(.system(size: 11))
                    .foregroundStyle(MMColor.secondaryInk)
                    .lineLimit(2)
            }
            .padding(15)

            Divider()

            if let rejectionDecisionDays {
                HStack(spacing: 10) {
                    Text("决策历时")
                        .foregroundStyle(MMColor.secondaryInk)
                    Spacer()
                    Text(MMLocalization.format("%d 天", rejectionDecisionDays))
                        .fontWeight(.semibold)
                        .foregroundStyle(MMColor.vermilion)
                        .monospacedDigit()
                }
                .font(.system(size: 11))
                .padding(14)
                Divider()
            }

            if let revision = latestRevisionEvent,
               let submission = revision.previousSubmissionEvent(in: events) {
                revisionTiming(submission: submission, revision: revision)
                Divider()
            }

            if isLive {
                liveActions
            } else {
                planningActions
            }

            if !events.isEmpty {
                Divider()
                Button {
                    onInspect()
                } label: {
                    Label("打开稿件详情", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(14)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(MMColor.vermilion)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 292)
        .background(MMColor.elevated)
        .sheet(
            isPresented: Binding(
                get: { pendingEvent != nil },
                set: { if !$0 { pendingEvent = nil } }
            )
        ) {
            if let kind = pendingEvent {
                RecordSubmissionEventSheet(
                    store: store,
                    manuscript: manuscript,
                    journal: journal,
                    kind: kind,
                    onComplete: {
                        pendingEvent = nil
                        onComplete()
                    }
                )
            }
        }
    }

    private func revisionTiming(submission: SubmissionEvent, revision: SubmissionEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            timingRow("上次投稿", date: submission.occurredAt)
            timingRow("返修更新", date: revision.occurredAt)
            HStack {
                Text("决策历时")
                    .foregroundStyle(MMColor.secondaryInk)
                Spacer()
                Text(MMLocalization.format("%d 天", submission.occurredAt.wholeDays(to: revision.occurredAt)))
                    .fontWeight(.semibold)
                    .foregroundStyle(MMColor.amber)
                    .monospacedDigit()
            }
        }
        .font(.system(size: 11))
        .padding(14)
    }

    private func timingRow(_ label: String, date: Date) -> some View {
        HStack(spacing: 8) {
            Text(MMLocalization.string(label))
                .foregroundStyle(MMColor.secondaryInk)
            Spacer(minLength: 6)
            Text("\(MMDateText.absolute.string(from: date)) · \(MMDateText.relativePast(from: date, to: displayDate))")
                .foregroundStyle(MMColor.ink)
                .monospacedDigit()
        }
    }

    private var planningActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            MMSectionLabel(target == nil ? "设置此位置" : "目标计划")

            HStack(spacing: 7) {
                ForEach(1...3, id: \.self) { priority in
                    Button {
                        setTarget(priority)
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(priority)")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text("顺位")
                                .font(.system(size: 8, weight: .medium))
                        }
                        .foregroundStyle(target?.priority == priority ? Color.white : MMColor.jade)
                        .frame(maxWidth: .infinity, minHeight: 45)
                        .background(target?.priority == priority ? MMColor.jade : MMColor.jadeWash, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                }
            }

            if target != nil {
                Button(role: .destructive) {
                    run(.removeTarget(manuscriptID: manuscript.id, journalID: journal.id))
                } label: {
                    Label("从目标计划移除", systemImage: "xmark")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
            }

            Divider()

            Button {
                pendingEvent = .submitted
            } label: {
                Label("记录为 Submitted", systemImage: "paperplane.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(MMColor.indigo, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
            .disabled(projection.activeJournalID != nil || projection.isAccepted)
        }
        .padding(14)
    }

    private var liveActions: some View {
        VStack(alignment: .leading, spacing: 11) {
            MMSectionLabel("记录状态或决定")
            eventButton(.majorRevision)
            eventButton(.minorRevision)
            eventButton(.rejectAndResubmit)
            eventButton(.resubmitted)
            Divider()
            eventButton(.accepted)
            eventButton(.rejected)
            eventButton(.withdrawn)
        }
        .padding(14)
    }

    private func eventButton(_ kind: SubmissionEventKind) -> some View {
        Button {
            pendingEvent = kind
        } label: {
            HStack(spacing: 9) {
                Image(systemName: kind.icon)
                    .foregroundStyle(kind.color)
                    .frame(width: 17)
                Text(kind.displayName)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MMColor.secondaryInk.opacity(0.5))
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(MMColor.ink)
        }
        .buttonStyle(.plain)
    }

    private func setTarget(_ priority: Int) {
        run(
            .setTarget(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                priority: priority,
                note: nil
            )
        )
    }

    private func run(_ command: BoardCommand) {
        Task {
            do {
                try await store.execute(command)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
