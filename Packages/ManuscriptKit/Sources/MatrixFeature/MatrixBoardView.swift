import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import Observation
import SwiftUI

private struct MatrixCellKey: Hashable {
    let manuscriptID: ManuscriptID
    let journalID: JournalID
}

struct MatrixPresentationIndex {
    let projections: [ManuscriptID: ManuscriptProjection]
    let targetsByManuscript: [ManuscriptID: [TargetChoice]]
    private let targetsByCell: [MatrixCellKey: TargetChoice]
    private let eventsByCell: [MatrixCellKey: [SubmissionEvent]]
    let relationshipCounts: [ManuscriptID: Int]
    let journalsByID: [JournalID: Journal]
    let usedJournalIDs: Set<JournalID>

    init(board: BoardSnapshot) {
        projections = Dictionary(uniqueKeysWithValues: board.visibleManuscripts.map {
            ($0.id, board.manuscriptProjection(for: $0.id))
        })

        var groupedTargets: [ManuscriptID: [TargetChoice]] = [:]
        var cellTargets: [MatrixCellKey: TargetChoice] = [:]
        var usedJournals = Set<JournalID>()
        for target in board.targets {
            groupedTargets[target.manuscriptID, default: []].append(target)
            cellTargets[MatrixCellKey(manuscriptID: target.manuscriptID, journalID: target.journalID)] = target
            usedJournals.insert(target.journalID)
        }
        for manuscriptID in groupedTargets.keys {
            groupedTargets[manuscriptID]?.sort { $0.priority < $1.priority }
        }
        targetsByManuscript = groupedTargets
        targetsByCell = cellTargets

        var groupedEvents: [MatrixCellKey: [SubmissionEvent]] = [:]
        for event in board.submissionEvents {
            let key = MatrixCellKey(manuscriptID: event.manuscriptID, journalID: event.journalID)
            groupedEvents[key, default: []].append(event)
            if !event.isVoided {
                usedJournals.insert(event.journalID)
            }
        }
        for key in groupedEvents.keys {
            groupedEvents[key]?.sort {
                if $0.occurredAt == $1.occurredAt { return $0.recordedAt > $1.recordedAt }
                return $0.occurredAt > $1.occurredAt
            }
        }
        eventsByCell = groupedEvents

        var counts: [ManuscriptID: Int] = [:]
        for relationship in board.relationships {
            counts[relationship.firstManuscriptID, default: 0] += 1
            counts[relationship.secondManuscriptID, default: 0] += 1
        }
        relationshipCounts = counts
        journalsByID = Dictionary(uniqueKeysWithValues: board.journals.map { ($0.id, $0) })
        usedJournalIDs = usedJournals
    }

    func projection(for manuscriptID: ManuscriptID) -> ManuscriptProjection? {
        projections[manuscriptID]
    }

    func target(for manuscriptID: ManuscriptID, journalID: JournalID) -> TargetChoice? {
        targetsByCell[MatrixCellKey(manuscriptID: manuscriptID, journalID: journalID)]
    }

    func events(for manuscriptID: ManuscriptID, journalID: JournalID) -> [SubmissionEvent] {
        eventsByCell[MatrixCellKey(manuscriptID: manuscriptID, journalID: journalID)] ?? []
    }
}

@Observable
private final class MatrixHorizontalScrollCoordinator {
    var offset: CGFloat = 0
}

struct MatrixBoardView: View {
    let board: BoardSnapshot
    let presentation: MatrixPresentationIndex
    @ObservedObject var store: BoardCommandService
    let searchText: String
    let scope: MatrixScope
    let visibility: MatrixVisibilityOptions
    @Binding var density: MatrixDensity
    let onInspectManuscript: (ManuscriptID) -> Void

    @State private var scrollCoordinator = MatrixHorizontalScrollCoordinator()

    private var scopedManuscripts: [Manuscript] {
        board.visibleManuscripts.filter { manuscript in
            guard let projection = presentation.projection(for: manuscript.id) else { return false }
            guard scope.includes(projection) else { return false }
            if visibility.hidesIncompleteManuscripts, projection.situation == .incomplete { return false }
            if visibility.hidesAcceptedManuscripts, projection.situation == .accepted { return false }
            return true
        }
    }

