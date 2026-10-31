import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct ManuscriptLibraryView: View {
    @ObservedObject var store: BoardCommandService
    let searchText: String
    let onInspect: (ManuscriptID) -> Void

    @State private var showsArchived = false
    @State private var deletionCandidate: Manuscript?

    private var manuscripts: [Manuscript] {
        store.board.manuscripts
            .filter { showsArchived ? $0.archivedAt != nil : $0.archivedAt == nil }
            .filter {
                searchText.isEmpty ||
                    $0.shortTitle.localizedCaseInsensitiveContains(searchText) ||
                    $0.title.localizedCaseInsensitiveContains(searchText) ||
                    $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(MMLocalization.string(showsArchived ? "已归档稿件" : "活跃稿件"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MMColor.secondaryInk)
                Spacer()
                Toggle("显示已归档", isOn: $showsArchived)
                    .toggleStyle(.switch)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(MMColor.surface.opacity(0.55))
            .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }

            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 14)],
                    alignment: .leading,
                    spacing: 14
                ) {
                    ForEach(manuscripts) { manuscript in
                        ManuscriptLibraryCard(
                            board: store.board,
                            manuscript: manuscript,
                            onOpen: { onInspect(manuscript.id) },
                            onArchive: { toggleArchive(manuscript) },
                            onDelete: { deletionCandidate = manuscript }
                        )
                    }
                }
                .padding(24)
            }
        }
        .background(MMColor.canvas)
        .confirmationDialog(
            "永久删除稿件？",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) { deleteCandidate() }
            Button("取消", role: .cancel) { deletionCandidate = nil }
        } message: {
            Text("该稿件的投稿历史、目标顺位和关系记录都会被删除；如误操作，可在当前 App 会话中使用撤销。")
        }
    }

    private func toggleArchive(_ manuscript: Manuscript) {
        Task {
            try? await store.execute(
                .setManuscriptArchived(
                    manuscriptID: manuscript.id,
                    archived: manuscript.archivedAt == nil,
                    occurredAt: .now
                )
            )
        }
    }

    private func deleteCandidate() {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        Task {
            try? await store.execute(
                .deleteManuscript(manuscriptID: candidate.id, permanently: true)
            )
        }
    }
}

private struct ManuscriptLibraryCard: View {
    @Environment(\.displayDate) private var displayDate
    let board: BoardSnapshot
    let manuscript: Manuscript
    let onOpen: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    private var projection: ManuscriptProjection {
        board.manuscriptProjection(for: manuscript.id)
    }

