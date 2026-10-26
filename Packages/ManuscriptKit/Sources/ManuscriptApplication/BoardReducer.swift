import Foundation
import ManuscriptDomain

public enum BoardReducer {
    public static func apply(
        _ command: BoardCommand,
        to snapshot: inout BoardSnapshot,
        now: Date = .now
    ) throws -> MutationReceipt {
        let receipt: MutationReceipt

        switch command {
        case let .createManuscript(id, title, shortTitle, tags, readiness, createdAt):
            guard !snapshot.manuscripts.contains(where: { $0.id == id }) else {
                throw BoardCommandError.identityAlreadyExists
            }
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanShortTitle = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty, !cleanShortTitle.isEmpty else {
                throw BoardCommandError.invalidTitle
            }
            snapshot.manuscripts.append(
                Manuscript(
                    id: id,
                    title: cleanTitle,
                    shortTitle: cleanShortTitle,
                    tags: tags,
                    readiness: readiness,
                    readinessUpdatedAt: createdAt,
                    createdAt: createdAt
                )
            )
            receipt = MutationReceipt(
                summary: "Created manuscript \(cleanShortTitle).",
                affectedEntityIDs: [id.description]
            )

        case let .updateManuscript(manuscriptID, title, shortTitle, tags):
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanShortTitle = shortTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanTitle.isEmpty, !cleanShortTitle.isEmpty else {
                throw BoardCommandError.invalidTitle
            }
            guard let index = snapshot.manuscripts.firstIndex(where: { $0.id == manuscriptID }) else {
                throw BoardCommandError.manuscriptNotFound
            }
            snapshot.manuscripts[index].title = cleanTitle
            snapshot.manuscripts[index].shortTitle = cleanShortTitle
            snapshot.manuscripts[index].tags = cleanTags(tags)
            receipt = MutationReceipt(
                summary: "Updated manuscript \(cleanShortTitle).",
                affectedEntityIDs: [manuscriptID.description]
            )

        case let .moveManuscript(manuscriptID, toPosition):
            guard toPosition >= 1 else { throw BoardCommandError.invalidManuscriptPosition }
            guard let manuscript = snapshot.manuscripts.first(where: { $0.id == manuscriptID }) else {
                throw BoardCommandError.manuscriptNotFound
            }
            guard manuscript.archivedAt == nil else { throw BoardCommandError.invalidStatusTransition }

            var ordered = snapshot.visibleManuscripts.filter { $0.id != manuscriptID }
            let insertionIndex = min(toPosition - 1, ordered.count)
            ordered.insert(manuscript, at: insertionIndex)
            for (index, orderedManuscript) in ordered.enumerated() {
                guard let storedIndex = snapshot.manuscripts.firstIndex(where: { $0.id == orderedManuscript.id }) else {
                    continue
                }
                snapshot.manuscripts[storedIndex].displayOrder = index + 1
            }
            receipt = MutationReceipt(
                summary: "Moved \(manuscript.shortTitle) to manuscript position \(insertionIndex + 1).",
                affectedEntityIDs: [manuscriptID.description]
            )

        case let .setManuscriptReadiness(manuscriptID, readiness, occurredAt):
            guard let index = snapshot.manuscripts.firstIndex(where: { $0.id == manuscriptID }) else {
                throw BoardCommandError.manuscriptNotFound
            }
            snapshot.manuscripts[index].readiness = readiness
            snapshot.manuscripts[index].readinessUpdatedAt = occurredAt
            receipt = MutationReceipt(
                summary: "Set manuscript preparation stage to \(readiness.rawValue).",
                affectedEntityIDs: [manuscriptID.description]
            )

        case let .setManuscriptArchived(manuscriptID, archived, occurredAt):
            guard let index = snapshot.manuscripts.firstIndex(where: { $0.id == manuscriptID }) else {
                throw BoardCommandError.manuscriptNotFound
            }
            if archived,
               snapshot.manuscriptProjection(for: manuscriptID).activeJournalID != nil {
                throw BoardCommandError.manuscriptHasLiveSubmission
            }
            snapshot.manuscripts[index].archivedAt = archived ? occurredAt : nil
            receipt = MutationReceipt(
                summary: archived ? "Archived manuscript." : "Restored manuscript.",
                affectedEntityIDs: [manuscriptID.description]
            )

        case let .deleteManuscript(manuscriptID, permanently):
            guard permanently else { throw BoardCommandError.deletionConfirmationRequired }
            try requireManuscript(manuscriptID, in: snapshot)
            snapshot.manuscripts.removeAll { $0.id == manuscriptID }
            snapshot.submissionEvents.removeAll { $0.manuscriptID == manuscriptID }
            snapshot.targets.removeAll { $0.manuscriptID == manuscriptID }
            snapshot.relationships.removeAll { $0.involves(manuscriptID) }
            receipt = MutationReceipt(
                summary: "Permanently deleted a manuscript and its related board records.",
                affectedEntityIDs: [manuscriptID.description]
            )

        case let .createJournal(id, name, rank, metrics, issn, eISSN, tags, createdAt):
            guard !snapshot.journals.contains(where: { $0.id == id }) else {
                throw BoardCommandError.identityAlreadyExists
            }
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { throw BoardCommandError.invalidName }
            let cleanMetrics = try cleanMetrics(metrics)
            let safeRank = max(1, rank)
            snapshot.journals = insertingJournalRank(safeRank, into: snapshot.journals)
            snapshot.journals.append(
                Journal(
                    id: id,
                    currentName: cleanName,
                    rank: safeRank,
                    issn: cleanedOptional(issn),
                    eISSN: cleanedOptional(eISSN),
                    tags: cleanTags(tags),
                    metrics: cleanMetrics,
                    createdAt: createdAt
                )
            )
            normalizeJournalRanks(in: &snapshot)
            receipt = MutationReceipt(
                summary: "Added \(cleanName) to the journal ladder at rank \(safeRank).",
                affectedEntityIDs: [id.description]
            )

        case let .renameJournal(journalID, newName, occurredAt):
            let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty else { throw BoardCommandError.invalidName }
            guard let index = snapshot.journals.firstIndex(where: { $0.id == journalID }) else {
                throw BoardCommandError.journalNotFound
            }
            let oldName = snapshot.journals[index].currentName
            if let openIndex = snapshot.journals[index].nameHistory.lastIndex(where: { $0.effectiveTo == nil }) {
                snapshot.journals[index].nameHistory[openIndex].effectiveTo = occurredAt
            }
            snapshot.journals[index].nameHistory.append(
                JournalNameRecord(name: cleanName, effectiveFrom: occurredAt)
            )
            snapshot.journals[index].currentName = cleanName
            receipt = MutationReceipt(
                summary: "Renamed \(oldName) to \(cleanName); historical event labels were preserved.",
                affectedEntityIDs: [journalID.description]
            )

        case let .deleteJournal(journalID, permanently):
            guard permanently else { throw BoardCommandError.deletionConfirmationRequired }
            try requireJournal(journalID, in: snapshot)
            snapshot.journals.removeAll { $0.id == journalID }
            snapshot.submissionEvents.removeAll { $0.journalID == journalID }
            snapshot.targets.removeAll { $0.journalID == journalID }
            normalizeJournalRanks(in: &snapshot)
            receipt = MutationReceipt(
                summary: "Permanently deleted a journal and its related submission records.",
                affectedEntityIDs: [journalID.description]
            )

        case let .moveJournal(journalID, toRank):
            guard toRank >= 1 else { throw BoardCommandError.invalidPriority }
            let journal = try requireJournal(journalID, in: snapshot)
            guard journal.archivedAt == nil else { throw BoardCommandError.invalidStatusTransition }
            var ordered = snapshot.rankedJournals.filter { $0.id != journalID }
            let insertionIndex = min(toRank - 1, ordered.count)
            ordered.insert(journal, at: insertionIndex)
            for index in ordered.indices {
                ordered[index].rank = index + 1
            }
            snapshot.journals = ordered + snapshot.journals.filter { $0.archivedAt != nil }
            receipt = MutationReceipt(
                summary: "Moved \(journal.currentName) to rank \(insertionIndex + 1).",
                affectedEntityIDs: [journalID.description]
            )

        case let .updateJournalMetadata(journalID, metrics, issn, eISSN, tags):
            guard let index = snapshot.journals.firstIndex(where: { $0.id == journalID }) else {
                throw BoardCommandError.journalNotFound
            }
            snapshot.journals[index].metrics = try cleanMetrics(metrics)
            snapshot.journals[index].issn = cleanedOptional(issn)
            snapshot.journals[index].eISSN = cleanedOptional(eISSN)
            snapshot.journals[index].tags = cleanTags(tags)
            receipt = MutationReceipt(
                summary: "Updated metadata for \(snapshot.journals[index].currentName).",
                affectedEntityIDs: [journalID.description]
            )

        case let .setJournalArchived(journalID, archived, occurredAt):
            guard let index = snapshot.journals.firstIndex(where: { $0.id == journalID }) else {
                throw BoardCommandError.journalNotFound
            }
            if archived {
                let hasLiveSubmission = snapshot.visibleManuscripts.contains {
                    snapshot.manuscriptProjection(for: $0.id).activeJournalID == journalID
                }
                guard !hasLiveSubmission else { throw BoardCommandError.journalHasLiveSubmissions }
                snapshot.targets.removeAll { $0.journalID == journalID }
            }
            snapshot.journals[index].archivedAt = archived ? occurredAt : nil
            if !archived {
                snapshot.journals[index].rank = snapshot.rankedJournals.count
            }
            normalizeJournalRanks(in: &snapshot)
            receipt = MutationReceipt(
                summary: archived ? "Archived journal." : "Restored journal to the ladder.",
                affectedEntityIDs: [journalID.description]
            )

        case let .setTarget(manuscriptID, journalID, priority, note):
            try requireActiveManuscript(manuscriptID, in: snapshot)
            try requireActiveJournal(journalID, in: snapshot)
            guard priority >= 1 else { throw BoardCommandError.invalidPriority }
            setTarget(
                manuscriptID: manuscriptID,
                journalID: journalID,
                priority: priority,
                note: note,
                in: &snapshot,
                now: now
            )
            receipt = MutationReceipt(
                summary: "Set target priority \(priority).",
                affectedEntityIDs: [manuscriptID.description, journalID.description]
            )

        case let .removeTarget(manuscriptID, journalID):
            try requireManuscript(manuscriptID, in: snapshot)
            try requireJournal(journalID, in: snapshot)
            snapshot.targets.removeAll {
                $0.manuscriptID == manuscriptID && $0.journalID == journalID
            }
            normalizeTargets(for: manuscriptID, in: &snapshot)
            receipt = MutationReceipt(
                summary: "Removed journal from the manuscript target plan.",
                affectedEntityIDs: [manuscriptID.description, journalID.description]
            )

        case let .recordSubmission(manuscriptID, journalID, occurredAt, note):
            try requireActiveManuscript(manuscriptID, in: snapshot)
            let journal = try requireActiveJournal(journalID, in: snapshot)
            let projection = snapshot.manuscriptProjection(for: manuscriptID)
            guard projection.activeJournalID == nil else {
                throw BoardCommandError.manuscriptAlreadyActive
            }
            guard !projection.isAccepted else {
                throw BoardCommandError.manuscriptAlreadyAccepted
            }
            snapshot.submissionEvents.append(
                SubmissionEvent(
                    manuscriptID: manuscriptID,
                    journalID: journalID,
                    journalNameSnapshot: journal.currentName,
                    kind: .submitted,
                    occurredAt: occurredAt,
                    note: note
                )
            )
            snapshot.targets.removeAll {
                $0.manuscriptID == manuscriptID && $0.journalID == journalID
            }
            normalizeTargets(for: manuscriptID, in: &snapshot)
            receipt = MutationReceipt(
                summary: "Recorded submission to \(journal.currentName).",
                affectedEntityIDs: [manuscriptID.description, journalID.description]
            )

        case let .recordStatus(manuscriptID, journalID, kind, occurredAt, note):
            try requireManuscript(manuscriptID, in: snapshot)
            let journal = try requireJournal(journalID, in: snapshot)
            guard kind != .submitted else { throw BoardCommandError.invalidStatusTransition }
            let projection = snapshot.manuscriptProjection(for: manuscriptID)
            guard projection.activeJournalID == journalID else {
                throw BoardCommandError.journalIsNotActiveSubmission
            }
            snapshot.submissionEvents.append(
                SubmissionEvent(
                    manuscriptID: manuscriptID,
                    journalID: journalID,
                    journalNameSnapshot: journal.currentName,
                    kind: kind,
                    occurredAt: occurredAt,
                    note: note
                )
            )
            receipt = MutationReceipt(
                summary: "Recorded \(kind.rawValue) at \(journal.currentName).",
                affectedEntityIDs: [manuscriptID.description, journalID.description]
            )

        case let .voidSubmissionEvent(eventID, reason, occurredAt):
            let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanReason.isEmpty else { throw BoardCommandError.invalidVoidReason }
            guard let index = snapshot.submissionEvents.firstIndex(where: { $0.id == eventID }) else {
                throw BoardCommandError.submissionEventNotFound
            }
            guard !snapshot.submissionEvents[index].isVoided else {
                throw BoardCommandError.eventAlreadyVoided
            }
            snapshot.submissionEvents[index].voidedAt = occurredAt
            snapshot.submissionEvents[index].voidReason = cleanReason
            receipt = MutationReceipt(
                summary: "Voided an incorrect submission event; the audit trace was retained.",
                affectedEntityIDs: [eventID.rawValue.uuidString]
            )

        case let .amendSubmissionEvent(eventID, occurredAt, note, reason, amendedAt):
            let cleanReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanReason.isEmpty else { throw BoardCommandError.invalidAmendmentReason }
            guard let index = snapshot.submissionEvents.firstIndex(where: { $0.id == eventID }) else {
                throw BoardCommandError.submissionEventNotFound
            }
            guard !snapshot.submissionEvents[index].isVoided else {
                throw BoardCommandError.eventAlreadyVoided
            }
            let previous = snapshot.submissionEvents[index]
            let cleanNote = cleanedOptional(note)
            let amendment = SubmissionEventAmendment(
                previousOccurredAt: previous.occurredAt,
                newOccurredAt: occurredAt,
                previousNote: previous.note,
                newNote: cleanNote,
                reason: cleanReason,
                amendedAt: amendedAt
            )
            snapshot.submissionEvents[index].occurredAt = occurredAt
            snapshot.submissionEvents[index].note = cleanNote
            snapshot.submissionEvents[index].amendments = previous.amendmentHistory + [amendment]
            receipt = MutationReceipt(
                summary: "Amended a submission event while preserving its audit history.",
                affectedEntityIDs: [eventID.rawValue.uuidString]
            )

        case let .createRelationship(
            id,
            firstManuscriptID,
            secondManuscriptID,
            direction,
            statement,
            createdAt
        ):
            guard !snapshot.relationships.contains(where: { $0.id == id }) else {
                throw BoardCommandError.identityAlreadyExists
            }
            try requireActiveManuscript(firstManuscriptID, in: snapshot)
            try requireActiveManuscript(secondManuscriptID, in: snapshot)
            guard firstManuscriptID != secondManuscriptID else {
                throw BoardCommandError.relationshipToSelf
            }
            let cleanStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanStatement.isEmpty else {
                throw BoardCommandError.invalidRelationshipStatement
            }
            snapshot.relationships.append(
                ManuscriptRelationship(
                    id: id,
                    firstManuscriptID: firstManuscriptID,
                    secondManuscriptID: secondManuscriptID,
                    direction: direction,
                    statement: cleanStatement,
                    createdAt: createdAt,
                    updatedAt: createdAt
                )
            )
            receipt = MutationReceipt(
                summary: "Created a relationship between two manuscripts.",
                affectedEntityIDs: [firstManuscriptID.description, secondManuscriptID.description]
            )

        case let .updateRelationship(relationshipID, direction, statement):
            let cleanStatement = statement.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanStatement.isEmpty else {
                throw BoardCommandError.invalidRelationshipStatement
            }
            guard let index = snapshot.relationships.firstIndex(where: { $0.id == relationshipID }) else {
                throw BoardCommandError.relationshipNotFound
            }
            snapshot.relationships[index].direction = direction
            snapshot.relationships[index].statement = cleanStatement
            snapshot.relationships[index].updatedAt = now
            receipt = MutationReceipt(
                summary: "Updated manuscript relationship.",
                affectedEntityIDs: [relationshipID.rawValue.uuidString]
            )

        case let .removeRelationship(relationshipID):
            guard snapshot.relationships.contains(where: { $0.id == relationshipID }) else {
                throw BoardCommandError.relationshipNotFound
            }
            snapshot.relationships.removeAll { $0.id == relationshipID }
            receipt = MutationReceipt(
                summary: "Removed manuscript relationship.",
                affectedEntityIDs: [relationshipID.rawValue.uuidString]
            )
        }

        snapshot.modifiedAt = now
        return receipt
    }

