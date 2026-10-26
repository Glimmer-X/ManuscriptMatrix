import Foundation

public enum JournalPartitionScheme: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case jcr = "JCR"
    case ccf = "CCF"
    case cas = "CAS"
    case emerging = "新锐"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .jcr: "JCR"
        case .ccf: "CCF"
        case .cas: "中科院（CAS）"
        case .emerging: "新锐"
        }
    }

    public var allowedValues: [String] {
        switch self {
        case .jcr: ["Q1", "Q2", "Q3", "Q4"]
        case .ccf: ["A", "B", "C"]
        case .cas, .emerging: ["1区", "2区", "3区", "4区"]
        }
    }

    public var defaultValue: String { allowedValues[0] }

    public static func resolve(_ rawValue: String) -> Self? {
        let clean = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.caseInsensitiveCompare("JCR") == .orderedSame { return .jcr }
        if clean.caseInsensitiveCompare("CCF") == .orderedSame { return .ccf }
        if clean.caseInsensitiveCompare("CAS") == .orderedSame || clean == "中科院" { return .cas }
        if clean == "新锐" { return .emerging }
        return nil
    }

    /// Canonicalizes supported values while keeping the runtime vocabulary finite.
    public func canonicalValue(_ rawValue: String) -> String? {
        let clean = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        switch self {
        case .jcr:
            let upper = clean.uppercased()
            return allowedValues.contains(upper) ? upper : nil
        case .ccf:
            let upper = clean.uppercased()
            return allowedValues.contains(upper) ? upper : nil
        case .cas, .emerging:
            return allowedValues.contains(clean) ? clean : nil
        }
    }

    /// Read-time compatibility for data created before finite partition options existed.
    func migratedValue(_ rawValue: String) -> String? {
        if let canonical = canonicalValue(rawValue) { return canonical }
        guard self == .jcr else { return nil }
        return switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "1区": "Q1"
        case "2区": "Q2"
        case "3区": "Q3"
        case "4区": "Q4"
        default: nil
        }
    }
}

public struct JournalNameRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var effectiveFrom: Date
    public var effectiveTo: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        effectiveFrom: Date,
        effectiveTo: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.effectiveFrom = effectiveFrom
        self.effectiveTo = effectiveTo
    }
}

