import Foundation
import ManuscriptDomain

public enum BoardRepositoryError: LocalizedError, Equatable, Sendable {
    case writeConflict

    public var errorDescription: String? {
        switch self {
        case .writeConflict:
            "The board changed in another process before this update could be saved."
        }
    }
}

public protocol BoardRepository: Sendable {
    func load() async throws -> BoardSnapshot
    func save(_ snapshot: BoardSnapshot, replacing expected: BoardSnapshot?) async throws
    func changes() async -> AsyncStream<Void>
}

public extension BoardRepository {
    func save(_ snapshot: BoardSnapshot) async throws {
        try await save(snapshot, replacing: nil)
    }

    func changes() async -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
