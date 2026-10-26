import Foundation

public enum ManuscriptStatus: String, Codable, Hashable, Sendable {
    case awaitingSubmission
    case submitted
    case majorRevision
    case minorRevision
    case rejectAndResubmit
    case accepted
}

public enum ManuscriptSituation: String, Codable, Hashable, Sendable {
    case incomplete
    case preparingSubmission
    case awaitingDecision
    case revision
    case rejected
    case accepted
}

public struct ManuscriptProjection: Hashable, Sendable {
    public let manuscriptID: ManuscriptID
    public let status: ManuscriptStatus
    public let readiness: ManuscriptReadiness
    public let activeJournalID: JournalID?
    public let liveStartedAt: Date?
    public let latestEvent: SubmissionEvent?

    public var isAccepted: Bool { status == .accepted }
    public var latestActionAt: Date? { latestEvent?.occurredAt ?? liveStartedAt }
    public var situation: ManuscriptSituation {
        switch status {
        case .submitted:
            .awaitingDecision
        case .majorRevision, .minorRevision, .rejectAndResubmit:
            .revision
        case .accepted:
            .accepted
        case .awaitingSubmission:
            if latestEvent?.kind == .rejected {
                .rejected
            } else if !readiness.isComplete {
                .incomplete
            } else {
                .preparingSubmission
            }
        }
    }

    public init(
        manuscriptID: ManuscriptID,
        status: ManuscriptStatus,
        readiness: ManuscriptReadiness,
        activeJournalID: JournalID?,
        liveStartedAt: Date?,
        latestEvent: SubmissionEvent?
    ) {
        self.manuscriptID = manuscriptID
        self.status = status
        self.readiness = readiness
        self.activeJournalID = activeJournalID
        self.liveStartedAt = liveStartedAt
        self.latestEvent = latestEvent
    }
}

public extension BoardSnapshot {
    var rankedJournals: [Journal] {
        journals.filter { $0.archivedAt == nil }.sorted {
            if $0.rank == $1.rank { return $0.currentName < $1.currentName }
            return $0.rank < $1.rank
        }
    }

    var visibleManuscripts: [Manuscript] {
        manuscripts
            .filter { $0.archivedAt == nil }
            .sorted { first, second in
                switch (first.displayOrder, second.displayOrder) {
                case let (.some(firstOrder), .some(secondOrder)):
                    if firstOrder == secondOrder { return first.createdAt < second.createdAt }
                    return firstOrder < secondOrder
                case (.some, .none):
                    return true
                case (.none, .some):
                    return false
                case (.none, .none):
                    return first.createdAt < second.createdAt
                }
            }
    }

    func manuscriptProjection(for manuscriptID: ManuscriptID) -> ManuscriptProjection {
        let readiness = manuscripts.first(where: { $0.id == manuscriptID })?.readiness ?? .readyToSubmit
        let events = submissionEvents
            .filter { $0.manuscriptID == manuscriptID && !$0.isVoided }
            .sorted {
                if $0.occurredAt == $1.occurredAt { return $0.recordedAt < $1.recordedAt }
                return $0.occurredAt < $1.occurredAt
            }

        var status: ManuscriptStatus = .awaitingSubmission
        var activeJournalID: JournalID?
        var liveStartedAt: Date?

        for event in events {
            switch event.kind {
            case .submitted:
                status = .submitted
                activeJournalID = event.journalID
                liveStartedAt = event.occurredAt
            case .resubmitted where activeJournalID == event.journalID:
                status = .submitted
                liveStartedAt = event.occurredAt
            case .majorRevision where activeJournalID == event.journalID:
                status = .majorRevision
            case .minorRevision where activeJournalID == event.journalID:
                status = .minorRevision
            case .rejectAndResubmit where activeJournalID == event.journalID:
                status = .rejectAndResubmit
            case .rejected where activeJournalID == event.journalID,
                 .withdrawn where activeJournalID == event.journalID:
                status = .awaitingSubmission
                activeJournalID = nil
                liveStartedAt = nil
            case .accepted where activeJournalID == event.journalID:
                status = .accepted
                activeJournalID = nil
                liveStartedAt = nil
            default:
                continue
            }
        }

        return ManuscriptProjection(
            manuscriptID: manuscriptID,
            status: status,
            readiness: readiness,
            activeJournalID: activeJournalID,
            liveStartedAt: liveStartedAt,
            latestEvent: events.last
        )
    }

    func events(for manuscriptID: ManuscriptID, journalID: JournalID? = nil) -> [SubmissionEvent] {
        submissionEvents
            .filter { event in
                event.manuscriptID == manuscriptID &&
                (journalID == nil || event.journalID == journalID)
            }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    func targets(for manuscriptID: ManuscriptID) -> [TargetChoice] {
        targets
            .filter { $0.manuscriptID == manuscriptID }
            .sorted { $0.priority < $1.priority }
    }

    func relationships(for manuscriptID: ManuscriptID) -> [ManuscriptRelationship] {
        relationships.filter { $0.involves(manuscriptID) }
    }
}

public extension SubmissionEvent {
    func previousSubmissionEvent(in events: [SubmissionEvent]) -> SubmissionEvent? {
        events
            .filter {
                $0.manuscriptID == manuscriptID &&
                    $0.journalID == journalID &&
                    !$0.isVoided &&
                    ($0.kind == .submitted || $0.kind == .resubmitted) &&
                    ($0.occurredAt < occurredAt || ($0.occurredAt == occurredAt && $0.recordedAt < recordedAt))
            }
            .max {
                if $0.occurredAt == $1.occurredAt { return $0.recordedAt < $1.recordedAt }
                return $0.occurredAt < $1.occurredAt
            }
    }

    func rejectionDecisionDays(in events: [SubmissionEvent]) -> Int? {
        guard kind == .rejected, !isVoided else { return nil }
        guard let start = previousSubmissionEvent(in: events) else { return nil }

        return start.occurredAt.wholeDays(to: occurredAt)
    }
}

public extension Date {
    func wholeDays(to laterDate: Date, calendar: Calendar = .current) -> Int {
        max(0, calendar.dateComponents([.day], from: self, to: laterDate).day ?? 0)
    }
}
