import Foundation
import ManuscriptDomain

public enum BoardCommand: Sendable {
    case createManuscript(
        id: ManuscriptID,
        title: String,
        shortTitle: String,
        tags: [String],
        readiness: ManuscriptReadiness = .incomplete,
        createdAt: Date
    )
    case updateManuscript(
        manuscriptID: ManuscriptID,
        title: String,
        shortTitle: String,
        tags: [String]
    )
    case moveManuscript(manuscriptID: ManuscriptID, toPosition: Int)
    case setManuscriptReadiness(
        manuscriptID: ManuscriptID,
        readiness: ManuscriptReadiness,
        occurredAt: Date
    )
    case setManuscriptArchived(
        manuscriptID: ManuscriptID,
        archived: Bool,
        occurredAt: Date
    )
    case deleteManuscript(manuscriptID: ManuscriptID, permanently: Bool)
    case createJournal(
        id: JournalID,
        name: String,
        rank: Int,
        metrics: JournalMetrics,
        issn: String?,
        eISSN: String?,
        tags: [String],
        createdAt: Date
    )
    case renameJournal(journalID: JournalID, newName: String, occurredAt: Date)
    case moveJournal(journalID: JournalID, toRank: Int)
    case updateJournalMetadata(
        journalID: JournalID,
        metrics: JournalMetrics,
        issn: String?,
        eISSN: String?,
        tags: [String]
    )
    case setJournalArchived(
        journalID: JournalID,
        archived: Bool,
        occurredAt: Date
    )
    case deleteJournal(journalID: JournalID, permanently: Bool)
    case setTarget(
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        priority: Int,
        note: String?
    )
    case removeTarget(manuscriptID: ManuscriptID, journalID: JournalID)
    case recordSubmission(
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        occurredAt: Date,
        note: String?
    )
    case recordStatus(
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        kind: SubmissionEventKind,
        occurredAt: Date,
        note: String?
    )
    case voidSubmissionEvent(
        eventID: SubmissionEventID,
        reason: String,
        occurredAt: Date
    )
    case amendSubmissionEvent(
        eventID: SubmissionEventID,
        occurredAt: Date,
        note: String?,
        reason: String,
        amendedAt: Date
    )
    case createRelationship(
        id: RelationshipID,
        firstManuscriptID: ManuscriptID,
        secondManuscriptID: ManuscriptID,
        direction: RelationshipDirection,
        statement: String,
        createdAt: Date
    )
    case updateRelationship(
        relationshipID: RelationshipID,
        direction: RelationshipDirection,
        statement: String
    )
    case removeRelationship(relationshipID: RelationshipID)
}

public struct MutationReceipt: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let appliedAt: Date
    public let summary: String
    public let affectedEntityIDs: [String]

    public init(
        id: UUID = UUID(),
        appliedAt: Date = .now,
        summary: String,
        affectedEntityIDs: [String]
    ) {
        self.id = id
        self.appliedAt = appliedAt
        self.summary = summary
        self.affectedEntityIDs = affectedEntityIDs
    }
}

public enum BoardCommandError: LocalizedError, Equatable {
    case manuscriptNotFound
    case journalNotFound
    case relationshipNotFound
    case invalidTitle
    case invalidManuscriptPosition
    case invalidName
    case invalidPriority
    case manuscriptAlreadyActive
    case manuscriptAlreadyAccepted
    case journalIsNotActiveSubmission
    case invalidStatusTransition
    case relationshipToSelf
    case invalidRelationshipStatement
    case submissionEventNotFound
    case eventAlreadyVoided
    case invalidVoidReason
    case invalidAmendmentReason
    case manuscriptHasLiveSubmission
    case journalHasLiveSubmissions
    case manuscriptArchived
    case journalArchived
    case identityAlreadyExists
    case deletionConfirmationRequired
    case invalidJournalMetrics
    case invalidJournalPartition

    public var errorDescription: String? {
        switch self {
        case .manuscriptNotFound: "Manuscript not found."
        case .journalNotFound: "Journal not found."
        case .relationshipNotFound: "Relationship not found."
        case .invalidTitle: "A manuscript title and short title are required."
        case .invalidManuscriptPosition: "Manuscript position must be at least one."
        case .invalidName: "A journal name is required."
        case .invalidPriority: "Target priority must be at least one."
        case .manuscriptAlreadyActive: "This manuscript already has a live submission."
        case .manuscriptAlreadyAccepted: "An accepted manuscript cannot be submitted again."
        case .journalIsNotActiveSubmission: "The selected journal is not this manuscript's live submission."
        case .invalidStatusTransition: "This status cannot be recorded in the current state."
        case .relationshipToSelf: "A manuscript cannot be related to itself."
        case .invalidRelationshipStatement: "A relationship statement is required."
        case .submissionEventNotFound: "Submission event not found."
        case .eventAlreadyVoided: "This submission event has already been voided."
        case .invalidVoidReason: "A reason is required when correcting history."
        case .invalidAmendmentReason: "A reason is required when amending an event."
        case .manuscriptHasLiveSubmission: "A manuscript with a live submission cannot be archived."
        case .journalHasLiveSubmissions: "A journal with live submissions cannot be archived."
        case .manuscriptArchived: "Restore this manuscript before using it in a plan or submission."
        case .journalArchived: "Restore this journal before using it in a plan or submission."
        case .identityAlreadyExists: "An entity with this stable identifier already exists."
        case .deletionConfirmationRequired: "Permanent deletion requires explicit confirmation."
        case .invalidJournalMetrics: "Journal metrics must use non-negative IF and positive decision days."
        case .invalidJournalPartition: "Journal partitions must use JCR Q1–Q4, CCF A–C, or CAS/新锐 1区–4区; years must be between 1900 and 2100."
        }
    }
}
