import Foundation
import ManuscriptDomain
import ManuscriptDesignSystem
import SwiftUI

extension ManuscriptReadiness {
    var displayName: String {
        let key: String = switch self {
        case .incomplete: "已收录"
        case .experimenting: "实验中"
        case .conceptualizing: "正在构思"
        case .writing: "正在写作"
        case .readyToSubmit: "完成"
        }
        return MMLocalization.string(key)
    }

    var detailText: String {
        let key: String = switch self {
        case .incomplete: "已收录，尚未开始"
        case .experimenting: "实验与数据准备进行中"
        case .conceptualizing: "正在整理结构与核心叙事"
        case .writing: "正文写作进行中"
        case .readyToSubmit: "稿件已完成，可以安排投稿"
        }
        return MMLocalization.string(key)
    }

    var color: Color {
        switch self {
        case .incomplete, .experimenting, .conceptualizing, .writing: MMColor.graphite
        case .readyToSubmit: MMColor.jade
        }
    }

    var wash: Color {
        switch self {
        case .incomplete, .experimenting, .conceptualizing, .writing: MMColor.elevated
        case .readyToSubmit: MMColor.jadeWash
        }
    }

    var icon: String {
        switch self {
        case .incomplete: "tray"
        case .experimenting: "flask.fill"
        case .conceptualizing: "lightbulb.fill"
        case .writing: "square.and.pencil"
        case .readyToSubmit: "checkmark.circle.fill"
        }
    }
}

extension ManuscriptStatus {
    var displayName: String {
        let key: String = switch self {
        case .awaitingSubmission: "待投"
        case .submitted: "Submitted"
        case .majorRevision: "Major revision"
        case .minorRevision: "Minor revision"
        case .rejectAndResubmit: "Reject & resubmit"
        case .accepted: "Accepted"
        }
        return MMLocalization.string(key)
    }

    var color: Color {
        switch self {
        case .awaitingSubmission: MMColor.graphite
        case .submitted: MMColor.indigo
        case .majorRevision, .minorRevision, .rejectAndResubmit: MMColor.amber
        case .accepted: MMColor.jade
        }
    }

    var wash: Color {
        switch self {
        case .awaitingSubmission: MMColor.surface
        case .submitted: MMColor.indigoWash
        case .majorRevision, .minorRevision, .rejectAndResubmit: MMColor.amberWash
        case .accepted: MMColor.jadeWash
        }
    }

    var icon: String {
        switch self {
        case .awaitingSubmission: "tray"
        case .submitted: "paperplane.fill"
        case .majorRevision: "arrow.triangle.2.circlepath"
        case .minorRevision: "pencil.line"
        case .rejectAndResubmit: "arrow.uturn.backward.circle.fill"
        case .accepted: "checkmark.seal.fill"
        }
    }
}

extension SubmissionEventKind {
    var displayName: String {
        switch self {
        case .submitted: "Submitted"
        case .resubmitted: "Revision resubmitted"
        case .majorRevision: "Major revision"
        case .minorRevision: "Minor revision"
        case .rejectAndResubmit: "Reject & resubmit"
        case .rejected: "Rejected"
        case .accepted: "Accepted"
        case .withdrawn: "Withdrawn"
        }
    }

    var color: Color {
        switch self {
        case .submitted, .resubmitted: MMColor.indigo
        case .majorRevision, .minorRevision, .rejectAndResubmit: MMColor.amber
        case .rejected: MMColor.vermilion
        case .accepted: MMColor.jade
        case .withdrawn: MMColor.graphite
        }
    }

    var icon: String {
        switch self {
        case .submitted, .resubmitted: "paperplane.fill"
        case .majorRevision, .minorRevision: "arrow.triangle.2.circlepath"
        case .rejectAndResubmit: "arrow.uturn.backward.circle.fill"
        case .rejected: "xmark.circle.fill"
        case .accepted: "checkmark.seal.fill"
        case .withdrawn: "arrowshape.turn.up.backward.fill"
        }
    }
}

enum MMDateText {
    static func elapsed(from date: Date, to now: Date = .now) -> String {
        "\(date.wholeDays(to: now))d"
    }

    static func relativePast(from date: Date, to now: Date = .now) -> String {
        let days = date.wholeDays(to: now)
        if days == 0 { return MMLocalization.string("今天") }
        if days == 1 { return MMLocalization.string("1 天前") }
        return MMLocalization.format("%d 天前", days)
    }

    static var absolute: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = MMLocalization.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