    private static func requireManuscript(
        _ id: ManuscriptID,
        in snapshot: BoardSnapshot
    ) throws {
        guard snapshot.manuscripts.contains(where: { $0.id == id }) else {
            throw BoardCommandError.manuscriptNotFound
        }
    }

    private static func requireActiveManuscript(
        _ id: ManuscriptID,
        in snapshot: BoardSnapshot
    ) throws {
        guard let manuscript = snapshot.manuscripts.first(where: { $0.id == id }) else {
            throw BoardCommandError.manuscriptNotFound
        }
        guard manuscript.archivedAt == nil else { throw BoardCommandError.manuscriptArchived }
    }

    @discardableResult
    private static func requireJournal(
        _ id: JournalID,
        in snapshot: BoardSnapshot
    ) throws -> Journal {
        guard let journal = snapshot.journals.first(where: { $0.id == id }) else {
            throw BoardCommandError.journalNotFound
        }
        return journal
    }

    @discardableResult
    private static func requireActiveJournal(
        _ id: JournalID,
        in snapshot: BoardSnapshot
    ) throws -> Journal {
        let journal = try requireJournal(id, in: snapshot)
        guard journal.archivedAt == nil else { throw BoardCommandError.journalArchived }
        return journal
    }

    private static func insertingJournalRank(_ rank: Int, into journals: [Journal]) -> [Journal] {
        journals.map { journal in
            var journal = journal
            if journal.archivedAt == nil, journal.rank >= rank { journal.rank += 1 }
            return journal
        }
    }

