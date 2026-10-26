import Foundation
import ManuscriptDomain

public struct AgentCommandEnvelope: Codable, Sendable {
    public let version: Int
    public let commandID: UUID
    public let type: String
    public let payload: JSONValue
    public let requestedAt: Date?
    public let source: String?

    enum CodingKeys: String, CodingKey {
        case version
        case commandID = "commandId"
        case type
        case payload
        case requestedAt
        case source
    }

    public init(
        version: Int = 1,
        commandID: UUID = UUID(),
        type: String,
        payload: JSONValue,
        requestedAt: Date? = nil,
        source: String? = nil
    ) {
        self.version = version
        self.commandID = commandID
        self.type = type
        self.payload = payload
        self.requestedAt = requestedAt
        self.source = source
    }
}

public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

public enum AgentCommandCodecError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case unsupportedCommand(String)
    case malformedPayload(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version):
            "Unsupported agent command version: \(version)."
        case let .unsupportedCommand(command):
            "Unsupported agent command: \(command)."
        case let .malformedPayload(reason):
            "Malformed command payload: \(reason)"
        }
    }
}

public enum AgentCommandCodec {
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    public static func makeEncoder(prettyPrinted: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return encoder
    }

    public static func decodeEnvelope(from data: Data) throws -> AgentCommandEnvelope {
        try makeDecoder().decode(AgentCommandEnvelope.self, from: data)
    }

