import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct EditManuscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let manuscript: Manuscript

    @State private var title: String
    @State private var shortTitle: String
    @State private var tags: String
    @State private var readiness: ManuscriptReadiness
    @State private var readinessOccurredAt = Date.now
    @State private var errorMessage: String?

    init(store: BoardCommandService, manuscript: Manuscript) {
        self.store = store
        self.manuscript = manuscript
        _title = State(initialValue: manuscript.title)
        _shortTitle = State(initialValue: manuscript.shortTitle)
        _tags = State(initialValue: manuscript.tags.joined(separator: ", "))
        _readiness = State(initialValue: manuscript.readiness)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader("编辑稿件", subtitle: MMLocalization.format("永久 ID · %@", manuscript.id.rawValue.uuidString))
            Divider()
            Form {
                TextField("简称", text: $shortTitle)
                TextField("完整论文标题", text: $title, axis: .vertical)
                    .lineLimit(2...5)
                TextField("标签（用逗号分隔）", text: $tags)
                Section("投稿准备状态") {
                    Picker("准备阶段", selection: $readiness) {
                        ForEach(ManuscriptReadiness.allCases, id: \.self) { stage in
                            Text(stage.displayName).tag(stage)
                        }
                    }
                    .pickerStyle(.menu)
                    if readiness != manuscript.readiness {
                        DatePicker(
                            "状态时间",
                            selection: $readinessOccurredAt,
                            in: ...Date.now,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let errorMessage { inlineError(errorMessage) }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.trimmed.isEmpty || shortTitle.trimmed.isEmpty)
            }
            .padding(18)
        }
        .frame(width: 500, height: 390)
        .background(MMColor.canvas)
    }

    private func save() {
        var commands: [BoardCommand] = [
            .updateManuscript(
                manuscriptID: manuscript.id,
                title: title,
                shortTitle: shortTitle,
                tags: commaSeparated(tags)
            )
        ]
        if readiness != manuscript.readiness {
            commands.append(
                .setManuscriptReadiness(
                    manuscriptID: manuscript.id,
                    readiness: readiness,
                    occurredAt: readinessOccurredAt
                )
            )
        }
        Task {
            do {
                try await store.execute(commands)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func run(_ command: BoardCommand) {
        Task {
            do {
                try await store.execute(command)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct JournalEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let journal: Journal

    @State private var name: String
    @State private var rank: Int
    @State private var impactFactor: Double?
    @State private var category: String
    @State private var averageDecisionDays: String
    @State private var issn: String
    @State private var eISSN: String
    @State private var tags: String
    @State private var partitions: [JournalPartition]
    @State private var renameOccurredAt = Date.now
    @State private var errorMessage: String?

    init(store: BoardCommandService, journal: Journal) {
        self.store = store
        self.journal = journal
        _name = State(initialValue: journal.currentName)
        _rank = State(initialValue: journal.rank)
        _impactFactor = State(initialValue: journal.metrics.impactFactor)
        _category = State(initialValue: journal.metrics.category ?? "")
        _averageDecisionDays = State(initialValue: journal.metrics.averageDecisionDays.map { String($0) } ?? "")
        _issn = State(initialValue: journal.issn ?? "")
        _eISSN = State(initialValue: journal.eISSN ?? "")
        _tags = State(initialValue: journal.tags.joined(separator: ", "))
        _partitions = State(initialValue: journal.metrics.partitions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sheetHeader("编辑期刊", subtitle: MMLocalization.format("永久 ID · %@", journal.id.rawValue.uuidString))
            Divider()

            Form {
                Section("身份与顺序") {
                    TextField("Journal name", text: $name)
                    if name.trimmed != journal.currentName {
                        DatePicker("更名生效时间", selection: $renameOccurredAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                    }
                    Stepper(MMLocalization.format("全局排名：%d", rank), value: $rank, in: 1...max(1, store.board.rankedJournals.count))
                    HStack {
                        TextField("ISSN", text: $issn)
                        TextField("eISSN", text: $eISSN)
                    }
                }

                Section("指标") {
                    TextField("IF", value: $impactFactor, format: .number)
                    TextField("学科类别", text: $category)
                    TextField("平均决定天数", text: $averageDecisionDays)
                }

                Section("分区记录（可同时保存多套体系与年份）") {
                    JournalPartitionEditor(partitions: $partitions)
                }

                Section("分类") {
                    TextField("标签（用逗号分隔）", text: $tags)
                }

                if journal.nameHistory.count > 1 {
                    Section("名称历史") {
                        ForEach(journal.nameHistory.sorted(by: { $0.effectiveFrom > $1.effectiveFrom })) { record in
                            HStack {
                                Text(record.name)
                                Spacer()
                                Text(MMDateText.absolute.string(from: record.effectiveFrom))
                                    .foregroundStyle(MMColor.secondaryInk)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if let errorMessage { inlineError(errorMessage) }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存修改") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmed.isEmpty)
            }
            .padding(18)
        }
        .frame(width: 600, height: 650)
        .background(MMColor.canvas)
    }

    private func save() {
        var commands: [BoardCommand] = []
        if name.trimmed != journal.currentName {
            commands.append(.renameJournal(journalID: journal.id, newName: name, occurredAt: renameOccurredAt))
        }
        if rank != journal.rank {
            commands.append(.moveJournal(journalID: journal.id, toRank: rank))
        }
        commands.append(
            .updateJournalMetadata(
                journalID: journal.id,
                metrics: JournalMetrics(
                    impactFactor: impactFactor,
                    quartile: cleanedPartitions.first(where: { $0.scheme == "JCR" })?.value,
                    category: category.trimmed.nilIfEmpty,
                    averageDecisionDays: Int(averageDecisionDays),
                    partitions: cleanedPartitions
                ),
                issn: issn,
                eISSN: eISSN,
                tags: commaSeparated(tags)
            )
        )

        Task {
            do {
                try await store.execute(commands)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private var cleanedPartitions: [JournalPartition] {
        partitions.compactMap { partition in
            let scheme = partition.scheme.trimmed
            let value = partition.value.trimmed
            guard !scheme.isEmpty, !value.isEmpty else { return nil }
            return JournalPartition(
                id: partition.id,
                scheme: scheme,
                year: partition.year,
                value: value,
                category: partition.category?.trimmed.nilIfEmpty
            )
        }
    }
}

struct RelationshipEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let relationship: ManuscriptRelationship?
    let preferredFirstID: ManuscriptID?

    @State private var firstID: ManuscriptID?
    @State private var secondID: ManuscriptID?
    @State private var direction: RelationshipDirection
    @State private var statement: String
    @State private var createdAt: Date
    @State private var errorMessage: String?

    init(
        store: BoardCommandService,
        relationship: ManuscriptRelationship? = nil,
        preferredFirstID: ManuscriptID? = nil
    ) {
        self.store = store
        self.relationship = relationship
        self.preferredFirstID = preferredFirstID
        _firstID = State(initialValue: relationship?.firstManuscriptID ?? preferredFirstID)
        _secondID = State(initialValue: relationship?.secondManuscriptID)
        _direction = State(initialValue: relationship?.direction ?? .firstToSecond)
        _statement = State(initialValue: relationship?.statement ?? "")
        _createdAt = State(initialValue: relationship?.createdAt ?? .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(
                MMLocalization.string(relationship == nil ? "声明稿件关系" : "编辑稿件关系"),
                subtitle: MMLocalization.string("同一条关系记录会同时显示在两篇稿件中")
            )

            Picker("第一篇稿件", selection: $firstID) {
                Text("请选择…").tag(nil as ManuscriptID?)
                ForEach(store.board.visibleManuscripts) { manuscript in
                    Text(manuscript.shortTitle).tag(manuscript.id as ManuscriptID?)
                }
            }
            .disabled(relationship != nil)

            Picker("第二篇稿件", selection: $secondID) {
                Text("请选择…").tag(nil as ManuscriptID?)
                ForEach(store.board.visibleManuscripts.filter { $0.id != firstID }) { manuscript in
                    Text(manuscript.shortTitle).tag(manuscript.id as ManuscriptID?)
                }
            }
            .disabled(relationship != nil)

            Picker("关系方向", selection: $direction) {
                Text("第一篇 → 第二篇").tag(RelationshipDirection.firstToSecond)
                Text("无方向").tag(RelationshipDirection.undirected)
                Text("第二篇 → 第一篇").tag(RelationshipDirection.secondToFirst)
            }

            TextEditor(text: $statement)
                .font(.system(size: 12))
                .frame(height: 130)
                .padding(8)
                .background(MMColor.surface, in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(MMColor.hairline) }
                .overlay(alignment: .topLeading) {
                    if statement.isEmpty {
                        Text("用自然语言描述两篇稿件之间的策略关系…")
                            .font(.system(size: 11))
                            .foregroundStyle(MMColor.secondaryInk.opacity(0.65))
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }

            if relationship == nil {
                DatePicker("关系记录时间", selection: $createdAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
            }

            if let errorMessage { inlineError(errorMessage) }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(MMLocalization.string(relationship == nil ? "创建" : "保存")) { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(firstID == nil || secondID == nil || firstID == secondID || statement.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 520, height: 470)
        .background(MMColor.canvas)
    }

    private func save() {
        guard let firstID, let secondID else { return }
        let command: BoardCommand
        if let relationship {
            command = .updateRelationship(
                relationshipID: relationship.id,
                direction: direction,
                statement: statement
            )
        } else {
            command = .createRelationship(
                id: RelationshipID(),
                firstManuscriptID: firstID,
                secondManuscriptID: secondID,
                direction: direction,
                statement: statement,
                createdAt: createdAt
            )
        }

        Task {
            do {
                try await store.execute(command)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct VoidEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let event: SubmissionEvent

    @State private var reason = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader("纠正历史事件", subtitle: "事件会继续保留，并显示为已纠正的审计记录")
            VStack(alignment: .leading, spacing: 5) {
                Text(event.kind.displayName)
                    .font(.system(size: 13, weight: .semibold))
                Text("\(event.journalNameSnapshot) · \(MMDateText.absolute.string(from: event.occurredAt))")
                    .font(.system(size: 10))
                    .foregroundStyle(MMColor.secondaryInk)
            }
            TextField("纠正原因", text: $reason, axis: .vertical)
                .lineLimit(2...4)
            if let errorMessage { inlineError(errorMessage) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("标记为已纠正", role: .destructive) { voidEvent() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reason.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480, height: 300)
        .background(MMColor.canvas)
    }

    private func voidEvent() {
        Task {
            do {
                try await store.execute(
                    .voidSubmissionEvent(eventID: event.id, reason: reason, occurredAt: .now)
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct RecordSubmissionEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let manuscript: Manuscript
    let journal: Journal
    let kind: SubmissionEventKind
    let onComplete: () -> Void

    @State private var occurredAt = Date.now
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader(
                kind == .submitted ? MMLocalization.string("记录 Submitted") : MMLocalization.format("记录 %@", kind.displayName),
                subtitle: "\(manuscript.shortTitle) · \(journal.currentName)"
            )
            DatePicker(
                "事件发生时间",
                selection: $occurredAt,
                in: ...Date.now,
                displayedComponents: [.date, .hourAndMinute]
            )
            TextField("备注（可选）", text: $note, axis: .vertical)
                .lineLimit(2...4)
            Text("这里记录真实发生时间；可以回填过去发生的投稿或决定。")
                .font(.system(size: 10))
                .foregroundStyle(MMColor.secondaryInk)
            if let errorMessage { inlineError(errorMessage) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(kind == .submitted ? MMLocalization.string("记录 Submitted") : MMLocalization.format("记录 %@", kind.displayName)) { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 330)
        .background(MMColor.canvas)
    }

    private func save() {
        let command: BoardCommand = kind == .submitted
            ? .recordSubmission(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                occurredAt: occurredAt,
                note: note.trimmed.nilIfEmpty
            )
            : .recordStatus(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                kind: kind,
                occurredAt: occurredAt,
                note: note.trimmed.nilIfEmpty
            )
        Task {
            do {
                try await store.execute(command)
                dismiss()
                onComplete()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct EditSubmissionEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    let event: SubmissionEvent

    @State private var occurredAt: Date
    @State private var note: String
    @State private var reason = ""
    @State private var errorMessage: String?

    init(store: BoardCommandService, event: SubmissionEvent) {
        self.store = store
        self.event = event
        _occurredAt = State(initialValue: event.occurredAt)
        _note = State(initialValue: event.note ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            sheetHeader("编辑事件时间与备注", subtitle: "修改会保留旧值、修改原因和修改时间")
            VStack(alignment: .leading, spacing: 5) {
                Text(event.kind.displayName).font(.system(size: 13, weight: .semibold))
                Text(event.journalNameSnapshot)
                    .font(.system(size: 10))
                    .foregroundStyle(MMColor.secondaryInk)
            }
            DatePicker("事件发生时间", selection: $occurredAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
            TextField("备注（可选）", text: $note, axis: .vertical).lineLimit(2...4)
            TextField("修改原因（必填）", text: $reason, axis: .vertical).lineLimit(2...3)
            if let errorMessage { inlineError(errorMessage) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存修正") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reason.trimmed.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 510, height: 410)
        .background(MMColor.canvas)
    }

    private func save() {
        Task {
            do {
                try await store.execute(
                    .amendSubmissionEvent(
                        eventID: event.id,
                        occurredAt: occurredAt,
                        note: note.trimmed.nilIfEmpty,
                        reason: reason,
                        amendedAt: .now
                    )
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@ViewBuilder
private func sheetHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(MMLocalization.string(title)).font(.system(size: 22, weight: .semibold))
        Text(MMLocalization.string(subtitle))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(MMColor.secondaryInk)
            .lineLimit(1)
            .textSelection(.enabled)
    }
    .padding(.horizontal, 24)
    .padding(.top, 22)
    .padding(.bottom, 18)
}

@ViewBuilder
private func inlineError(_ message: String) -> some View {
    Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 10))
        .foregroundStyle(MMColor.vermilion)
}