    private var manuscripts: [Manuscript] {
        guard !searchText.isEmpty else { return scopedManuscripts }
        return scopedManuscripts.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.shortTitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var journals: [Journal] {
        let all = board.rankedJournals.filter { journal in
            !visibility.hidesUnusedJournals || presentation.usedJournalIDs.contains(journal.id)
        }
        guard !searchText.isEmpty else { return all }
        if !manuscripts.isEmpty { return all }
        return all.filter { $0.currentName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        GeometryReader { geometry in
            let scrollingViewportWidth = max(0, geometry.size.width - density.journalColumnWidth)
            let manuscriptContentWidth = CGFloat(manuscripts.count) * density.manuscriptColumnWidth
            let scrollingContentWidth = max(scrollingViewportWidth, manuscriptContentWidth)

            ScrollView(.vertical) {
                HStack(alignment: .top, spacing: 0) {
                    fixedJournalColumn
                        .frame(width: density.journalColumnWidth)
                        .background(MMColor.surface)
                        .zIndex(2)

                    ScrollView(.horizontal) {
                        scrollingManuscriptGrid(width: scrollingContentWidth)
                    }
                    .onScrollGeometryChange(for: CGFloat.self) { geometry in
                        max(0, geometry.contentOffset.x + geometry.contentInsets.leading)
                    } action: { _, newOffset in
                        scrollCoordinator.offset = newOffset
                    }
                    .frame(width: scrollingViewportWidth, height: matrixHeight)
                    .scrollIndicators(.visible)
                    .background(MMColor.canvas)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(MMColor.hairline)
                            .frame(width: 1)
                    }
                }
                .frame(height: matrixHeight, alignment: .top)
            }
            .overlay(alignment: .topLeading) {
                stickyMatrixHeader(
                    viewportWidth: scrollingViewportWidth,
                    contentWidth: scrollingContentWidth
                )
                .zIndex(20)
            }
            .scrollIndicators(.visible)
        }
        .background(MMColor.canvas)
        .simultaneousGesture(
            MagnifyGesture(minimumScaleDelta: 0.08)
                .onEnded { value in
                    if value.magnification < 0.86, density == .detailed {
                        density = .overview
                    } else if value.magnification > 1.14, density == .overview {
                        density = .detailed
                    }
                }
        )
        .animation(.snappy(duration: 0.3, extraBounce: 0.04), value: density)
        .animation(.snappy(duration: 0.25, extraBounce: 0.02), value: visibility)
    }

    private var matrixHeight: CGFloat {
        density.headerHeight + density.stagingHeight + CGFloat(journals.count) * density.rowHeight
    }

    private var fixedJournalColumn: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear
                .frame(width: density.journalColumnWidth, height: density.headerHeight)
            stagingHeaderCell

            ForEach(Array(journals.enumerated()), id: \.element.id) { index, journal in
                JournalIdentityCell(journal: journal, store: store, density: density)
                    .frame(width: density.journalColumnWidth, height: density.rowHeight)
                    .background(index.isMultiple(of: 2) ? MMColor.surface : MMColor.canvas)
                    .overlay(alignment: .bottom) {
                        Divider().overlay(MMColor.hairline.opacity(0.85))
                    }
            }
        }
        .frame(width: density.journalColumnWidth, alignment: .leading)
    }

    private func stickyMatrixHeader(viewportWidth: CGFloat, contentWidth: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            journalHeaderCell
                .frame(width: density.journalColumnWidth, height: density.headerHeight)

            MatrixScrollingHeaderViewport(
                coordinator: scrollCoordinator,
                viewportWidth: viewportWidth,
                height: density.headerHeight,
                content: manuscriptHeaderRow(width: contentWidth)
            )
            .offset(x: density.journalColumnWidth)

            Rectangle()
                .fill(MMColor.hairline)
                .frame(width: 1, height: density.headerHeight)
                .offset(x: density.journalColumnWidth - 1)
                .allowsHitTesting(false)
                .zIndex(30)
        }
        .frame(
            width: density.journalColumnWidth + viewportWidth,
            height: density.headerHeight,
            alignment: .topLeading
        )
        .background(MMColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MMColor.hairline)
                .frame(height: 1)
                .allowsHitTesting(false)
        }
    }

    private var journalHeaderCell: some View {
        Group {
            if density == .overview {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(MMColor.indigo)
                    Text(MMLocalization.format("期刊 · %d", journals.count))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MMColor.ink)
                }
                .padding(.horizontal, 14)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    MMSectionLabel("期刊顺位")
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text("排名")
                            .font(.system(size: 24, weight: .medium, design: .serif))
                        Text("\(journals.count)")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundStyle(MMColor.secondaryInk)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .frame(width: density.journalColumnWidth, height: density.headerHeight, alignment: .leading)
        .background(MMColor.surface)
        .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }
    }

    private var stagingHeaderCell: some View {
        Group {
            if density == .overview {
                HStack(spacing: 8) {
                    Circle().fill(MMColor.graphite).frame(width: 6, height: 6)
                    Circle().fill(MMColor.jade).frame(width: 6, height: 6)
                    Text("准备区")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.7)
                }
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9).fill(MMColor.elevated)
                        Image(systemName: "checklist")
                            .foregroundStyle(MMColor.secondaryInk)
                    }
                    .frame(width: 34, height: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("准备区")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(1.1)
                        Text("未完成 / 待发表")
                            .font(.system(size: 10))
                            .foregroundStyle(MMColor.secondaryInk)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
        .frame(width: density.journalColumnWidth, height: density.stagingHeight, alignment: .leading)
        .background(MMColor.surface.opacity(0.72))
        .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }
    }

    private func scrollingManuscriptGrid(width: CGFloat) -> some View {
        let manuscriptRightEdge = CGFloat(manuscripts.count) * density.manuscriptColumnWidth
        return LazyVStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(width: width, height: density.headerHeight)
            stagingManuscriptRow(width: width)

            ForEach(Array(journals.enumerated()), id: \.element.id) { index, journal in
                manuscriptJournalRow(journal, index: index, width: width)
            }
        }
        .frame(width: width, alignment: .leading)
        .overlay(alignment: .topLeading) {
            if !manuscripts.isEmpty {
                Rectangle()
                    .fill(MMColor.hairline)
                    .frame(width: 1, height: matrixHeight)
                    .offset(x: manuscriptRightEdge - 1)
                    .allowsHitTesting(false)
            }
        }
    }

    private func manuscriptHeaderRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(manuscripts) { manuscript in
                ManuscriptHeaderCard(
                    manuscript: manuscript,
                    projection: presentation.projection(for: manuscript.id) ?? board.manuscriptProjection(for: manuscript.id),
                    relationshipCount: presentation.relationshipCounts[manuscript.id, default: 0],
                    density: density,
                    action: { onInspectManuscript(manuscript.id) }
                )
                .frame(width: density.manuscriptColumnWidth, height: density.headerHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: density.headerHeight, alignment: .leading)
        .background(MMColor.surface)
        .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }
    }

    private func stagingManuscriptRow(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(manuscripts) { manuscript in
                StagingCell(
                    manuscript: manuscript,
                    projection: presentation.projection(for: manuscript.id) ?? board.manuscriptProjection(for: manuscript.id),
                    firstTarget: presentation.targetsByManuscript[manuscript.id]?.first,
                    firstTargetJournal: firstTargetJournal(for: manuscript.id),
                    density: density,
                    action: { onInspectManuscript(manuscript.id) }
                )
                .frame(width: density.manuscriptColumnWidth, height: density.stagingHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: density.stagingHeight, alignment: .leading)
        .background(MMColor.surface.opacity(0.45))
        .overlay(alignment: .bottom) { Divider().overlay(MMColor.hairline) }
    }

    private func manuscriptJournalRow(_ journal: Journal, index: Int, width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(manuscripts) { manuscript in
                MatrixCellView(
                    store: store,
                    manuscript: manuscript,
                    journal: journal,
                    projection: presentation.projection(for: manuscript.id) ?? board.manuscriptProjection(for: manuscript.id),
                    target: presentation.target(for: manuscript.id, journalID: journal.id),
                    events: presentation.events(for: manuscript.id, journalID: journal.id),
                    density: density,
                    onInspect: { onInspectManuscript(manuscript.id) }
                )
                .equatable()
                .frame(width: density.manuscriptColumnWidth, height: density.rowHeight)
            }
            Spacer(minLength: 0)
        }
        .frame(width: width, height: density.rowHeight, alignment: .leading)
        .background(index.isMultiple(of: 2) ? MMColor.surface.opacity(0.52) : MMColor.canvas)
        .overlay(alignment: .bottom) {
            Divider().overlay(MMColor.hairline.opacity(0.85))
        }
    }

    private func firstTargetJournal(for manuscriptID: ManuscriptID) -> Journal? {
        guard let target = presentation.targetsByManuscript[manuscriptID]?.first else { return nil }
        return presentation.journalsByID[target.journalID]
    }
}

