import Foundation
import ManuscriptDomain

func commaSeparated(_ text: String) -> [String] {
    text.split(separator: ",").map { String($0).trimmed }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

extension Journal {
    /// A presentation-only name for the overview matrix. Stable identity,
    /// persisted names and historical snapshots always retain `currentName`.
    var overviewDisplayName: String {
        let transactionPrefixes = [
            "IEEE Transactions on ",
            "IEEE/ACM Transactions on ",
            "ACM Transactions on "
        ]

        for prefix in transactionPrefixes where currentName.hasPrefix(prefix) {
            return "Trans. on " + currentName.dropFirst(prefix.count)
        }
        return currentName
    }
}