    private static func normalizeJournalRanks(in snapshot: inout BoardSnapshot) {
        let sortedIDs = snapshot.journals.filter { $0.archivedAt == nil }.sorted {
            if $0.rank == $1.rank { return $0.createdAt < $1.createdAt }
            return $0.rank < $1.rank
        }.map(\.id)

        for (offset, id) in sortedIDs.enumerated() {
            if let index = snapshot.journals.firstIndex(where: { $0.id == id }) {
                snapshot.journals[index].rank = offset + 1
            }
        }
    }

    private static func setTarget(
        manuscriptID: ManuscriptID,
        journalID: JournalID,
        priority: Int,
        note: String?,
        in snapshot: inout BoardSnapshot,
        now: Date
    ) {
        var manuscriptTargets = snapshot.targets
            .filter { $0.manuscriptID == manuscriptID && $0.journalID != journalID }
            .sorted { $0.priority < $1.priority }
        let insertionIndex = min(max(0, priority - 1), manuscriptTargets.count)
        manuscriptTargets.insert(
            TargetChoice(
                manuscriptID: manuscriptID,
                journalID: journalID,
                priority: priority,
                note: note,
                updatedAt: now
            ),
            at: insertionIndex
        )
        for index in manuscriptTargets.indices {
            manuscriptTargets[index].priority = index + 1
        }
        snapshot.targets.removeAll { $0.manuscriptID == manuscriptID }
        snapshot.targets.append(contentsOf: manuscriptTargets)
    }