public struct JournalPartition: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var scheme: String
    public var year: Int?
    public var value: String
    public var category: String?

    public init(
        id: UUID = UUID(),
        scheme: String,
        year: Int? = nil,
        value: String,
        category: String? = nil
    ) {
        self.id = id
        self.scheme = scheme
        self.year = year
        self.value = value
        self.category = category
    }

    public var displayLabel: String {
        [scheme, year.map(String.init), value]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    var migratedToFiniteVocabulary: JournalPartition? {
        guard
            let resolvedScheme = JournalPartitionScheme.resolve(scheme),
            let resolvedValue = resolvedScheme.migratedValue(value)
        else { return nil }
        return JournalPartition(
            id: id,
            scheme: resolvedScheme.rawValue,
            year: year,
            value: resolvedValue,
            category: category
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case scheme
        case year
        case value
        case category
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        scheme = try container.decode(String.self, forKey: .scheme)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        value = try container.decode(String.self, forKey: .value)
        category = try container.decodeIfPresent(String.self, forKey: .category)
    }
}

public struct JournalMetrics: Codable, Hashable, Sendable {
    public var impactFactor: Double?
    /// Legacy single JCR value retained for schema-v1 compatibility.
    public var quartile: String?
    public var category: String?
    public var averageDecisionDays: Int?
    public var partitions: [JournalPartition]

    public init(
        impactFactor: Double? = nil,
        quartile: String? = nil,
        category: String? = nil,
        averageDecisionDays: Int? = nil,
        partitions: [JournalPartition] = []
    ) {
        self.impactFactor = impactFactor
        self.quartile = quartile
        self.category = category
        self.averageDecisionDays = averageDecisionDays
        self.partitions = partitions.isEmpty && quartile != nil
            ? [JournalPartition(scheme: "JCR", value: quartile ?? "")]
            : partitions
    }

    enum CodingKeys: String, CodingKey {
        case impactFactor
        case quartile
        case category
        case averageDecisionDays
        case partitions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        impactFactor = try container.decodeIfPresent(Double.self, forKey: .impactFactor)
        let decodedQuartile = try container.decodeIfPresent(String.self, forKey: .quartile)
        quartile = decodedQuartile.flatMap { JournalPartitionScheme.jcr.migratedValue($0) }
        category = try container.decodeIfPresent(String.self, forKey: .category)
        averageDecisionDays = try container.decodeIfPresent(Int.self, forKey: .averageDecisionDays)
        let decoded = try container.decodeIfPresent([JournalPartition].self, forKey: .partitions) ?? []
        let migrated = decoded.compactMap(\.migratedToFiniteVocabulary)
        partitions = migrated.isEmpty && quartile != nil
            ? [JournalPartition(scheme: "JCR", value: quartile ?? "")]
            : migrated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(impactFactor, forKey: .impactFactor)
        try container.encodeIfPresent(quartile, forKey: .quartile)
        try container.encodeIfPresent(category, forKey: .category)
        try container.encodeIfPresent(averageDecisionDays, forKey: .averageDecisionDays)
        try container.encode(partitions, forKey: .partitions)
    }
}

public struct Journal: Identifiable, Codable, Hashable, Sendable {
    public let id: JournalID
    public var currentName: String
    public var rank: Int
    public var issn: String?
    public var eISSN: String?
    public var tags: [String]
    public var metrics: JournalMetrics
    public var nameHistory: [JournalNameRecord]
    public var createdAt: Date
    public var archivedAt: Date?

    public init(
        id: JournalID = JournalID(),
        currentName: String,
        rank: Int,
        issn: String? = nil,
        eISSN: String? = nil,
        tags: [String] = [],
        metrics: JournalMetrics = JournalMetrics(),
        nameHistory: [JournalNameRecord]? = nil,
        createdAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.currentName = currentName
        self.rank = rank
        self.issn = issn
        self.eISSN = eISSN
        self.tags = tags
        self.metrics = metrics
        self.nameHistory = nameHistory ?? [
            JournalNameRecord(name: currentName, effectiveFrom: createdAt)
        ]
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }
}

public enum ManuscriptReadiness: String, Codable, CaseIterable, Hashable, Sendable {
    case incomplete
    case experimenting
    case conceptualizing
    case writing
    case readyToSubmit

    public var isComplete: Bool { self == .readyToSubmit }

    public var progressFraction: Double {
        switch self {
        case .incomplete: 0.12
        case .experimenting: 0.34
        case .conceptualizing: 0.56
        case .writing: 0.78
        case .readyToSubmit: 1
        }
    }
}

public struct Manuscript: Identifiable, Codable, Hashable, Sendable {
    public let id: ManuscriptID
    public var title: String
    public var shortTitle: String
    public var tags: [String]
    public var readiness: ManuscriptReadiness
    public var readinessUpdatedAt: Date
    public var displayOrder: Int?
    public var createdAt: Date
    public var archivedAt: Date?

    public init(
        id: ManuscriptID = ManuscriptID(),
        title: String,
        shortTitle: String,
        tags: [String] = [],
        readiness: ManuscriptReadiness = .readyToSubmit,
        readinessUpdatedAt: Date? = nil,
        displayOrder: Int? = nil,
        createdAt: Date = .now,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.shortTitle = shortTitle
        self.tags = tags
        self.readiness = readiness
        self.readinessUpdatedAt = readinessUpdatedAt ?? createdAt
        self.displayOrder = displayOrder
        self.createdAt = createdAt
        self.archivedAt = archivedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case shortTitle
        case tags
        case readiness
        case readinessUpdatedAt
        case displayOrder
        case createdAt
        case archivedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(ManuscriptID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        shortTitle = try container.decode(String.self, forKey: .shortTitle)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        archivedAt = try container.decodeIfPresent(Date.self, forKey: .archivedAt)

        // Schema-v1 boards predate readiness. Treat those manuscripts as ready so
        // upgrading never silently moves an existing portfolio into "incomplete".
        readiness = try container.decodeIfPresent(ManuscriptReadiness.self, forKey: .readiness) ?? .readyToSubmit
        readinessUpdatedAt = try container.decodeIfPresent(Date.self, forKey: .readinessUpdatedAt) ?? createdAt
        displayOrder = try container.decodeIfPresent(Int.self, forKey: .displayOrder)
    }
}

public enum SubmissionEventKind: String, Codable, CaseIterable, Hashable, Sendable {
    case submitted
    case resubmitted
    case majorRevision
    case minorRevision
    case rejectAndResubmit
    case rejected
    case accepted
    case withdrawn

    public var endsLiveSubmission: Bool {
        switch self {
        case .rejected, .accepted, .withdrawn:
            true
        default:
            false
        }
    }
}

public struct SubmissionEventAmendment: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let previousOccurredAt: Date
    public let newOccurredAt: Date
    public let previousNote: String?
    public let newNote: String?
    public let reason: String
    public let amendedAt: Date

    public init(
        id: UUID = UUID(),
        previousOccurredAt: Date,
        newOccurredAt: Date,
        previousNote: String?,
        newNote: String?,
        reason: String,
        amendedAt: Date = .now
    ) {
        self.id = id
        self.previousOccurredAt = previousOccurredAt
        self.newOccurredAt = newOccurredAt
        self.previousNote = previousNote
        self.newNote = newNote
        self.reason = reason
        self.amendedAt = amendedAt
    }
}

public struct SubmissionEvent: Identifiable, Codable, Hashable, Sendable {
    public let id: SubmissionEventID
    public let manuscriptID: ManuscriptID
    public let journalID: JournalID
    public let journalNameSnapshot: String
    public let kind: SubmissionEventKind
    public var occurredAt: Date
    public let recordedAt: Date
    public var note: String?
    public var voidedAt: Date?
    public var voidReason: String?
    public var amendments: [SubmissionEventAmendment]?

    public init(
        id: SubmissionEventID = SubmissionEventID(),
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        journalNameSnapshot: String,
        kind: SubmissionEventKind,
        occurredAt: Date,
        recordedAt: Date = .now,
        note: String? = nil,
        voidedAt: Date? = nil,
        voidReason: String? = nil,
        amendments: [SubmissionEventAmendment]? = nil
    ) {
        self.id = id
        self.manuscriptID = manuscriptID
        self.journalID = journalID
        self.journalNameSnapshot = journalNameSnapshot
        self.kind = kind
        self.occurredAt = occurredAt
        self.recordedAt = recordedAt
        self.note = note
        self.voidedAt = voidedAt
        self.voidReason = voidReason
        self.amendments = amendments
    }

    public var isVoided: Bool { voidedAt != nil }
    public var amendmentHistory: [SubmissionEventAmendment] { amendments ?? [] }
}

public struct TargetChoice: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(manuscriptID.description):\(journalID.description)" }
    public let manuscriptID: ManuscriptID
    public let journalID: JournalID
    public var priority: Int
    public var note: String?
    public var updatedAt: Date

    public init(
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        priority: Int,
        note: String? = nil,
        updatedAt: Date = .now
    ) {
        self.manuscriptID = manuscriptID
        self.journalID = journalID
        self.priority = priority
        self.note = note
        self.updatedAt = updatedAt
    }
}

