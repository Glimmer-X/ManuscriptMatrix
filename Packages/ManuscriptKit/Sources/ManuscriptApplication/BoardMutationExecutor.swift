import Foundation
import ManuscriptDomain

public struct PersistedBoardMutation: Sendable {
    public let previousBoard: BoardSnapshot
    public let board: BoardSnapshot
    public let receipt: MutationReceipt

    public init(previousBoard: BoardSnapshot, board: BoardSnapshot, receipt: MutationReceipt) {
        self.previousBoard = previousBoard
        self.board = board
        self.receipt = receipt
    }
}

/// Applies commands against the latest persisted snapshot and retries when a
/// different process wins the optimistic write race.
public enum BoardMutationExecutor {
    public static func execute(
        _ commands: [BoardCommand],
        initialBoard: BoardSnapshot? = nil,
        repository: any BoardRepository,
        maximumAttempts: Int = 4
    ) async throws -> PersistedBoardMutation {
        precondition(!commands.isEmpty)
        precondition(maximumAttempts > 0)

        var base: BoardSnapshot
        if let initialBoard {
            base = initialBoard
        } else {
            base = try await repository.load()
        }

        for attempt in 1...maximumAttempts {
            var candidate = base
            let receipts = try commands.map { command in
                try BoardReducer.apply(command, to: &candidate)
            }

            do {
                try await repository.save(candidate, replacing: base)
                let persisted = try await repository.load()
                return PersistedBoardMutation(
                    previousBoard: base,
                    board: persisted,
                    receipt: combinedReceipt(receipts)
                )
            } catch BoardRepositoryError.writeConflict where attempt < maximumAttempts {
                base = try await repository.load()
            }
        }

        throw BoardRepositoryError.writeConflict
    }

    public static func execute(
        _ command: BoardCommand,
        initialBoard: BoardSnapshot? = nil,
        repository: any BoardRepository,
        maximumAttempts: Int = 4
    ) async throws -> PersistedBoardMutation {
        try await execute(
            [command],
            initialBoard: initialBoard,
            repository: repository,
            maximumAttempts: maximumAttempts
        )
    }

    private static func combinedReceipt(_ receipts: [MutationReceipt]) -> MutationReceipt {
        MutationReceipt(
            summary: receipts.map(\.summary).joined(separator: " "),
            affectedEntityIDs: Array(Set(receipts.flatMap(\.affectedEntityIDs))).sorted()
        )
    }
}