private struct MatrixScrollingHeaderViewport<Content: View>: View {
    let coordinator: MatrixHorizontalScrollCoordinator
    let viewportWidth: CGFloat
    let height: CGFloat
    let content: Content

    var body: some View {
        content
            .offset(x: -coordinator.offset)
            .frame(width: viewportWidth, height: height, alignment: .topLeading)
            .clipped()
    }
}

private struct ManuscriptHeaderCard: View {
    let manuscript: Manuscript
    let projection: ManuscriptProjection
    let relationshipCount: Int
    let density: MatrixDensity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if density == .overview {
                    VStack(alignment: .leading, spacing: 0) {
                        Group {
                            if projection.status == .awaitingSubmission {
                                ReadinessProgressBar(readiness: projection.readiness, height: 4)
                            } else {
                                Capsule(style: .continuous)
                                    .fill(projection.status.color)
                            }
                        }
                            .frame(width: 46, height: 4)
                            .frame(maxWidth: .infinity, minHeight: 4, maxHeight: 4, alignment: .center)
                            .shadow(color: projection.status.color.opacity(0.2), radius: 3, y: 1)
                            .padding(.top, 7)
                        Text(manuscript.shortTitle)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(MMColor.ink)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 5)
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(alignment: .center) {
                            Circle().fill(projection.status.color).frame(width: 7, height: 7)
                            Text(projection.status.displayName.uppercased())
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .tracking(0.8)
                                .foregroundStyle(projection.status.color)
                            Spacer()
                            if relationshipCount > 0 {
                                Label("\(relationshipCount)", systemImage: "link")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(MMColor.secondaryInk)
                            }
                        }
                        Text(manuscript.shortTitle)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MMColor.ink)
                            .lineLimit(1)
                        Text(manuscript.title)
                            .font(.system(size: 10))
                            .foregroundStyle(MMColor.secondaryInk)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .padding(13)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: density == .overview ? .top : .topLeading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MMColor.surface)
        .overlay(alignment: .leading) { Divider().overlay(MMColor.hairline) }
    }
}