public enum RelationshipDirection: String, Codable, Hashable, Sendable {
    case undirected
    case firstToSecond
    case secondToFirst
}

public struct ManuscriptRelationship: Identifiable, Codable, Hashable, Sendable {
    public let id: RelationshipID
    public let firstManuscriptID: ManuscriptID
    public let secondManuscriptID: ManuscriptID
    public var direction: RelationshipDirection
    public var statement: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: RelationshipID = RelationshipID(),
        firstManuscriptID: ManuscriptID,
        secondManuscriptID: ManuscriptID,
        direction: RelationshipDirection = .undirected,
        statement: String,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.firstManuscriptID = firstManuscriptID
        self.secondManuscriptID = secondManuscriptID
        self.direction = direction
        self.statement = statement
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func involves(_ manuscriptID: ManuscriptID) -> Bool {
        firstManuscriptID == manuscriptID || secondManuscriptID == manuscriptID
    }
}

public struct BoardSnapshot: Codable, Hashable, Sendable {
    public var schemaVersion: Int
    public var modifiedAt: Date
    public var journals: [Journal]
    public var manuscripts: [Manuscript]
    public var submissionEvents: [SubmissionEvent]
    public var targets: [TargetChoice]
    public var relationships: [ManuscriptRelationship]

    public init(
        schemaVersion: Int = 1,
        modifiedAt: Date = .now,
        journals: [Journal] = [],
        manuscripts: [Manuscript] = [],
        submissionEvents: [SubmissionEvent] = [],
        targets: [TargetChoice] = [],
        relationships: [ManuscriptRelationship] = []
    ) {
        self.schemaVersion = schemaVersion
        self.modifiedAt = modifiedAt
        self.journals = journals
        self.manuscripts = manuscripts
        self.submissionEvents = submissionEvents
        self.targets = targets
        self.relationships = relationships
    }

    public static let empty = BoardSnapshot()
}
