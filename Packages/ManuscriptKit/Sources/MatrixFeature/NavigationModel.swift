import ManuscriptDomain
import ManuscriptDesignSystem

enum AppSection: String, CaseIterable, Identifiable {
    case matrix
    case manuscripts
    case journals
    case relationships
    case activity

    var id: String { rawValue }

    var title: String {
        let key: String = switch self {
        case .matrix: "投稿矩阵"
        case .manuscripts: "稿件"
        case .journals: "期刊库"
        case .relationships: "稿件关系"
        case .activity: "投稿动态"
        }
        return MMLocalization.string(key)
    }

    var subtitle: String {
        let key: String = switch self {
        case .matrix: "在一个视图中查看策略、时间与历史"
        case .manuscripts: "将每篇稿件作为独立的投稿策略对象"
        case .journals: "期刊身份、排序、指标与分区"
        case .relationships: "由你声明的稿件之间的策略关系"
        case .activity: "可审计的真实投稿事件时间线"
        }
        return MMLocalization.string(key)
    }

    var icon: String {
        switch self {
        case .matrix: "square.grid.3x3.fill"
        case .manuscripts: "doc.on.doc.fill"
        case .journals: "books.vertical.fill"
        case .relationships: "point.3.connected.trianglepath.dotted"
        case .activity: "clock.arrow.circlepath"
        }
    }
}
enum MatrixScope: String, CaseIterable, Identifiable {
    case all
    case awaitingDecision
    case revision
    case incomplete
    case preparingSubmission
    case rejected
    case accepted

    var id: String { rawValue }

    var title: String {
        let key: String = switch self {
        case .all: "全部稿件"
        case .awaitingDecision: "等待决策"
        case .revision: "正在返修"
        case .incomplete: "未完成"
        case .preparingSubmission: "准备提交"
        case .rejected: "Rejected"
        case .accepted: "Accepted"
        }
        return MMLocalization.string(key)
    }

    func includes(_ projection: ManuscriptProjection) -> Bool {
        switch self {
        case .all:
            true
        case .awaitingDecision:
            projection.situation == .awaitingDecision
        case .revision:
            projection.situation == .revision
        case .incomplete:
            projection.situation == .incomplete
        case .preparingSubmission:
            projection.situation == .preparingSubmission
        case .rejected:
            projection.situation == .rejected
        case .accepted:
            projection.situation == .accepted
        }
    }
}

struct MatrixVisibilityOptions: Equatable {
    var hidesUnusedJournals: Bool
    var hidesIncompleteManuscripts: Bool
    var hidesAcceptedManuscripts: Bool

    var hasCollapsedContent: Bool {
        hidesUnusedJournals || hidesIncompleteManuscripts || hidesAcceptedManuscripts
    }
}