    private var activeJournal: Journal? {
        guard let journalID = projection.activeJournalID else { return nil }
        return board.journals.first { $0.id == journalID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
                HStack {
                    MMPill(
                        manuscript.archivedAt == nil ? projection.status.displayName : MMLocalization.string("已归档"),
                        foreground: manuscript.archivedAt == nil ? projection.status.color : MMColor.graphite,
                        background: manuscript.archivedAt == nil ? projection.status.wash : MMColor.surface,
                        systemImage: manuscript.archivedAt == nil ? projection.status.icon : "archivebox.fill"
                    )
                    Spacer()
                    Menu {
                        Button(MMLocalization.string(manuscript.archivedAt == nil ? "归档" : "恢复"), systemImage: manuscript.archivedAt == nil ? "archivebox" : "arrow.uturn.backward") {
                            onArchive()
                        }
                        Divider()
                        Button("永久删除…", systemImage: "trash", role: .destructive) { onDelete() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 24, height: 24)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(manuscript.shortTitle)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(MMColor.ink)
                    Text(manuscript.title)
                        .font(.system(size: 11))
                        .foregroundStyle(MMColor.secondaryInk)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(activeJournal?.currentName ?? firstTargetText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(MMColor.ink)
                            .lineLimit(1)
                        Text(MMLocalization.string(activeJournal == nil ? "下一目标" : "当前期刊"))
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .tracking(0.8)
                            .foregroundStyle(MMColor.secondaryInk)
                    }
                    Spacer()
                    if activeJournal != nil, let start = projection.latestActionAt {
                        Text(MMDateText.elapsed(from: start, to: displayDate))
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                            .foregroundStyle(projection.status.color)
                    }
                }

                HStack(spacing: 12) {
                    Label(MMLocalization.format("%d 个目标", board.targets(for: manuscript.id).count), systemImage: "scope")
                    Label(MMLocalization.format("%d 个关系", board.relationships(for: manuscript.id).count), systemImage: "link")
                    Spacer()
                }
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(MMColor.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay {
            RoundedRectangle(cornerRadius: 15)
                .stroke(MMColor.hairline, lineWidth: 0.8)
        }
        .contentShape(RoundedRectangle(cornerRadius: 15))
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
    }

    private var firstTargetText: String {
        guard let target = board.targets(for: manuscript.id).first,
              let journal = board.journals.first(where: { $0.id == target.journalID }) else {
            return MMLocalization.string("尚未设置目标")
        }
        return journal.currentName
    }
}

struct JournalLibraryView: View {
    @ObservedObject var store: BoardCommandService
    let searchText: String

    @State private var showsArchived = false
    @State private var editedJournal: Journal?
    @State private var deletionCandidate: Journal?

    private var journals: [Journal] {
        store.board.journals
            .filter { showsArchived ? $0.archivedAt != nil : $0.archivedAt == nil }
            .filter {
                searchText.isEmpty ||
                    $0.currentName.localizedCaseInsensitiveContains(searchText) ||
                    ($0.metrics.category?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted { $0.rank < $1.rank }
    }

    var body: some View {
        VStack(spacing: 0) {
            journalTableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(journals) { journal in
                        JournalLibraryRow(
                            board: store.board,
                            journal: journal,
                            onEdit: { editedJournal = journal },
                            onArchive: { toggleArchive(journal) },
                            onDelete: { deletionCandidate = journal }
                        )
                        Divider().overlay(MMColor.hairline)
                    }
                }
            }
        }
        .background(MMColor.canvas)
        .sheet(item: $editedJournal) { journal in
            JournalEditorSheet(store: store, journal: journal)
        }
        .confirmationDialog(
            "永久删除期刊？",
            isPresented: Binding(
                get: { deletionCandidate != nil },
                set: { if !$0 { deletionCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("永久删除", role: .destructive) { deleteCandidate() }
            Button("取消", role: .cancel) { deletionCandidate = nil }
        } message: {
            Text("该期刊关联的投稿事件和所有稿件目标都会被删除；如误操作，可在当前 App 会话中使用撤销。")
        }
    }

    private var journalTableHeader: some View {
        HStack(spacing: 0) {
            Text("排名").frame(width: 72, alignment: .leading)
            Text("品牌").frame(width: 56, alignment: .leading)
            Text("期刊").frame(maxWidth: .infinity, alignment: .leading)
            Text("IF 与分区").frame(width: 230, alignment: .leading)
            Text("决定周期").frame(width: 110, alignment: .leading)
            Text("使用情况").frame(width: 120, alignment: .leading)
            Toggle("已归档", isOn: $showsArchived)
                .toggleStyle(.switch)
                .frame(width: 100)
        }
        .font(.system(size: 9, weight: .bold, design: .rounded))
        .tracking(0.9)
        .foregroundStyle(MMColor.secondaryInk)
        .padding(.horizontal, 24)
        .frame(height: 48)
        .background(MMColor.surface)
        .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }
    }

    private func toggleArchive(_ journal: Journal) {
        Task {
            try? await store.execute(
                .setJournalArchived(
                    journalID: journal.id,
                    archived: journal.archivedAt == nil,
                    occurredAt: .now
                )
            )
        }
    }

    private func deleteCandidate() {
        guard let candidate = deletionCandidate else { return }
        deletionCandidate = nil
        Task {
            try? await store.execute(.deleteJournal(journalID: candidate.id, permanently: true))
        }
    }
}

private struct JournalLibraryRow: View {
    let board: BoardSnapshot
    let journal: Journal
    let onEdit: () -> Void
    let onArchive: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
                Text(journal.archivedAt == nil ? String(format: "%02d", journal.rank) : "—")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(MMColor.indigo)
                    .frame(width: 72, alignment: .leading)

                JournalPublisherMark(journal: journal)
                    .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(journal.currentName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(MMColor.ink)
                        .lineLimit(1)
                    Text(journal.metrics.category ?? journal.tags.joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(MMColor.secondaryInk)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                JournalMetricsSummary(journal: journal, density: .library)
                .frame(width: 230, alignment: .leading)

                Text(journal.metrics.averageDecisionDays.map { "~\($0)d" } ?? "—")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(MMLocalization.format("%d 个在投", activeCount))
                    Text(MMLocalization.format("%d 个目标", targetCount))
                        .foregroundStyle(MMColor.secondaryInk)
                }
                .font(.system(size: 9, weight: .medium))
                .frame(width: 120, alignment: .leading)

                Menu {
                    Button("编辑", systemImage: "pencil") { onEdit() }
                    Button(MMLocalization.string(journal.archivedAt == nil ? "归档" : "恢复"), systemImage: journal.archivedAt == nil ? "archivebox" : "arrow.uturn.backward") {
                        onArchive()
                    }
                    Divider()
                    Button("永久删除…", systemImage: "trash", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 30, height: 30)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(width: 100)
        }
        .padding(.horizontal, 24)
        .frame(height: 76)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .accessibilityAddTraits(.isButton)
        .background(MMColor.surface.opacity(0.45))
    }

    private var activeCount: Int {
        board.visibleManuscripts.filter {
            board.manuscriptProjection(for: $0.id).activeJournalID == journal.id
        }.count
    }

    private var targetCount: Int {
        board.targets.filter { $0.journalID == journal.id }.count
    }
}

struct RelationshipManagementView: View {
    @ObservedObject var store: BoardCommandService
    let searchText: String

    @State private var editedRelationship: ManuscriptRelationship?
    @State private var createsRelationship = false

    private var relationships: [ManuscriptRelationship] {
        store.board.relationships
            .filter { relationship in
                guard !searchText.isEmpty else { return true }
                return relationship.statement.localizedCaseInsensitiveContains(searchText) ||
                    title(for: relationship.firstManuscriptID).localizedCaseInsensitiveContains(searchText) ||
                    title(for: relationship.secondManuscriptID).localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(MMLocalization.format("已声明 %d 个稿件关系", relationships.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MMColor.secondaryInk)
                Spacer()
                Button {
                    createsRelationship = true
                } label: {
                    Label("声明稿件关系", systemImage: "plus")
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(MMColor.surface.opacity(0.55))
            .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }

            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(relationships) { relationship in
                        RelationshipCard(
                            relationship: relationship,
                            firstTitle: title(for: relationship.firstManuscriptID),
                            secondTitle: title(for: relationship.secondManuscriptID),
                            onEdit: { editedRelationship = relationship },
                            onRemove: { remove(relationship) }
                        )
                    }
                }
                .padding(24)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
        }
        .background(MMColor.canvas)
        .sheet(isPresented: $createsRelationship) {
            RelationshipEditorSheet(store: store)
        }
        .sheet(item: $editedRelationship) { relationship in
            RelationshipEditorSheet(store: store, relationship: relationship)
        }
    }

    private func title(for manuscriptID: ManuscriptID) -> String {
        store.board.manuscripts.first(where: { $0.id == manuscriptID })?.shortTitle ?? MMLocalization.string("未知稿件")
    }

    private func remove(_ relationship: ManuscriptRelationship) {
        Task {
            try? await store.execute(.removeRelationship(relationshipID: relationship.id))
        }
    }
}

private struct RelationshipCard: View {
    @Environment(\.displayDate) private var displayDate
    let relationship: ManuscriptRelationship
    let firstTitle: String
    let secondTitle: String
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 13) {
                manuscriptToken(firstTitle)
                Image(systemName: directionIcon)
                    .foregroundStyle(MMColor.indigo)
                manuscriptToken(secondTitle)
                Spacer()
                Menu {
                    Button("编辑", systemImage: "pencil") { onEdit() }
                    Button("移除", systemImage: "trash", role: .destructive) { onRemove() }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 28, height: 28)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            Text(relationship.statement)
                .font(.system(size: 12))
                .foregroundStyle(MMColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(MMLocalization.format("更新于 %@", MMDateText.relativePast(from: relationship.updatedAt, to: displayDate)))
                .font(.system(size: 9))
                .foregroundStyle(MMColor.secondaryInk)
        }
        .padding(18)
        .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 15))
        .overlay { RoundedRectangle(cornerRadius: 15).stroke(MMColor.hairline) }
    }

    private func manuscriptToken(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MMColor.indigo)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(MMColor.indigoWash, in: RoundedRectangle(cornerRadius: 8))
    }

    private var directionIcon: String {
        switch relationship.direction {
        case .undirected: "arrow.left.arrow.right"
        case .firstToSecond: "arrow.right"
        case .secondToFirst: "arrow.left"
        }
    }
}

struct ActivityTimelineView: View {
    @ObservedObject var store: BoardCommandService
    let searchText: String
    let onInspect: (ManuscriptID) -> Void

