import CoreGraphics
import ManuscriptDesignSystem

/// Semantic zoom levels for the matrix. Overview is not a scaled-down copy of
/// the detailed board: it deliberately removes secondary text while preserving
/// entity identity, status colour and every click target.
enum MatrixDensity: String, CaseIterable, Identifiable {
    case overview
    case detailed

    var id: String { rawValue }

    var journalColumnWidth: CGFloat {
        switch self {
        case .overview: 194
        case .detailed: 240
        }
    }

    var manuscriptColumnWidth: CGFloat {
        switch self {
        case .overview: 104
        case .detailed: 204
        }
    }

    var headerHeight: CGFloat {
        switch self {
        case .overview: 54
        case .detailed: 116
        }
    }

    var stagingHeight: CGFloat {
        switch self {
        case .overview: 46
        case .detailed: 92
        }
    }

    var rowHeight: CGFloat {
        switch self {
        case .overview: 60
        case .detailed: 112
        }
    }

    var title: String {
        let key: String = switch self {
        case .overview: "缩览"
        case .detailed: "详细"
        }
        return MMLocalization.string(key)
    }

    var icon: String {
        switch self {
        case .overview: "rectangle.grid.3x2"
        case .detailed: "rectangle.grid.1x2"
        }
    }
}