    public static func command(from envelope: AgentCommandEnvelope) throws -> BoardCommand {
        guard envelope.version == 1 else {
            throw AgentCommandCodecError.unsupportedVersion(envelope.version)
        }

        let payloadData = try makeEncoder().encode(envelope.payload)
        let decoder = makeDecoder()

        do {
            switch envelope.type {
            case "manuscript.create":
                let payload = try decoder.decode(CreateManuscriptPayload.self, from: payloadData)
                return .createManuscript(
                    id: ManuscriptID(payload.id ?? UUID()),
                    title: payload.title,
                    shortTitle: payload.shortTitle,
                    tags: payload.tags ?? [],
                    readiness: payload.readiness ?? .incomplete,
                    createdAt: payload.createdAt ?? envelope.requestedAt ?? .now
                )

            case "manuscript.update":
                let payload = try decoder.decode(UpdateManuscriptPayload.self, from: payloadData)
                return .updateManuscript(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    title: payload.title,
                    shortTitle: payload.shortTitle,
                    tags: payload.tags ?? []
                )

            case "manuscript.position.set":
                let payload = try decoder.decode(MoveManuscriptPayload.self, from: payloadData)
                return .moveManuscript(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    toPosition: payload.position
                )

            case "manuscript.readiness.set":
                let payload = try decoder.decode(SetManuscriptReadinessPayload.self, from: payloadData)
                return .setManuscriptReadiness(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    readiness: payload.readiness,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now
                )

            case "manuscript.archive.set":
                let payload = try decoder.decode(ArchiveManuscriptPayload.self, from: payloadData)
                return .setManuscriptArchived(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    archived: payload.archived,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now
                )

            case "manuscript.delete":
                let payload = try decoder.decode(DeleteManuscriptPayload.self, from: payloadData)
                return .deleteManuscript(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    permanently: payload.confirmPermanentDeletion
                )

            case "journal.create":
                let payload = try decoder.decode(CreateJournalPayload.self, from: payloadData)
                return .createJournal(
                    id: JournalID(payload.id ?? UUID()),
                    name: payload.name,
                    rank: payload.rank,
                    metrics: JournalMetrics(
                        impactFactor: payload.impactFactor,
                        quartile: payload.quartile,
                        category: payload.category,
                        averageDecisionDays: payload.averageDecisionDays,
                        partitions: payload.partitions ?? []
                    ),
                    issn: payload.issn,
                    eISSN: payload.eISSN,
                    tags: payload.tags ?? [],
                    createdAt: payload.createdAt ?? envelope.requestedAt ?? .now
                )

            case "journal.rename":
                let payload = try decoder.decode(RenameJournalPayload.self, from: payloadData)
                return .renameJournal(
                    journalID: JournalID(payload.journalId),
                    newName: payload.newName,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now
                )

            case "journal.rank.set":
                let payload = try decoder.decode(MoveJournalPayload.self, from: payloadData)
                return .moveJournal(
                    journalID: JournalID(payload.journalId),
                    toRank: payload.rank
                )

            case "journal.metadata.update":
                let payload = try decoder.decode(UpdateJournalMetadataPayload.self, from: payloadData)
                return .updateJournalMetadata(
                    journalID: JournalID(payload.journalId),
                    metrics: JournalMetrics(
                        impactFactor: payload.impactFactor,
                        quartile: payload.quartile,
                        category: payload.category,
                        averageDecisionDays: payload.averageDecisionDays,
                        partitions: payload.partitions ?? []
                    ),
                    issn: payload.issn,
                    eISSN: payload.eISSN,
                    tags: payload.tags ?? []
                )

            case "journal.archive.set":
                let payload = try decoder.decode(ArchiveJournalPayload.self, from: payloadData)
                return .setJournalArchived(
                    journalID: JournalID(payload.journalId),
                    archived: payload.archived,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now
                )

            case "journal.delete":
                let payload = try decoder.decode(DeleteJournalPayload.self, from: payloadData)
                return .deleteJournal(
                    journalID: JournalID(payload.journalId),
                    permanently: payload.confirmPermanentDeletion
                )

            case "target.set":
                let payload = try decoder.decode(TargetPayload.self, from: payloadData)
                return .setTarget(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    journalID: JournalID(payload.journalId),
                    priority: payload.priority,
                    note: payload.note
                )

            case "target.remove":
                let payload = try decoder.decode(PairPayload.self, from: payloadData)
                return .removeTarget(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    journalID: JournalID(payload.journalId)
                )

            case "submission.record":
                let payload = try decoder.decode(SubmissionPayload.self, from: payloadData)
                return .recordSubmission(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    journalID: JournalID(payload.journalId),
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now,
                    note: payload.note
                )

            case "submission.status.record":
                let payload = try decoder.decode(StatusPayload.self, from: payloadData)
                guard payload.status != .submitted else {
                    throw AgentCommandCodecError.malformedPayload("Use submission.record for submitted status.")
                }
                return .recordStatus(
                    manuscriptID: ManuscriptID(payload.manuscriptId),
                    journalID: JournalID(payload.journalId),
                    kind: payload.status,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now,
                    note: payload.note
                )

            case "submission.event.void":
                let payload = try decoder.decode(VoidEventPayload.self, from: payloadData)
                return .voidSubmissionEvent(
                    eventID: SubmissionEventID(payload.eventId),
                    reason: payload.reason,
                    occurredAt: payload.occurredAt ?? envelope.requestedAt ?? .now
                )

            case "submission.event.amend":
                let payload = try decoder.decode(AmendEventPayload.self, from: payloadData)
                return .amendSubmissionEvent(
                    eventID: SubmissionEventID(payload.eventId),
                    occurredAt: payload.occurredAt,
                    note: payload.note,
                    reason: payload.reason,
                    amendedAt: payload.amendedAt ?? envelope.requestedAt ?? .now
                )

            case "relationship.create":
                let payload = try decoder.decode(RelationshipPayload.self, from: payloadData)
                return .createRelationship(
                    id: RelationshipID(payload.id ?? UUID()),
                    firstManuscriptID: ManuscriptID(payload.firstManuscriptId),
                    secondManuscriptID: ManuscriptID(payload.secondManuscriptId),
                    direction: payload.direction ?? .undirected,
                    statement: payload.statement,
                    createdAt: payload.createdAt ?? envelope.requestedAt ?? .now
                )

            case "relationship.remove":
                let payload = try decoder.decode(RemoveRelationshipPayload.self, from: payloadData)
                return .removeRelationship(relationshipID: RelationshipID(payload.relationshipId))

            case "relationship.update":
                let payload = try decoder.decode(UpdateRelationshipPayload.self, from: payloadData)
                return .updateRelationship(
                    relationshipID: RelationshipID(payload.relationshipId),
                    direction: payload.direction,
                    statement: payload.statement
                )

            default:
                throw AgentCommandCodecError.unsupportedCommand(envelope.type)
            }
        } catch let error as AgentCommandCodecError {
            throw error
        } catch {
            throw AgentCommandCodecError.malformedPayload(error.localizedDescription)
        }
    }
}