    @State private var eventToVoid: SubmissionEvent?
    @State private var eventToEdit: SubmissionEvent?
    @State private var showsVoided = true

    private var events: [SubmissionEvent] {
        store.board.submissionEvents
            .filter { showsVoided || !$0.isVoided }
            .filter { event in
                guard !searchText.isEmpty else { return true }
                return event.journalNameSnapshot.localizedCaseInsensitiveContains(searchText) ||
                    manuscriptTitle(event.manuscriptID).localizedCaseInsensitiveContains(searchText) ||
                    event.kind.displayName.localizedCaseInsensitiveContains(searchText)
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(MMLocalization.format("共 %d 条投稿事件", events.count))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MMColor.secondaryInk)
                Spacer()
                Toggle("显示已纠正事件", isOn: $showsVoided)
                    .toggleStyle(.switch)
                    .font(.system(size: 10))
            }
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(MMColor.surface.opacity(0.55))
            .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(events) { event in
                        ActivityRow(
                            event: event,
                            manuscriptTitle: manuscriptTitle(event.manuscriptID),
                            onOpen: { onInspect(event.manuscriptID) },
                            onEdit: { eventToEdit = event },
                            onCorrect: { eventToVoid = event }
                        )
                        Divider().overlay(MMColor.hairline)
                    }
                }
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .background(MMColor.canvas)
        .sheet(item: $eventToVoid) { event in
            VoidEventSheet(store: store, event: event)
        }
        .sheet(item: $eventToEdit) { event in
            EditSubmissionEventSheet(store: store, event: event)
        }
    }

    private func manuscriptTitle(_ id: ManuscriptID) -> String {
        store.board.manuscripts.first(where: { $0.id == id })?.shortTitle ?? MMLocalization.string("未知稿件")
    }
}

