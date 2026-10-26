import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct AddManuscriptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    @State private var title = ""
    @State private var shortTitle = ""
    @State private var tags = ""
    @State private var readiness: ManuscriptReadiness = .incomplete
    @State private var createdAt = Date.now
    @State private var errorMessage: String?

    var body: some View {
        MMFormSheet(title: "新建稿件", subtitle: "将稿件作为投稿策略对象进行管理") {
            TextField("简称", text: $shortTitle)
            TextField("完整论文标题", text: $title, axis: .vertical)
                .lineLimit(2...4)
            TextField("标签（用逗号分隔）", text: $tags)
            Picker("准备阶段", selection: $readiness) {
                ForEach(ManuscriptReadiness.allCases, id: \.self) { stage in
                    Text(stage.displayName).tag(stage)
                }
            }
            .pickerStyle(.menu)
            DatePicker("记录时间", selection: $createdAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
        } footer: {
            if let errorMessage { formError(errorMessage) }
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("创建稿件") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || shortTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func create() {
        Task {
            do {
                try await store.execute(
                    .createManuscript(
                        id: ManuscriptID(),
                        title: title,
                        shortTitle: shortTitle,
                        tags: tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) },
                        readiness: readiness,
                        createdAt: createdAt
                    )
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct AddJournalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: BoardCommandService
    @State private var name = ""
    @State private var rank = 1
    @State private var impactFactor: Double?
    @State private var category = ""
    @State private var averageDecisionDays = ""
    @State private var issn = ""
    @State private var eISSN = ""
    @State private var tags = ""
    @State private var partitions: [JournalPartition] = []
    @State private var createdAt = Date.now
    @State private var errorMessage: String?

    var body: some View {
        MMFormSheet(title: "新建期刊", subtitle: "期刊更名后仍保留同一个永久 ID") {
            TextField("Journal name", text: $name)
            Stepper(MMLocalization.format("全局排名：%d", rank), value: $rank, in: 1...max(1, store.board.journals.count + 1))
            HStack {
                TextField("IF", value: $impactFactor, format: .number)
                TextField("平均决定天数", text: $averageDecisionDays)
            }
            TextField("学科类别", text: $category)
            HStack {
                TextField("ISSN", text: $issn)
                TextField("eISSN", text: $eISSN)
            }
            TextField("标签（用逗号分隔）", text: $tags)
            Section("分区记录（可添加多条）") {
                JournalPartitionEditor(partitions: $partitions)
            }
            DatePicker("记录时间", selection: $createdAt, in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
        } footer: {
            if let errorMessage { formError(errorMessage) }
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("添加期刊") { create() }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func create() {
        Task {
            do {
                try await store.execute(
                    .createJournal(
                        id: JournalID(),
                        name: name,
                        rank: rank,
                        metrics: JournalMetrics(
                            impactFactor: impactFactor,
                            quartile: partitions.first(where: { $0.scheme == "JCR" })?.value.nilIfEmpty,
                            category: category.trimmed.nilIfEmpty,
                            averageDecisionDays: Int(averageDecisionDays),
                            partitions: cleanedPartitions
                        ),
                        issn: issn,
                        eISSN: eISSN,
                        tags: commaSeparated(tags),
                        createdAt: createdAt
                    )
                )
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

private struct MMFormSheet<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Footer

    init(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(MMLocalization.string(title)).font(.system(size: 22, weight: .semibold))
                Text(MMLocalization.string(subtitle)).font(.system(size: 11)).foregroundStyle(MMColor.secondaryInk)
            }
            .padding(24)

            Divider()

            Form { content }
                .formStyle(.grouped)
                .padding(.horizontal, 10)

            Divider()

            HStack { Spacer(); footer }
                .padding(18)
        }
        .frame(width: 480)
        .frame(minHeight: 350)
        .background(MMColor.canvas)
    }
}

@ViewBuilder
private func formError(_ message: String) -> some View {
    Text(message)
        .font(.system(size: 10))
        .foregroundStyle(MMColor.vermilion)
        .padding(.trailing, 8)
}
