import Combine
import Foundation
import ManuscriptDomain

@MainActor
public final class BoardCommandService: ObservableObject {
    @Published public private(set) var board: BoardSnapshot
    @Published public private(set) var lastReceipt: MutationReceipt?
    @Published public private(set) var isLoaded = false
    @Published public private(set) var lastErrorMessage: String?

    private let repository: any BoardRepository
    private var undoStack: [BoardSnapshot] = []
    private let maximumUndoDepth = 30
    private var observationTask: Task<Void, Never>?
    private var scheduledReloadTask: Task<Void, Never>?

    public init(repository: any BoardRepository, initialBoard: BoardSnapshot = .empty) {
        self.repository = repository
        self.board = initialBoard
    }

    deinit {
        observationTask?.cancel()
        scheduledReloadTask?.cancel()
    }

    public var canUndo: Bool { !undoStack.isEmpty }

    public func load(seedIfEmpty: (@Sendable () -> BoardSnapshot)? = nil) async {
        do {
            var loaded = try await repository.load()
            if loaded.manuscripts.isEmpty, loaded.journals.isEmpty, let seedIfEmpty {
                loaded = seedIfEmpty()
                try await repository.save(loaded)
                loaded = try await repository.load()
            }
            board = loaded
            isLoaded = true
            lastErrorMessage = nil
            await startObservingRepository()
        } catch {
            lastErrorMessage = error.localizedDescription
            isLoaded = true
        }
    }

    @discardableResult
    public func execute(_ command: BoardCommand) async throws -> MutationReceipt {
        try await execute([command])
    }

    @discardableResult
    public func execute(_ commands: [BoardCommand]) async throws -> MutationReceipt {
        let mutation = try await BoardMutationExecutor.execute(
            commands,
            initialBoard: board,
            repository: repository
        )
        pushUndo(mutation.previousBoard)
        board = mutation.board
        lastReceipt = mutation.receipt
        lastErrorMessage = nil
        return mutation.receipt
    }

    public func preview(_ commands: [BoardCommand]) throws -> MutationReceipt {
        var candidate = board
        let receipts = try commands.map { try BoardReducer.apply($0, to: &candidate) }
        return MutationReceipt(
            summary: receipts.map(\.summary).joined(separator: " "),
            affectedEntityIDs: Array(Set(receipts.flatMap(\.affectedEntityIDs))).sorted()
        )
    }

    public func undo() async throws {
        guard let previous = undoStack.last else { return }
        do {
            try await repository.save(previous, replacing: board)
            undoStack.removeLast()
            board = try await repository.load()
            lastReceipt = MutationReceipt(
                summary: "Undid the most recent board change.",
                affectedEntityIDs: []
            )
        } catch BoardRepositoryError.writeConflict {
            await reloadExternalBoard()
            throw BoardRepositoryError.writeConflict
        }
    }

    public func exportArchive() throws -> Data {
        try BoardArchiveCodec.encode(board)
    }

    public func importArchive(_ data: Data) async throws {
        var imported = try BoardArchiveCodec.decode(data)
        imported.modifiedAt = .now
        let previous = board
        do {
            try await repository.save(imported, replacing: previous)
            pushUndo(previous)
            board = try await repository.load()
            lastReceipt = MutationReceipt(
                summary: "Imported a validated Manuscript Matrix backup.",
                affectedEntityIDs: []
            )
            lastErrorMessage = nil
        } catch BoardRepositoryError.writeConflict {
            await reloadExternalBoard()
            throw BoardRepositoryError.writeConflict
        }
    }

    private func pushUndo(_ snapshot: BoardSnapshot) {
        undoStack.append(snapshot)
        if undoStack.count > maximumUndoDepth {
            undoStack.removeFirst(undoStack.count - maximumUndoDepth)
        }
    }

    private func startObservingRepository() async {
        guard observationTask == nil else { return }
        let repository = self.repository
        let changes = await repository.changes()
        observationTask = Task { [weak self] in
            for await _ in changes {
                guard !Task.isCancelled else { break }
                self?.scheduleExternalReload()
            }
        }
        await reloadExternalBoard()
    }

    private func scheduleExternalReload() {
        scheduledReloadTask?.cancel()
        scheduledReloadTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(140))
            } catch {
                return
            }
            await self?.reloadExternalBoard()
        }
    }

    private func reloadExternalBoard() async {
        do {
            let loaded = try await repository.load()
            guard loaded != board else { return }
            board = loaded
            undoStack.removeAll()
            lastReceipt = MutationReceipt(
                summary: "Reloaded board changes from another process.",
                affectedEntityIDs: []
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
