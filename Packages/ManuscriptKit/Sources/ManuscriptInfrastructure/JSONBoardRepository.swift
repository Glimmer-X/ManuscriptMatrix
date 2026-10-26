import Darwin
import Dispatch
import Foundation
import ManuscriptApplication
import ManuscriptDomain

public actor JSONBoardRepository: BoardRepository {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func load() async throws -> BoardSnapshot {
        try loadFromDisk() ?? .empty
    }

    public func save(_ snapshot: BoardSnapshot, replacing expected: BoardSnapshot?) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let lockURL = directory.appendingPathComponent("board-v1.lock", isDirectory: false)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { Darwin.close(descriptor) }

        guard Self.setAdvisoryLock(F_WRLCK, on: descriptor, command: F_SETLKW) == 0 else {
            throw Self.posixError()
        }
        defer { _ = Self.setAdvisoryLock(F_UNLCK, on: descriptor, command: F_SETLK) }

        if let expected {
            // A missing file represents the same empty snapshot returned by load().
            // Recheck under the lock so a concurrent first writer is still detected.
            let current = try loadFromDisk() ?? .empty
            guard current == expected else { throw BoardRepositoryError.writeConflict }
        }

        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    public func changes() async -> AsyncStream<Void> {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            return AsyncStream { $0.finish() }
        }

        guard let watcher = DirectoryChangeWatcher(directoryURL: directory) else {
            return AsyncStream { $0.finish() }
        }

        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            watcher.start {
                continuation.yield()
            }
            continuation.onTermination = { _ in
                watcher.cancel()
            }
        }
    }

    private func loadFromDisk() throws -> BoardSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(BoardSnapshot.self, from: data)
    }

    private nonisolated static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private nonisolated static func setAdvisoryLock(
        _ type: Int32,
        on descriptor: Int32,
        command: Int32
    ) -> Int32 {
        var lock = flock()
        lock.l_type = Int16(type)
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0
        return Darwin.fcntl(descriptor, command, &lock)
    }

    public nonisolated static func defaultFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return applicationSupport
            .appendingPathComponent("ManuscriptMatrix", isDirectory: true)
            .appendingPathComponent("board-v1.json", isDirectory: false)
    }
}

public actor InMemoryBoardRepository: BoardRepository {
    private var snapshot: BoardSnapshot

    public init(snapshot: BoardSnapshot = .empty) {
        self.snapshot = snapshot
    }

    public func load() async throws -> BoardSnapshot { snapshot }

    public func save(_ snapshot: BoardSnapshot, replacing expected: BoardSnapshot?) async throws {
        if let expected, self.snapshot != expected {
            throw BoardRepositoryError.writeConflict
        }
        self.snapshot = snapshot
    }
}

private final class DirectoryChangeWatcher: @unchecked Sendable {
    private let descriptor: Int32
    private let source: DispatchSourceFileSystemObject
    private let lock = NSLock()
    private var isCancelled = false

    init?(directoryURL: URL) {
        let descriptor = Darwin.open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.descriptor = descriptor
        source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: DispatchQueue(label: "io.manuscriptmatrix.board-watcher", qos: .utility)
        )
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            Darwin.close(descriptor)
        }
        source.resume()
    }

    func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        isCancelled = true
        source.cancel()
    }
}
