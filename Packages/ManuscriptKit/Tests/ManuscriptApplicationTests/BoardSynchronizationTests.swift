import Foundation
import ManuscriptApplication
import ManuscriptDomain
import ManuscriptInfrastructure
import XCTest

final class BoardSynchronizationTests: XCTestCase {
    func testFirstMutationCreatesAMissingBoardWithoutBypassingConflictChecks() async throws {
        let fixture = try TemporaryBoardFixture()
        defer { fixture.remove() }
        let repository = JSONBoardRepository(fileURL: fixture.fileURL)
        let empty = try await repository.load()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
        let mutation = try await BoardMutationExecutor.execute(
            .createManuscript(
                id: ManuscriptID(), title: "First manuscript", shortTitle: "First",
                tags: [], createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            repository: repository
        )
        XCTAssertEqual(mutation.board.manuscripts.count, 1)
        do {
            try await repository.save(empty, replacing: empty)
            XCTFail("A second first-writer must not replace the newly created board.")
        } catch {
            XCTAssertEqual(error as? BoardRepositoryError, .writeConflict)
        }
    }

    func testConditionalSaveRejectsAStaleSnapshot() async throws {
        let fixture = try TemporaryBoardFixture()
        defer { fixture.remove() }

        let firstRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        let secondRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        let seed = BoardSnapshot(modifiedAt: Date(timeIntervalSince1970: 1_000))
        try await firstRepository.save(seed)

        let firstBase = try await firstRepository.load()
        let staleBase = try await secondRepository.load()
        var firstUpdate = firstBase
        _ = try BoardReducer.apply(
            .createManuscript(
                id: ManuscriptID(),
                title: "First",
                shortTitle: "First",
                tags: [],
                createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            to: &firstUpdate
        )
        try await firstRepository.save(firstUpdate, replacing: firstBase)

        var staleUpdate = staleBase
        _ = try BoardReducer.apply(
            .createJournal(
                id: JournalID(),
                name: "Stale journal",
                rank: 1,
                metrics: JournalMetrics(),
                issn: nil,
                eISSN: nil,
                tags: [],
                createdAt: Date(timeIntervalSince1970: 3_000)
            ),
            to: &staleUpdate
        )

        do {
            try await secondRepository.save(staleUpdate, replacing: staleBase)
            XCTFail("A stale conditional save must not overwrite a newer board.")
        } catch {
            XCTAssertEqual(error as? BoardRepositoryError, .writeConflict)
        }
    }

    func testMutationExecutorRetriesAndMergesConcurrentChanges() async throws {
        let fixture = try TemporaryBoardFixture()
        defer { fixture.remove() }

        let firstRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        let secondRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        try await firstRepository.save(BoardSnapshot(modifiedAt: Date(timeIntervalSince1970: 1_000)))
        let sharedBase = try await firstRepository.load()

        _ = try await BoardMutationExecutor.execute(
            .createManuscript(
                id: ManuscriptID(),
                title: "Concurrent manuscript",
                shortTitle: "Manuscript",
                tags: [],
                createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            initialBoard: sharedBase,
            repository: firstRepository
        )

        _ = try await BoardMutationExecutor.execute(
            .createJournal(
                id: JournalID(),
                name: "Concurrent journal",
                rank: 1,
                metrics: JournalMetrics(),
                issn: nil,
                eISSN: nil,
                tags: [],
                createdAt: Date(timeIntervalSince1970: 3_000)
            ),
            initialBoard: sharedBase,
            repository: secondRepository
        )

        let merged = try await firstRepository.load()
        XCTAssertEqual(merged.manuscripts.map(\.shortTitle), ["Manuscript"])
        XCTAssertEqual(merged.journals.map(\.currentName), ["Concurrent journal"])
    }

    @MainActor
    func testCommandServiceReloadsAnExternalRepositoryMutation() async throws {
        let fixture = try TemporaryBoardFixture()
        defer { fixture.remove() }

        let appRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        let agentRepository = JSONBoardRepository(fileURL: fixture.fileURL)
        try await appRepository.save(BoardSnapshot(modifiedAt: Date(timeIntervalSince1970: 1_000)))

        let store = BoardCommandService(repository: appRepository)
        await store.load()
        XCTAssertTrue(store.board.manuscripts.isEmpty)

        let manuscriptID = ManuscriptID()
        _ = try await BoardMutationExecutor.execute(
            .createManuscript(
                id: manuscriptID,
                title: "Live external update",
                shortTitle: "Live",
                tags: [],
                createdAt: Date(timeIntervalSince1970: 2_000)
            ),
            repository: agentRepository
        )

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !store.board.manuscripts.contains(where: { $0.id == manuscriptID }), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }

        XCTAssertTrue(store.board.manuscripts.contains(where: { $0.id == manuscriptID }))
        XCTAssertEqual(store.lastReceipt?.summary, "Reloaded board changes from another process.")
    }

    @MainActor
    func testCommandServiceDoesNotTreatItsOwnSaveAsAnExternalChange() async throws {
        let fixture = try TemporaryBoardFixture()
        defer { fixture.remove() }

        let repository = JSONBoardRepository(fileURL: fixture.fileURL)
        try await repository.save(BoardSnapshot(modifiedAt: Date(timeIntervalSince1970: 1_000)))
        let store = BoardCommandService(repository: repository)
        await store.load()

        let receipt = try await store.execute(
            .createManuscript(
                id: ManuscriptID(),
                title: "Local update",
                shortTitle: "Local",
                tags: [],
                createdAt: Date(timeIntervalSince1970: 2_000)
            )
        )
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertTrue(store.canUndo)
        XCTAssertEqual(store.lastReceipt, receipt)
        XCTAssertEqual(store.board.manuscripts.map(\.shortTitle), ["Local"])
    }
}

private struct TemporaryBoardFixture: @unchecked Sendable {
    let directoryURL: URL
    let fileURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManuscriptMatrixTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("board-v1.json", isDirectory: false)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
