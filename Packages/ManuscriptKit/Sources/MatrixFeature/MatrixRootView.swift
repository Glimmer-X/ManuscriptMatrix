import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI
import UniformTypeIdentifiers

public struct MatrixRootView: View {
    private let store: BoardCommandService

    public init(store: BoardCommandService) {
        self.store = store
    }

    public var body: some View {
        DisplayDateScope {
            MatrixContentView(store: store)
        }
    }
}

private struct MatrixContentView: View {
    @Environment(\.displayDate) private var displayDate
    @ObservedObject private var store: BoardCommandService
    @State private var searchText = ""
    @State private var addSheet: AddSheet?
    @State private var inspectedManuscriptID: ManuscriptID?
    @State private var selectedSection: AppSection = .matrix
    @State private var matrixScope: MatrixScope = .all
    @State private var showsExporter = false
    @State private var showsImporter = false
    @State private var exportDocument = BoardArchiveDocument()
    @State private var pendingImportData: Data?
    @State private var archiveErrorMessage: String?
    @AppStorage("matrix.semanticDensity") private var matrixDensityRawValue = MatrixDensity.detailed.rawValue
    @AppStorage("matrix.hideUnusedJournals") private var hidesUnusedJournals = false
    @AppStorage("matrix.hideIncompleteManuscripts") private var hidesIncompleteManuscripts = false
    @AppStorage("matrix.hideAcceptedManuscripts") private var hidesAcceptedManuscripts = false

    private enum AddSheet: String, Identifiable {
        case manuscript
        case journal
        var id: String { rawValue }
    }

    init(store: BoardCommandService) {
        self.store = store
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: MMLayout.sidebarWidth)