private struct JournalIdentityCell: View {
    let journal: Journal
    @ObservedObject var store: BoardCommandService
    let density: MatrixDensity
    @State private var showsInspector = false
    @State private var showsFullEditor = false

    var body: some View {
        Button {
            showsInspector = true
        } label: {
            Group {
                if density == .overview {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(format: "%02d", journal.rank))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(journal.rank <= 3 ? MMColor.indigo : MMColor.secondaryInk)
                                .frame(width: 22, alignment: .trailing)
                            JournalPublisherMark(journal: journal, style: .dot)
                                .frame(width: 8, height: 12)
                            Text(journal.overviewDisplayName)
                                .font(.system(size: 9.5, weight: .semibold))
                                .foregroundStyle(MMColor.ink)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, minHeight: 22, maxHeight: 22, alignment: .topLeading)
                        }

                        JournalMetricsSummary(journal: journal, density: .overview)
                            .padding(.leading, 46)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                } else {
                    HStack(alignment: .top, spacing: 13) {
                        VStack(spacing: 8) {
                            Text(String(format: "%02d", journal.rank))
                                .font(.system(size: 15, weight: .medium, design: .monospaced))
                                .foregroundStyle(journal.rank <= 3 ? MMColor.indigo : MMColor.secondaryInk)
                            JournalPublisherMark(journal: journal)
                        }
                        .frame(width: 42, alignment: .center)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(journal.currentName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MMColor.ink)
                                .lineLimit(2)

                            JournalMetricsSummary(journal: journal)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 17)
                    .padding(.vertical, 10)
                }
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: density == .overview ? .leading : .topLeading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(MMColor.surface.opacity(0.74))
        .popover(isPresented: $showsInspector, arrowEdge: .leading) {
            JournalInspectorPopover(
                journal: journal,
                store: store,
                onComplete: { showsInspector = false },
                onEditAll: {
                    showsInspector = false
                    showsFullEditor = true
                }
            )
        }
        .sheet(isPresented: $showsFullEditor) {
            JournalEditorSheet(store: store, journal: journal)
        }
    }
}

private struct JournalInspectorPopover: View {
    let journal: Journal
    @ObservedObject var store: BoardCommandService
    let onComplete: () -> Void
    let onEditAll: () -> Void

    @State private var newName: String
    @State private var rank: Int
    @State private var errorMessage: String?