private struct CreateManuscriptPayload: Decodable {
    let id: UUID?
    let title: String
    let shortTitle: String
    let tags: [String]?
    let readiness: ManuscriptReadiness?
    let createdAt: Date?
}

private struct UpdateManuscriptPayload: Decodable {
    let manuscriptId: UUID
    let title: String
    let shortTitle: String
    let tags: [String]?
}

private struct MoveManuscriptPayload: Decodable {
    let manuscriptId: UUID
    let position: Int
}

private struct SetManuscriptReadinessPayload: Decodable {
    let manuscriptId: UUID
    let readiness: ManuscriptReadiness
    let occurredAt: Date?
}

private struct ArchiveManuscriptPayload: Decodable {
    let manuscriptId: UUID
    let archived: Bool
    let occurredAt: Date?
}

private struct DeleteManuscriptPayload: Decodable {
    let manuscriptId: UUID
    let confirmPermanentDeletion: Bool
}

private struct CreateJournalPayload: Decodable {
    let id: UUID?
    let name: String
    let rank: Int
    let impactFactor: Double?
    let quartile: String?
    let category: String?
    let averageDecisionDays: Int?
    let partitions: [JournalPartition]?
    let issn: String?
    let eISSN: String?
    let tags: [String]?
    let createdAt: Date?
}

private struct RenameJournalPayload: Decodable {
    let journalId: UUID
    let newName: String
    let occurredAt: Date?
}

private struct MoveJournalPayload: Decodable {
    let journalId: UUID
    let rank: Int
}

private struct UpdateJournalMetadataPayload: Decodable {
    let journalId: UUID
    let impactFactor: Double?
    let quartile: String?
    let category: String?
    let averageDecisionDays: Int?
    let partitions: [JournalPartition]?
    let issn: String?
    let eISSN: String?
    let tags: [String]?
}

private struct ArchiveJournalPayload: Decodable {
    let journalId: UUID
    let archived: Bool
    let occurredAt: Date?
}

private struct DeleteJournalPayload: Decodable {
    let journalId: UUID
    let confirmPermanentDeletion: Bool
}

private struct PairPayload: Decodable {
    let manuscriptId: UUID
    let journalId: UUID
}

private struct TargetPayload: Decodable {
    let manuscriptId: UUID
    let journalId: UUID
    let priority: Int
    let note: String?
}

private struct SubmissionPayload: Decodable {
    let manuscriptId: UUID
    let journalId: UUID
    let occurredAt: Date?
    let note: String?
}

private struct StatusPayload: Decodable {
    let manuscriptId: UUID
    let journalId: UUID
    let status: SubmissionEventKind
    let occurredAt: Date?
    let note: String?
}

private struct VoidEventPayload: Decodable {
    let eventId: UUID
    let reason: String
    let occurredAt: Date?
}

private struct AmendEventPayload: Decodable {
    let eventId: UUID
    let occurredAt: Date
    let note: String?
    let reason: String
    let amendedAt: Date?
}

private struct RelationshipPayload: Decodable {
    let id: UUID?
    let firstManuscriptId: UUID
    let secondManuscriptId: UUID
    let direction: RelationshipDirection?
    let statement: String
    let createdAt: Date?
}

private struct RemoveRelationshipPayload: Decodable {
    let relationshipId: UUID
}

private struct UpdateRelationshipPayload: Decodable {
    let relationshipId: UUID
    let direction: RelationshipDirection
    let statement: String
}