    private static func normalizeTargets(
        for manuscriptID: ManuscriptID,
        in snapshot: inout BoardSnapshot
    ) {
        var manuscriptTargets = snapshot.targets
            .filter { $0.manuscriptID == manuscriptID }
            .sorted { $0.priority < $1.priority }
        for index in manuscriptTargets.indices {
            manuscriptTargets[index].priority = index + 1
        }
        snapshot.targets.removeAll { $0.manuscriptID == manuscriptID }
        snapshot.targets.append(contentsOf: manuscriptTargets)
    }

    private static func cleanTags(_ tags: [String]) -> [String] {
        Array(
            Set(
                tags
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private static func cleanedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? nil : clean
    }

    private static func cleanMetrics(_ metrics: JournalMetrics) throws -> JournalMetrics {
        if let impactFactor = metrics.impactFactor, impactFactor < 0 {
            throw BoardCommandError.invalidJournalMetrics
        }
        if let days = metrics.averageDecisionDays, days <= 0 {
            throw BoardCommandError.invalidJournalMetrics
        }

        let partitions = try metrics.partitions.map { partition in
            guard
                let scheme = JournalPartitionScheme.resolve(partition.scheme),
                let value = scheme.canonicalValue(partition.value)
            else {
                throw BoardCommandError.invalidJournalPartition
            }
            if let year = partition.year, !(1900...2100).contains(year) {
                throw BoardCommandError.invalidJournalPartition
            }
            return JournalPartition(
                id: partition.id,
                scheme: scheme.rawValue,
                year: partition.year,
                value: value,
                category: cleanedOptional(partition.category)
            )
        }

        return JournalMetrics(
            impactFactor: metrics.impactFactor,
            quartile: partitions.first(where: { $0.scheme == JournalPartitionScheme.jcr.rawValue })?.value,
            category: cleanedOptional(metrics.category),
            averageDecisionDays: metrics.averageDecisionDays,
            partitions: partitions
        )
    }
}
