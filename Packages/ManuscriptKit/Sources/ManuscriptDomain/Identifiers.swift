import Foundation

public struct JournalID: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public var description: String { rawValue.uuidString }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct ManuscriptID: Hashable, Codable, Sendable, Identifiable, CustomStringConvertible {
    public let rawValue: UUID
    public var id: UUID { rawValue }
    public var description: String { rawValue.uuidString }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct SubmissionEventID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public struct RelationshipID: Hashable, Codable, Sendable, Identifiable {
    public let rawValue: UUID
    public var id: UUID { rawValue }

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}
