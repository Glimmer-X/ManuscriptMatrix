import Foundation
import ManuscriptDomain

public enum BoardArchiveError: LocalizedError, Equatable {
    case unsupportedSchema(Int)
    case duplicateIdentity(String)
    case danglingReference(String)
    case invalidTargetPlan(String)
    case invalidJournalLadder(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(version):
            "This backup uses unsupported schema version \(version)."
        case let .duplicateIdentity(kind):
            "The backup contains duplicate \(kind) identities."
        case let .danglingReference(description):
            "The backup contains an invalid reference: \(description)."
        case let .invalidTargetPlan(description):
            "The backup contains an invalid target plan: \(description)."
        case let .invalidJournalLadder(description):
            "The backup contains an invalid journal ladder: \(description)."
        }
    }
}

public enum BoardArchiveCodec {
    public static func encode(_ board: BoardSnapshot, prettyPrinted: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted
            ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            : [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(board)
    }

    public static func decode(_ data: Data) throws -> BoardSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let board = try decoder.decode(BoardSnapshot.self, from: data)
        try BoardValidator.validate(board)
        return board
    }
}

public enum BoardValidator {
    public static func validate(_ board: BoardSnapshot) throws {
        guard board.schemaVersion == 1 else {
            throw BoardArchiveError.unsupportedSchema(board.schemaVersion)
        }

        try requireUnique(board.journals.map(\.id), kind: "journal")
        try requireUnique(board.manuscripts.map(\.id), kind: "manuscript")
        try requireUnique(board.submissionEvents.map(\.id), kind: "submission event")
        try requireUnique(board.relationships.map(\.id), kind: "relationship")

        let journalIDs = Set(board.journals.map(\.id))
        let manuscriptIDs = Set(board.manuscripts.map(\.id))
        let activeJournalIDs = Set(board.journals.filter { $0.archivedAt == nil }.map(\.id))
        let activeManuscriptIDs = Set(board.manuscripts.filter { $0.archivedAt == nil }.map(\.id))

        let journalRanks = board.rankedJournals.map(\.rank)
        let expectedRanks = board.rankedJournals.isEmpty ? [] : Array(1...board.rankedJournals.count)
        guard journalRanks == expectedRanks else {
            throw BoardArchiveError.invalidJournalLadder("active ranks must be contiguous")
        }

        for event in board.submissionEvents {
            guard manuscriptIDs.contains(event.manuscriptID) else {
                throw BoardArchiveError.danglingReference("event → manuscript")
            }
            guard journalIDs.contains(event.journalID) else {
                throw BoardArchiveError.danglingReference("event → journal")
            }
        }

        for target in board.targets {
            guard manuscriptIDs.contains(target.manuscriptID) else {
                throw BoardArchiveError.danglingReference("target → manuscript")
            }
            guard journalIDs.contains(target.journalID) else {
                throw BoardArchiveError.danglingReference("target → journal")
            }
            guard activeManuscriptIDs.contains(target.manuscriptID),
                  activeJournalIDs.contains(target.journalID) else {
                throw BoardArchiveError.invalidTargetPlan("archived entities cannot remain in a target plan")
            }
        }

        for relationship in board.relationships {
            guard manuscriptIDs.contains(relationship.firstManuscriptID),
                  manuscriptIDs.contains(relationship.secondManuscriptID) else {
                throw BoardArchiveError.danglingReference("relationship → manuscript")
            }
            guard relationship.firstManuscriptID != relationship.secondManuscriptID else {
                throw BoardArchiveError.danglingReference("relationship connects a manuscript to itself")
            }
        }

        for manuscriptID in manuscriptIDs {
            let targets = board.targets(for: manuscriptID)
            let priorities = targets.map(\.priority)
            let expected = targets.isEmpty ? [] : Array(1...targets.count)
            guard priorities == expected else {
                throw BoardArchiveError.invalidTargetPlan("priorities must be contiguous for \(manuscriptID)")
            }
            guard Set(targets.map(\.journalID)).count == targets.count else {
                throw BoardArchiveError.invalidTargetPlan("a journal appears more than once for \(manuscriptID)")
            }
        }
    }

    private static func requireUnique<ID: Hashable>(_ ids: [ID], kind: String) throws {
        guard Set(ids).count == ids.count else {
            throw BoardArchiveError.duplicateIdentity(kind)
        }
    }
}