            VStack(spacing: 0) {
                toolbar
                Divider().overlay(MMColor.hairline)

                if !store.isLoaded {
                    ProgressView("正在打开投稿面板…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.lastErrorMessage {
                    ContentUnavailableView(
                        "无法打开投稿面板",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.board.journals.isEmpty || store.board.manuscripts.isEmpty {
                    emptyState
                } else {
                    sectionContent
                }
            }
            .background(MMColor.canvas)
        }
        .frame(minWidth: 1_120, minHeight: 720)
        .background(MMColor.canvas)
        .sheet(item: $addSheet) { sheet in
            switch sheet {
            case .manuscript:
                AddManuscriptSheet(store: store)
            case .journal:
                AddJournalSheet(store: store)
            }
        }
        .sheet(
            isPresented: Binding(
                get: { inspectedManuscriptID != nil },
                set: { if !$0 { inspectedManuscriptID = nil } }
            )
        ) {
            if let id = inspectedManuscriptID,
               let manuscript = store.board.manuscripts.first(where: { $0.id == id }) {
                ManuscriptInspector(store: store, manuscript: manuscript)
            }
        }
        .fileExporter(
            isPresented: $showsExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Manuscript-Matrix-Backup"
        ) { result in
            if case let .failure(error) = result {
                archiveErrorMessage = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showsImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleImportSelection(result)
        }
        .confirmationDialog(
            "用此备份替换当前面板？",
            isPresented: Binding(
                get: { pendingImportData != nil },
                set: { if !$0 { pendingImportData = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("导入并替换", role: .destructive) { importPendingArchive() }
            Button("取消", role: .cancel) { pendingImportData = nil }
        } message: {
            Text("文件会先经过完整性校验；本次 App 会话中可以撤销此次替换。")
        }
        .alert(
            "备份操作失败",
            isPresented: Binding(
                get: { archiveErrorMessage != nil },
                set: { if !$0 { archiveErrorMessage = nil } }
            )
        ) {
            Button("好", role: .cancel) { archiveErrorMessage = nil }
        } message: {
            Text(archiveErrorMessage ?? MMLocalization.string("未知错误"))
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .matrix:
            MatrixBoardView(
                board: store.board,
                presentation: MatrixPresentationIndex(board: store.board),
                store: store,
                searchText: searchText,
                scope: matrixScope,
                visibility: matrixVisibility,
                density: matrixDensityBinding,
                onInspectManuscript: { inspectedManuscriptID = $0 }
            )
        case .manuscripts:
            ManuscriptLibraryView(
                store: store,
                searchText: searchText,
                onInspect: { inspectedManuscriptID = $0 }
            )
        case .journals:
            JournalLibraryView(store: store, searchText: searchText)
        case .relationships:
            RelationshipManagementView(store: store, searchText: searchText)
        case .activity:
            ActivityTimelineView(
                store: store,
                searchText: searchText,
                onInspect: { inspectedManuscriptID = $0 }
            )
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(Color.white.opacity(0.11))
                    Image(systemName: "square.grid.3x3.middle.filled")
                        .font(.system(size: 19, weight: .medium))
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("MANUSCRIPT")
                    Text("MATRIX")
                }
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.6)
            }
            .foregroundStyle(MMColor.sidebarInk)
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 28)

            sidebarNavItem(.matrix)
            sidebarNavItem(.manuscripts)
            sidebarNavItem(.journals)
            sidebarNavItem(.relationships)
            sidebarNavItem(.activity)

            Text("概览")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Color.white.opacity(0.38))
                .padding(.horizontal, 20)
                .padding(.top, 28)
                .padding(.bottom, 12)

            sidebarMetric(
                value: "\(store.board.visibleManuscripts.count)",
                label: "活跃稿件",
                color: Color.white,
                scope: .all
            )
            sidebarMetric(
                value: "\(count(for: .awaitingDecision))",
                label: "等待决策",
                color: MMColor.indigo,
                scope: .awaitingDecision
            )
            sidebarMetric(
                value: "\(count(for: .revision))",
                label: "正在返修",
                color: MMColor.amber,
                scope: .revision
            )
            sidebarMetric(
                value: "\(count(for: .incomplete))",
                label: "未完成",
                color: MMColor.graphite,
                scope: .incomplete
            )
            sidebarMetric(
                value: "\(count(for: .preparingSubmission))",
                label: "准备提交",
                color: MMColor.jade,
                scope: .preparingSubmission
            )
            sidebarMetric(
                value: "\(count(for: .rejected))",
                label: "Rejected",
                color: MMColor.vermilion,
                scope: .rejected
            )
            sidebarMetric(
                value: "\(count(for: .accepted))",
                label: "Accepted",
                color: MMColor.jade,
                scope: .accepted
            )

            Spacer()

            ActivityHeatmap(board: store.board)

            Divider()
                .overlay(Color.white.opacity(0.07))
                .padding(.horizontal, 20)

            HStack(spacing: 7) {
                Circle().fill(MMColor.jade).frame(width: 7, height: 7)
                Text(MMLocalization.format("v%@ · 更新于%@", appVersion, MMDateText.relativePast(from: store.board.modifiedAt, to: displayDate)))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.58))
            .padding(.horizontal, 20)
            .frame(height: 48)
        }
        .background(MMColor.sidebar)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.3"
    }

    private func sidebarNavItem(_ section: AppSection) -> some View {
        let selected = selectedSection == section
        return Button {
            selectedSection = section
            searchText = ""
        } label: {
            HStack(spacing: 11) {
                Image(systemName: section.icon).frame(width: 18)
                Text(section.title)
                Spacer()
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? Color.white : Color.white.opacity(0.55))
            .padding(.horizontal, 13)
            .frame(height: 38)
            .background(selected ? Color.white.opacity(0.105) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }

    private func sidebarMetric(
        value: String,
        label: String,
        color: Color,
        scope: MatrixScope
    ) -> some View {
        Button {
            matrixScope = scope
            selectedSection = .matrix
        } label: {
            HStack(spacing: 12) {
                Text(value)
                    .font(.system(size: 21, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                    .frame(width: 37, alignment: .trailing)
                Text(MMLocalization.string(label))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.56))
                Spacer()
                if selectedSection == .matrix, matrixScope == scope {
                    Circle().fill(color).frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var toolbar: some View {
        HStack(spacing: 13) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(selectedSection.title)
                    if selectedSection == .matrix, matrixScope != .all {
                        MMPill(
                            matrixScope.title,
                            foreground: MMColor.indigo,
                            background: MMColor.indigoWash,
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .onTapGesture { matrixScope = .all }
                    }
                }
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(MMColor.ink)
                Text(selectedSection.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(MMColor.secondaryInk)
            }

            Spacer()

            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(MMColor.secondaryInk)
                TextField("查找期刊或稿件", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
            }
            .padding(.horizontal, 11)
            .frame(width: 238, height: 32)
            .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9).stroke(MMColor.hairline, lineWidth: 0.7)
            }

            if selectedSection == .matrix {
                MatrixFoldControl(
                    hidesUnusedJournals: $hidesUnusedJournals,
                    hidesIncompleteManuscripts: $hidesIncompleteManuscripts,
                    hidesAcceptedManuscripts: $hidesAcceptedManuscripts
                )

                MatrixDensityControl(
                    density: matrixDensity,
                    onSelect: setMatrixDensity
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }

            MMIconButton(systemName: "arrow.uturn.backward", help: "撤销") {
                Task { try? await store.undo() }
            }
            .disabled(!store.canUndo)

            Menu {
                Button("新建稿件", systemImage: "doc.badge.plus") { addSheet = .manuscript }
                Button("新建期刊", systemImage: "books.vertical.fill") { addSheet = .journal }
                Divider()
                Button("导出备份…", systemImage: "square.and.arrow.up") { prepareExport() }
                Button("导入备份…", systemImage: "square.and.arrow.down") { showsImporter = true }
            } label: {
                Label("添加", systemImage: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MMColor.indigo)
                    .padding(.horizontal, 13)
                    .frame(height: 32)
                    .background(MMColor.indigoWash, in: Capsule())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 22)
        .frame(height: 72)
        .background(MMColor.canvas)
    }

    private var matrixDensity: MatrixDensity {
        MatrixDensity(rawValue: matrixDensityRawValue) ?? .detailed
    }

    private var matrixVisibility: MatrixVisibilityOptions {
        MatrixVisibilityOptions(
            hidesUnusedJournals: hidesUnusedJournals,
            hidesIncompleteManuscripts: hidesIncompleteManuscripts,
            hidesAcceptedManuscripts: hidesAcceptedManuscripts
        )
    }

    private var matrixDensityBinding: Binding<MatrixDensity> {
        Binding(
            get: { matrixDensity },
            set: { setMatrixDensity($0) }
        )
    }

    private func setMatrixDensity(_ density: MatrixDensity) {
        withAnimation(.snappy(duration: 0.3, extraBounce: 0.04)) {
            matrixDensityRawValue = density.rawValue
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("创建你的第一个投稿矩阵", systemImage: "square.grid.3x3")
        } description: {
            Text("至少添加一篇稿件和一个期刊即可开始。")
        } actions: {
            HStack {
                Button("添加稿件") { addSheet = .manuscript }
                Button("添加期刊") { addSheet = .journal }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func count(for scope: MatrixScope) -> Int {
        store.board.visibleManuscripts.filter {
            scope.includes(store.board.manuscriptProjection(for: $0.id))
        }.count
    }

    private func prepareExport() {
        do {
            exportDocument = BoardArchiveDocument(data: try store.exportArchive())
            showsExporter = true
        } catch {
            archiveErrorMessage = error.localizedDescription
        }
    }

    private func handleImportSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let gainedAccess = url.startAccessingSecurityScopedResource()
            defer {
                if gainedAccess { url.stopAccessingSecurityScopedResource() }
            }
            pendingImportData = try Data(contentsOf: url)
        } catch {
            archiveErrorMessage = error.localizedDescription
        }
    }

    private func importPendingArchive() {
        guard let data = pendingImportData else { return }
        pendingImportData = nil
        Task {
            do {
                try await store.importArchive(data)
            } catch {
                archiveErrorMessage = error.localizedDescription
            }
        }
    }
}

private struct MatrixFoldControl: View {
    @Binding var hidesUnusedJournals: Bool
    @Binding var hidesIncompleteManuscripts: Bool
    @Binding var hidesAcceptedManuscripts: Bool

    private var hidesAnyManuscripts: Bool {
        hidesIncompleteManuscripts || hidesAcceptedManuscripts
    }

    var body: some View {
        HStack(spacing: 2) {
            Button {
                withAnimation(.snappy(duration: 0.25, extraBounce: 0.02)) {
                    hidesUnusedJournals.toggle()
                }
            } label: {
                controlIcon(selected: hidesUnusedJournals) {
                    Image(systemName: "rectangle.compress.vertical")
                }
            }
            .buttonStyle(.plain)
            .help(MMLocalization.string(hidesUnusedJournals ? "显示空白期刊" : "隐藏没有目标或投稿记录的期刊"))
            .accessibilityLabel(MMLocalization.string(hidesUnusedJournals ? "显示空白期刊" : "隐藏空白期刊"))

            Menu {
                Toggle("隐藏未完成稿件", isOn: animatedBinding($hidesIncompleteManuscripts))
                Toggle("隐藏已录用稿件", isOn: animatedBinding($hidesAcceptedManuscripts))
                if hidesAnyManuscripts {
                    Divider()
                    Button("显示全部稿件") {
                        withAnimation(.snappy(duration: 0.25, extraBounce: 0.02)) {
                            hidesIncompleteManuscripts = false
                            hidesAcceptedManuscripts = false
                        }
                    }
                }
            } label: {
                controlIcon(selected: hidesAnyManuscripts) {
                    HorizontalFoldGlyph()
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(MMLocalization.string("收纳稿件列"))
            .accessibilityLabel(MMLocalization.string("收纳稿件列"))
        }
        .padding(3)
        .frame(height: 32)
        .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MMLocalization.string("矩阵收纳"))
    }

    private func controlIcon<Icon: View>(
        selected: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        ZStack {
            icon()
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? MMColor.indigo : MMColor.secondaryInk)
        }
        .frame(width: 27, height: 24, alignment: .center)
        .background(
            selected ? MMColor.indigoWash : Color.clear,
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func animatedBinding(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding(
            get: { binding.wrappedValue },
            set: { value in
                withAnimation(.snappy(duration: 0.25, extraBounce: 0.02)) {
                    binding.wrappedValue = value
                }
            }
        )
    }
}

private struct HorizontalFoldGlyph: View {
    var body: some View {
        ZStack {
            Capsule(style: .continuous)
                .frame(width: 1.4, height: 13)

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .offset(x: -5.5)

            Image(systemName: "chevron.left")
                .font(.system(size: 7, weight: .bold))
                .offset(x: 5.5)
        }
        .frame(width: 19, height: 17, alignment: .center)
    }
}

private struct MatrixDensityControl: View {
    let density: MatrixDensity
    let onSelect: (MatrixDensity) -> Void

    var body: some View {
        HStack(spacing: 2) {
            densityButton(.overview, shortcut: "-")
            densityButton(.detailed, shortcut: "+")
        }
        .padding(3)
        .frame(height: 32)
        .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(MMColor.hairline, lineWidth: 0.7)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(MMLocalization.string("矩阵显示密度"))
    }

    private func densityButton(_ option: MatrixDensity, shortcut: KeyEquivalent) -> some View {
        let selected = density == option
        return Button {
            onSelect(option)
        } label: {
            Image(systemName: option.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? MMColor.indigo : MMColor.secondaryInk)
                .frame(width: 27, height: 24)
                .background(
                    selected ? MMColor.indigoWash : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help(MMLocalization.string(option == .overview ? "缩览矩阵（⌘−）" : "详细矩阵（⌘+）"))
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
