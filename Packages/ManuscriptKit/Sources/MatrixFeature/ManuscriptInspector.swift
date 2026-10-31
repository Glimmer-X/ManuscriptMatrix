import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct ManuscriptInspector: View {
    @Environment(\.displayDate) private var displayDate
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let manuscript: Manuscript

    @State private var createsRelationship = false
    @State private var editedRelationship: ManuscriptRelationship?
    @State private var editsManuscript = false
    @State private var eventToVoid: SubmissionEvent?
    @State private var eventToEdit: SubmissionEvent?
    @State private var confirmsDeletion = false

    private var currentManuscript: Manuscript {
        store.board.manuscripts.first(where: { $0.id == manuscript.id }) ?? manuscript
    }

    private var projection: ManuscriptProjection {
        store.board.manuscriptProjection(for: manuscript.id)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                HStack(alignment: .top, spacing: 26) {
                    overview
                    timeline
                }
                .padding(26)
            }
        }
        .frame(width: 860, height: 640)
        .background(MMColor.canvas)
        .sheet(isPresented: $createsRelationship) {
            RelationshipEditorSheet(store: store, preferredFirstID: manuscript.id)
        }
        .sheet(item: $editedRelationship) { relationship in
            RelationshipEditorSheet(store: store, relationship: relationship)
        }
        .sheet(isPresented: $editsManuscript) {
            EditManuscriptSheet(store: store, manuscript: currentManuscript)
        }
        .sheet(item: $eventToVoid) { event in
            VoidEventSheet(store: store, event: event)
        }
        .sheet(item: $eventToEdit) { event in
            EditSubmissionEventSheet(store: store, event: event)
        }
        .confirmationDialog("永久删除稿件？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("永久删除", role: .destructive) { deleteManuscript() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("投稿历史、目标顺位和稿件关系都会被删除；如误操作，可在当前 App 会话中使用撤销。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(projection.status.wash)
                Image(systemName: projection.status.icon)
                    .font(.system(size: 23, weight: .medium))
                    .foregroundStyle(projection.status.color)
            }
            .frame(width: 50, height: 50)

            VStack(alignment: .leading, spacing: 5) {
                Text(currentManuscript.shortTitle)
                    .font(.system(size: 23, weight: .semibold))
                Text(currentManuscript.title)
                    .font(.system(size: 12))
                    .foregroundStyle(MMColor.secondaryInk)
                    .lineLimit(2)
                HStack(spacing: 7) {
                    MMPill(
                        projection.status.displayName,
                        foreground: projection.status.color,
                        background: projection.status.wash,
                        systemImage: projection.status.icon
                    )
                    MMPill(
                        currentManuscript.readiness.displayName,
                        foreground: currentManuscript.readiness.color,
                        background: currentManuscript.readiness.wash,
                        systemImage: currentManuscript.readiness.icon
                    )
                }
            }

            Spacer()

            Menu {
                Button("编辑稿件", systemImage: "pencil") { editsManuscript = true }
                Menu("准备阶段", systemImage: "chart.bar.fill") {
                    ForEach(ManuscriptReadiness.allCases, id: \.self) { stage in
                        Button {
                            setReadiness(stage)
                        } label: {
                            Label(
                                stage.displayName,
                                systemImage: currentManuscript.readiness == stage ? "checkmark" : stage.icon
                            )
                        }
                        .disabled(currentManuscript.readiness == stage)
                    }
                }
                Button(MMLocalization.string(currentManuscript.archivedAt == nil ? "归档" : "恢复"), systemImage: currentManuscript.archivedAt == nil ? "archivebox" : "arrow.uturn.backward") {
                    toggleArchive()
                }
                Divider()
                Button("永久删除…", systemImage: "trash", role: .destructive) { confirmsDeletion = true }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .background(MMColor.surface)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 22) {
            inspectorSection("当前位置") {
                if let journalID = projection.activeJournalID,
                   let journal = store.board.journals.first(where: { $0.id == journalID }) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(journal.currentName)
                            .font(.system(size: 14, weight: .semibold))
                        if let start = projection.latestActionAt {
                            Text("\(projection.status.displayName) \(MMDateText.elapsed(from: start, to: displayDate)) · \(MMDateText.absolute.string(from: start))")
                                .font(.system(size: 11))
                                .foregroundStyle(MMColor.secondaryInk)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(projection.isAccepted ? MMLocalization.string("Accepted — 当前无在投期刊") : currentManuscript.readiness.detailText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(MMColor.secondaryInk)
                        if !projection.isAccepted {
                            Text(MMLocalization.format("状态更新于 %@", MMDateText.absolute.string(from: currentManuscript.readinessUpdatedAt)))
                                .font(.system(size: 10))
                                .foregroundStyle(MMColor.secondaryInk.opacity(0.72))
                        }
                    }
                }
            }

            inspectorSection("目标顺位") {
                let targets = store.board.targets(for: manuscript.id)
                if targets.isEmpty {
                    Text("尚未设置后续目标。")
                        .foregroundStyle(MMColor.secondaryInk)
                } else {
                    ForEach(targets) { target in
                        if let journal = store.board.journals.first(where: { $0.id == target.journalID }) {
                            HStack(spacing: 9) {
                                Text("\(target.priority)")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundStyle(MMColor.jade)
                                    .frame(width: 24, height: 24)
                                    .background(MMColor.jadeWash, in: Circle())
                                Text(journal.currentName)
                                    .font(.system(size: 11, weight: .medium))
                                Spacer()
                                Button {
                                    moveTarget(target, by: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.plain)
                                .disabled(target.priority == 1)

                                Button {
                                    moveTarget(target, by: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.plain)
                                .disabled(target.priority == targets.count)

                                Button(role: .destructive) {
                                    removeTarget(target)
                                } label: {
                                    Image(systemName: "xmark")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            inspectorSection("稿件关系") {
                let relationships = store.board.relationships(for: manuscript.id)
                if relationships.isEmpty {
                    Text("尚未声明稿件关系。")
                        .foregroundStyle(MMColor.secondaryInk)
                } else {
                    ForEach(relationships) { relationship in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(otherTitle(for: relationship), systemImage: "link")
                                    .font(.system(size: 11, weight: .semibold))
                                Spacer()
                                Menu {
                                    Button("编辑", systemImage: "pencil") { editedRelationship = relationship }
                                    Button("移除", systemImage: "trash", role: .destructive) {
                                        removeRelationship(relationship)
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                            Text(relationship.statement)
                                .font(.system(size: 10))
                                .foregroundStyle(MMColor.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(11)
                        .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Button {
                    createsRelationship = true
                } label: {
                    Label("声明稿件关系", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(MMColor.indigo)
            }
        }
        .frame(width: 330, alignment: .topLeading)
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 13) {
            MMSectionLabel("投稿历史")
            let events = store.board.events(for: manuscript.id)
            if events.isEmpty {
                Text("尚无投稿事件。")
                    .font(.system(size: 11))
                    .foregroundStyle(MMColor.secondaryInk)
                    .padding(.top, 8)
            } else {
                ForEach(events) { event in
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            Circle().fill(event.kind.color.opacity(event.isVoided ? 0.04 : 0.12))
                            Image(systemName: event.isVoided ? "nosign" : event.kind.icon)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(event.isVoided ? MMColor.graphite : event.kind.color)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(event.kind.displayName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .strikethrough(event.isVoided)
                                if event.isVoided {
                                    MMPill("已纠正", foreground: MMColor.graphite, background: MMColor.canvas)
                                }
                                Spacer()
                                Text(MMDateText.relativePast(from: event.occurredAt, to: displayDate))
                                    .font(.system(size: 9, weight: .medium, design: .rounded))
                                    .foregroundStyle(MMColor.secondaryInk)
                            }
                            Text(event.journalNameSnapshot)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(MMColor.secondaryInk)
                            Text(MMDateText.absolute.string(from: event.occurredAt))
                                .font(.system(size: 9))
                                .foregroundStyle(MMColor.secondaryInk.opacity(0.72))
                            if let reason = event.voidReason {
                                Text(MMLocalization.format("纠正原因：%@", reason))
                                    .font(.system(size: 9))
                                    .foregroundStyle(MMColor.vermilion)
                            }
                            if !event.amendmentHistory.isEmpty {
                                Text(MMLocalization.format("已修正 %d 次 · 保留审计记录", event.amendmentHistory.count))
                                    .font(.system(size: 9))
                                    .foregroundStyle(MMColor.indigo)
                            }
                        }

                        if !event.isVoided {
                            Menu {
                                Button("编辑时间与备注…", systemImage: "calendar.badge.clock") {
                                    eventToEdit = event
                                }
                                Button("作废此事件…", systemImage: "nosign", role: .destructive) {
                                    eventToVoid = event
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 22, height: 22)
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }
                    }
                    .padding(12)
                    .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 11))
                    .opacity(event.isVoided ? 0.62 : 1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func inspectorSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            MMSectionLabel(title)
            content()
                .font(.system(size: 11))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func otherTitle(for relationship: ManuscriptRelationship) -> String {
        let otherID = relationship.firstManuscriptID == manuscript.id
            ? relationship.secondManuscriptID
            : relationship.firstManuscriptID
        return store.board.manuscripts.first(where: { $0.id == otherID })?.shortTitle ?? MMLocalization.string("相关稿件")
    }

    private func moveTarget(_ target: TargetChoice, by offset: Int) {
        let newPriority = target.priority + offset
        guard newPriority >= 1 else { return }
        Task {
            try? await store.execute(
                .setTarget(
                    manuscriptID: manuscript.id,
                    journalID: target.journalID,
                    priority: newPriority,
                    note: target.note
                )
            )
        }
    }

    private func removeTarget(_ target: TargetChoice) {
        Task {
            try? await store.execute(
                .removeTarget(manuscriptID: manuscript.id, journalID: target.journalID)
            )
        }
    }

    private func removeRelationship(_ relationship: ManuscriptRelationship) {
        Task {
            try? await store.execute(.removeRelationship(relationshipID: relationship.id))
        }
    }

    private func toggleArchive() {
        Task {
            try? await store.execute(
                .setManuscriptArchived(
                    manuscriptID: manuscript.id,
                    archived: currentManuscript.archivedAt == nil,
                    occurredAt: .now
                )
            )
        }
    }

    private func deleteManuscript() {
        Task {
            do {
                try await store.execute(
                    .deleteManuscript(manuscriptID: manuscript.id, permanently: true)
                )
                dismiss()
            } catch {
                // The inspector remains open so the user can retry or cancel.
            }
        }
    }

    private func setReadiness(_ stage: ManuscriptReadiness) {
        Task {
            try? await store.execute(
                .setManuscriptReadiness(
                    manuscriptID: manuscript.id,
                    readiness: stage,
                    occurredAt: .now
                )
            )
        }
    }
}