private struct ActivityRow: View {
    @Environment(\.displayDate) private var displayDate
    let event: SubmissionEvent
    let manuscriptTitle: String
    let onOpen: () -> Void
    let onEdit: () -> Void
    let onCorrect: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
                ZStack {
                    Circle().fill(event.kind.color.opacity(event.isVoided ? 0.05 : 0.13))
                    Image(systemName: event.isVoided ? "nosign" : event.kind.icon)
                        .foregroundStyle(event.isVoided ? MMColor.graphite : event.kind.color)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(event.kind.displayName)
                            .font(.system(size: 12, weight: .semibold))
                        if event.isVoided {
                            MMPill("已纠正", foreground: MMColor.graphite, background: MMColor.surface)
                        }
                    }
                    Text("\(manuscriptTitle) · \(event.journalNameSnapshot)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(MMColor.secondaryInk)
                    if let note = event.note, !note.isEmpty {
                        Text(note).font(.system(size: 10)).foregroundStyle(MMColor.secondaryInk)
                    }
                    if let reason = event.voidReason {
                        Text(MMLocalization.format("纠正原因：%@", reason))
                            .font(.system(size: 9))
                            .foregroundStyle(MMColor.vermilion)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(MMDateText.absolute.string(from: event.occurredAt))
                        .font(.system(size: 10, weight: .medium))
                    Text(MMDateText.relativePast(from: event.occurredAt, to: displayDate))
                        .font(.system(size: 9))
                        .foregroundStyle(MMColor.secondaryInk)
                    if !event.isVoided {
                        Menu {
                            Button("编辑时间与备注…", systemImage: "calendar.badge.clock", action: onEdit)
                            Button("作废此事件…", systemImage: "nosign", role: .destructive, action: onCorrect)
                        } label: {
                            Label("管理", systemImage: "ellipsis")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .opacity(event.isVoided ? 0.62 : 1)
    }
}