    init(
        journal: Journal,
        store: BoardCommandService,
        onComplete: @escaping () -> Void,
        onEditAll: @escaping () -> Void
    ) {
        self.journal = journal
        self.store = store
        self.onComplete = onComplete
        self.onEditAll = onEditAll
        _newName = State(initialValue: journal.currentName)
        _rank = State(initialValue: journal.rank)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 4) {
                Text("期刊身份")
                    .font(.system(size: 15, weight: .semibold))
                Text("ID · \(journal.id.rawValue.uuidString)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(MMColor.secondaryInk)
                    .textSelection(.enabled)
            }

            Divider()

            VStack(alignment: .leading, spacing: 7) {
                MMSectionLabel("当前名称")
                TextField("Journal name", text: $newName)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 7) {
                MMSectionLabel("全局排名")
                Stepper(MMLocalization.format("第 %d 位", rank), value: $rank, in: 1...max(1, store.board.journals.count))
            }

            if journal.nameHistory.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    MMSectionLabel("名称历史")
                    ForEach(journal.nameHistory.sorted(by: { $0.effectiveFrom > $1.effectiveFrom })) { record in
                        HStack {
                            Text(record.name).lineLimit(1)
                            Spacer()
                            Text(MMDateText.absolute.string(from: record.effectiveFrom))
                                .foregroundStyle(MMColor.secondaryInk)
                        }
                        .font(.system(size: 10))
                    }
                }
            }

            Button {
                onEditAll()
            } label: {
                Label("编辑 IF、分区与完整信息…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MMColor.indigo)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(MMColor.vermilion)
            }

            HStack {
                Spacer()
                Button("取消") { onComplete() }
                Button("保存修改") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
        .background(MMColor.elevated)
    }

    private func save() {
        var commands: [BoardCommand] = []
        if newName.trimmingCharacters(in: .whitespacesAndNewlines) != journal.currentName {
            commands.append(
                .renameJournal(
                    journalID: journal.id,
                    newName: newName,
                    occurredAt: .now
                )
            )
        }
        if rank != journal.rank {
            commands.append(.moveJournal(journalID: journal.id, toRank: rank))
        }
        guard !commands.isEmpty else {
            onComplete()
            return
        }

        Task {
            do {
                try await store.execute(commands)
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StagingCell: View {
    let manuscript: Manuscript
    let projection: ManuscriptProjection
    let firstTarget: TargetChoice?
    let firstTargetJournal: Journal?
    let density: MatrixDensity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Group {
                if density == .overview {
                    CompactStagingIndicator(projection: projection)
                } else if projection.status == .awaitingSubmission {
                    let readiness = projection.readiness
                    VStack(spacing: 9) {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(readiness.displayName, systemImage: readiness.icon)
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .tracking(0.9)
                                    .foregroundStyle(readiness.color)
                                Text(!readiness.isComplete
                                     ? readiness.detailText
                                     : firstTargetJournal.map { MMLocalization.format("下一目标 · %@", $0.currentName) } ?? MMLocalization.string("尚未设置目标"))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(MMColor.secondaryInk)
                                    .lineLimit(2)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(readiness.color)
                        }

                        ReadinessProgressBar(readiness: readiness, height: 5)
                    }
                    .padding(11)
                    .background(readiness.wash.opacity(0.92), in: RoundedRectangle(cornerRadius: 11))
                    .overlay {
                        RoundedRectangle(cornerRadius: 11)
                            .stroke(readiness.color.opacity(0.42), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                } else if projection.status == .accepted {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.seal.fill")
                        Text("Accepted")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MMColor.jade)
                } else {
                    HStack(spacing: 7) {
                        Image(systemName: "paperplane.fill")
                        Text("正在投稿")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MMColor.secondaryInk.opacity(0.65))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .leading) { Divider().overlay(MMColor.hairline) }
    }
}

private struct CompactStagingIndicator: View {
    let projection: ManuscriptProjection

    var body: some View {
        Group {
            if projection.status == .awaitingSubmission {
                ReadinessProgressBar(readiness: projection.readiness, height: 8)
                    .frame(width: 42, height: 8)
            } else if projection.status == .accepted {
                Circle()
                    .fill(MMColor.jade)
                    .frame(width: 8, height: 8)
            } else {
                Circle()
                    .fill(MMColor.secondaryInk.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
        .transition(.scale(scale: 0.72).combined(with: .opacity))
    }
}

private struct ReadinessProgressBar: View {
    let readiness: ManuscriptReadiness
    let height: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(MMColor.graphite.opacity(0.2))
                Capsule(style: .continuous)
                    .fill(MMColor.jade)
                    .frame(width: max(height, geometry.size.width * readiness.progressFraction))
                    .shadow(color: MMColor.jade.opacity(0.2), radius: 3, y: 1)
            }
        }
        .frame(height: height)
        .accessibilityLabel(MMLocalization.format("准备进度：%@", readiness.displayName))
    }
}
