import ManuscriptDesignSystem
import ManuscriptDomain
import SwiftUI

struct JournalPartitionEditor: View {
    @Binding var partitions: [JournalPartition]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach($partitions) { $partition in
                let scheme = JournalPartitionScheme.resolve(partition.scheme) ?? .jcr
                HStack(spacing: 8) {
                    Picker("体系", selection: schemeBinding(for: $partition)) {
                        ForEach(JournalPartitionScheme.allCases) { option in
                            Text(option.localizedDisplayName).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 118)
                    TextField(
                        "年份",
                        text: Binding(
                            get: { partition.year.map(String.init) ?? "" },
                            set: { partition.year = Int($0) }
                        )
                    )
                    .frame(width: 64)
                    Picker("等级", selection: $partition.value) {
                        ForEach(scheme.allowedValues, id: \.self) { value in
                            Text(value).tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 76)
                    TextField(
                        "学科（可选）",
                        text: Binding(
                            get: { partition.category ?? "" },
                            set: { partition.category = $0.trimmed.nilIfEmpty }
                        )
                    )
                    Button(role: .destructive) {
                        partitions.removeAll { $0.id == partition.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            Menu {
                ForEach(JournalPartitionScheme.allCases) { scheme in
                    Button(scheme.localizedDisplayName) { add(scheme) }
                }
            } label: {
                Label("添加分区记录", systemImage: "plus.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func add(_ scheme: JournalPartitionScheme) {
        partitions.append(JournalPartition(scheme: scheme.rawValue, value: scheme.defaultValue))
    }

    private func schemeBinding(for partition: Binding<JournalPartition>) -> Binding<JournalPartitionScheme> {
        Binding(
            get: { JournalPartitionScheme.resolve(partition.wrappedValue.scheme) ?? .jcr },
            set: { scheme in
                partition.wrappedValue.scheme = scheme.rawValue
                if !scheme.allowedValues.contains(partition.wrappedValue.value) {
                    partition.wrappedValue.value = scheme.defaultValue
                }
            }
        )
    }
}

private extension JournalPartitionScheme {
    var localizedDisplayName: String {
        switch self {
        case .jcr: "JCR"
        case .ccf: "CCF"
        case .cas: MMLocalization.string("中科院（CAS）")
        case .emerging: MMLocalization.string("新锐")
        }
    }
}
