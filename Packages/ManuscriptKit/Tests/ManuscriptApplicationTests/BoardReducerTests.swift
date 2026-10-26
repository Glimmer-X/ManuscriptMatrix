import Foundation
import ManuscriptApplication
import ManuscriptDomain
import XCTest

final class BoardReducerTests: XCTestCase {
    func testAgentCanBackfillManuscriptReadinessWithoutChangingSubmissionHistory() throws {
        let manuscriptID = UUID()
        let occurredAt = "2026-08-20T12:30:00Z"
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "manuscript.readiness.set",
          "payload": {
            "manuscriptId": "\(manuscriptID.uuidString)",
            "readiness": "readyToSubmit",
            "occurredAt": "\(occurredAt)"
          }
        }
        """
        let manuscript = Manuscript(
            id: ManuscriptID(manuscriptID),
            title: "Draft",
            shortTitle: "Draft",
            readiness: .incomplete
        )
        var board = BoardSnapshot(manuscripts: [manuscript])

        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        _ = try BoardReducer.apply(try AgentCommandCodec.command(from: envelope), to: &board)

        XCTAssertEqual(board.manuscripts.first?.readiness, .readyToSubmit)
        XCTAssertEqual(
            board.manuscripts.first?.readinessUpdatedAt,
            ISO8601DateFormatter().date(from: occurredAt)
        )
        XCTAssertTrue(board.submissionEvents.isEmpty)
    }

    func testAgentCanSetIntermediatePreparationStage() throws {
        let manuscriptID = UUID()
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "manuscript.readiness.set",
          "payload": {
            "manuscriptId": "\(manuscriptID.uuidString)",
            "readiness": "writing",
            "occurredAt": "2026-08-31T12:30:00Z"
          }
        }
        """
        var board = BoardSnapshot(manuscripts: [
            Manuscript(
                id: ManuscriptID(manuscriptID),
                title: "Draft",
                shortTitle: "Draft",
                readiness: .experimenting
            )
        ])

        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        _ = try BoardReducer.apply(try AgentCommandCodec.command(from: envelope), to: &board)

        XCTAssertEqual(board.manuscripts.first?.readiness, .writing)
        XCTAssertEqual(board.manuscriptProjection(for: ManuscriptID(manuscriptID)).situation, .incomplete)
        XCTAssertTrue(board.submissionEvents.isEmpty)
    }

    func testAgentCreatedManuscriptDefaultsToIncomplete() throws {
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "manuscript.create",
          "payload": {
            "title": "New draft",
            "shortTitle": "Draft"
          }
        }
        """
        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        var board = BoardSnapshot.empty

        _ = try BoardReducer.apply(try AgentCommandCodec.command(from: envelope), to: &board)

        XCTAssertEqual(board.manuscripts.first?.readiness, .incomplete)
        XCTAssertEqual(board.manuscriptProjection(for: board.manuscripts[0].id).situation, .incomplete)
    }

    func testAgentCodecDecodesTargetCommandWithPlainUUIDs() throws {
        let manuscriptID = UUID()
        let journalID = UUID()
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "target.set",
          "payload": {
            "manuscriptId": "\(manuscriptID.uuidString)",
            "journalId": "\(journalID.uuidString)",
            "priority": 2,
            "note": "Second option"
          },
          "source": "agent"
        }
        """

        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        let command = try AgentCommandCodec.command(from: envelope)
        let manuscript = Manuscript(
            id: ManuscriptID(manuscriptID),
            title: "Full",
            shortTitle: "A"
        )
        let journal = Journal(id: JournalID(journalID), currentName: "Journal", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript])

        _ = try BoardReducer.apply(command, to: &board)

        XCTAssertEqual(board.targets.first?.priority, 1, "A lone target is normalized to first place")
        XCTAssertEqual(board.targets.first?.note, "Second option")
    }

    func testSettingTargetInsertsAndNormalizesPriorities() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journals = [
            Journal(currentName: "One", rank: 1),
            Journal(currentName: "Two", rank: 2),
            Journal(currentName: "Three", rank: 3)
        ]
        var board = BoardSnapshot(journals: journals, manuscripts: [manuscript])

        _ = try BoardReducer.apply(
            .setTarget(manuscriptID: manuscript.id, journalID: journals[0].id, priority: 1, note: nil),
            to: &board
        )
        _ = try BoardReducer.apply(
            .setTarget(manuscriptID: manuscript.id, journalID: journals[1].id, priority: 2, note: nil),
            to: &board
        )
        _ = try BoardReducer.apply(
            .setTarget(manuscriptID: manuscript.id, journalID: journals[2].id, priority: 1, note: nil),
            to: &board
        )

        let targets = board.targets(for: manuscript.id)
        XCTAssertEqual(targets.map(\.priority), [1, 2, 3])
        XCTAssertEqual(targets.map(\.journalID), [journals[2].id, journals[0].id, journals[1].id])
        XCTAssertTrue(board.submissionEvents.isEmpty, "Planning must not fabricate history")
    }

    func testJournalRenamePreservesSubmissionNameSnapshot() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Old Name", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript])

        _ = try BoardReducer.apply(
            .recordSubmission(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                occurredAt: Date(timeIntervalSince1970: 1_000),
                note: nil
            ),
            to: &board
        )
        _ = try BoardReducer.apply(
            .renameJournal(
                journalID: journal.id,
                newName: "New Name",
                occurredAt: Date(timeIntervalSince1970: 2_000)
            ),
            to: &board
        )

        XCTAssertEqual(board.journals.first?.currentName, "New Name")
        XCTAssertEqual(board.submissionEvents.first?.journalNameSnapshot, "Old Name")
        XCTAssertEqual(board.journals.first?.nameHistory.map(\.name), ["Old Name", "New Name"])
    }

    func testCannotCreateSecondLiveSubmission() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journals = [
            Journal(currentName: "One", rank: 1),
            Journal(currentName: "Two", rank: 2)
        ]
        var board = BoardSnapshot(journals: journals, manuscripts: [manuscript])

        _ = try BoardReducer.apply(
            .recordSubmission(
                manuscriptID: manuscript.id,
                journalID: journals[0].id,
                occurredAt: .now,
                note: nil
            ),
            to: &board
        )

        XCTAssertThrowsError(
            try BoardReducer.apply(
                .recordSubmission(
                    manuscriptID: manuscript.id,
                    journalID: journals[1].id,
                    occurredAt: .now,
                    note: nil
                ),
                to: &board
            )
        ) { error in
            XCTAssertEqual(error as? BoardCommandError, .manuscriptAlreadyActive)
        }
    }

    func testMovingJournalReordersTheGlobalLadder() throws {
        let journals = [
            Journal(currentName: "One", rank: 1),
            Journal(currentName: "Two", rank: 2),
            Journal(currentName: "Three", rank: 3)
        ]
        var board = BoardSnapshot(journals: journals)

        _ = try BoardReducer.apply(
            .moveJournal(journalID: journals[2].id, toRank: 1),
            to: &board
        )

        XCTAssertEqual(board.rankedJournals.map(\.currentName), ["Three", "One", "Two"])
        XCTAssertEqual(board.rankedJournals.map(\.rank), [1, 2, 3])
    }

    func testAgentCanMoveManuscriptColumnAndPersistNormalizedPositions() throws {
        let manuscripts = [
            Manuscript(title: "First", shortTitle: "A", createdAt: Date(timeIntervalSince1970: 1_000)),
            Manuscript(title: "Second", shortTitle: "B", createdAt: Date(timeIntervalSince1970: 2_000)),
            Manuscript(title: "Third", shortTitle: "C", createdAt: Date(timeIntervalSince1970: 3_000))
        ]
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "manuscript.position.set",
          "payload": {
            "manuscriptId": "\(manuscripts[0].id.description)",
            "position": 3
          }
        }
        """
        var board = BoardSnapshot(manuscripts: manuscripts)

        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        _ = try BoardReducer.apply(try AgentCommandCodec.command(from: envelope), to: &board)

        XCTAssertEqual(board.visibleManuscripts.map(\.shortTitle), ["B", "C", "A"])
        XCTAssertEqual(board.visibleManuscripts.compactMap(\.displayOrder), [1, 2, 3])

        let encoded = try AgentCommandCodec.makeEncoder().encode(board)
        let decoded = try AgentCommandCodec.makeDecoder().decode(BoardSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.visibleManuscripts.map(\.shortTitle), ["B", "C", "A"])
    }

    func testRelationshipIsStoredOnceAndProjectedFromBothEnds() throws {
        let first = Manuscript(title: "First", shortTitle: "A")
        let second = Manuscript(title: "Second", shortTitle: "B")
        var board = BoardSnapshot(manuscripts: [first, second])

        _ = try BoardReducer.apply(
            .createRelationship(
                id: RelationshipID(),
                firstManuscriptID: first.id,
                secondManuscriptID: second.id,
                direction: .firstToSecond,
                statement: "B supersedes A if accepted first.",
                createdAt: .now
            ),
            to: &board
        )

        XCTAssertEqual(board.relationships.count, 1)
        XCTAssertEqual(board.relationships(for: first.id).count, 1)
        XCTAssertEqual(board.relationships(for: second.id).count, 1)
    }

    func testVoidingRejectedEventRestoresLiveProjectionAndAuditTrace() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript])
        _ = try BoardReducer.apply(
            .recordSubmission(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                occurredAt: Date(timeIntervalSince1970: 1_000),
                note: nil
            ),
            to: &board
        )
        _ = try BoardReducer.apply(
            .recordStatus(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                kind: .rejected,
                occurredAt: Date(timeIntervalSince1970: 2_000),
                note: nil
            ),
            to: &board
        )
        let rejectedID = try XCTUnwrap(board.submissionEvents.last?.id)

        _ = try BoardReducer.apply(
            .voidSubmissionEvent(
                eventID: rejectedID,
                reason: "Entered the wrong status",
                occurredAt: Date(timeIntervalSince1970: 3_000)
            ),
            to: &board
        )

        XCTAssertEqual(board.manuscriptProjection(for: manuscript.id).status, .submitted)
        XCTAssertEqual(board.manuscriptProjection(for: manuscript.id).activeJournalID, journal.id)
        XCTAssertEqual(board.submissionEvents.count, 2)
        XCTAssertEqual(board.submissionEvents.last?.voidReason, "Entered the wrong status")
    }

    func testLiveManuscriptAndJournalCannotBeArchived() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript])
        _ = try BoardReducer.apply(
            .recordSubmission(
                manuscriptID: manuscript.id,
                journalID: journal.id,
                occurredAt: .now,
                note: nil
            ),
            to: &board
        )

        XCTAssertThrowsError(
            try BoardReducer.apply(
                .setManuscriptArchived(manuscriptID: manuscript.id, archived: true, occurredAt: .now),
                to: &board
            )
        ) { XCTAssertEqual($0 as? BoardCommandError, .manuscriptHasLiveSubmission) }
        XCTAssertThrowsError(
            try BoardReducer.apply(
                .setJournalArchived(journalID: journal.id, archived: true, occurredAt: .now),
                to: &board
            )
        ) { XCTAssertEqual($0 as? BoardCommandError, .journalHasLiveSubmissions) }
    }

    func testArchiveValidatorRejectsDanglingTarget() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let missingJournal = JournalID()
        let board = BoardSnapshot(
            manuscripts: [manuscript],
            targets: [TargetChoice(manuscriptID: manuscript.id, journalID: missingJournal, priority: 1)]
        )
        let data = try BoardArchiveCodec.encode(board)

        XCTAssertThrowsError(try BoardArchiveCodec.decode(data)) {
            XCTAssertEqual($0 as? BoardArchiveError, .danglingReference("target → journal"))
        }
    }

    func testAgentCodecDecodesHistoryCorrection() throws {
        let eventID = UUID()
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "submission.event.void",
          "payload": {
            "eventId": "\(eventID.uuidString)",
            "reason": "Wrong email update"
          }
        }
        """
        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        let command = try AgentCommandCodec.command(from: envelope)
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal", rank: 1)
        let event = SubmissionEvent(
            id: SubmissionEventID(eventID),
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .submitted,
            occurredAt: .now
        )
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript], submissionEvents: [event])

        _ = try BoardReducer.apply(command, to: &board)

        XCTAssertTrue(board.submissionEvents[0].isVoided)
    }

    func testAmendingEventPreservesPriorDateAndNote() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal", rank: 1)
        let originalDate = Date(timeIntervalSince1970: 1_000)
        let correctedDate = Date(timeIntervalSince1970: 2_000)
        let amendedAt = Date(timeIntervalSince1970: 3_000)
        let event = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .submitted,
            occurredAt: originalDate,
            note: "Original note"
        )
        var board = BoardSnapshot(
            journals: [journal],
            manuscripts: [manuscript],
            submissionEvents: [event]
        )

        _ = try BoardReducer.apply(
            .amendSubmissionEvent(
                eventID: event.id,
                occurredAt: correctedDate,
                note: "Corrected note",
                reason: "Backfilled from the editorial email",
                amendedAt: amendedAt
            ),
            to: &board
        )

        let corrected = try XCTUnwrap(board.submissionEvents.first)
        XCTAssertEqual(corrected.occurredAt, correctedDate)
        XCTAssertEqual(corrected.note, "Corrected note")
        XCTAssertEqual(corrected.amendmentHistory.first?.previousOccurredAt, originalDate)
        XCTAssertEqual(corrected.amendmentHistory.first?.previousNote, "Original note")
        XCTAssertEqual(corrected.amendmentHistory.first?.reason, "Backfilled from the editorial email")
        XCTAssertEqual(corrected.amendmentHistory.first?.amendedAt, amendedAt)
    }

    func testAgentCanAmendEventDate() throws {
        let eventID = UUID()
        let correctedDate = "2026-08-01T12:30:00Z"
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "submission.event.amend",
          "payload": {
            "eventId": "\(eventID.uuidString)",
            "occurredAt": "\(correctedDate)",
            "note": "Imported from email",
            "reason": "Corrected historical timestamp"
          }
        }
        """
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal", rank: 1)
        let event = SubmissionEvent(
            id: SubmissionEventID(eventID),
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .submitted,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript], submissionEvents: [event])

        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        _ = try BoardReducer.apply(try AgentCommandCodec.command(from: envelope), to: &board)

        XCTAssertEqual(board.submissionEvents.first?.note, "Imported from email")
        XCTAssertEqual(board.submissionEvents.first?.amendmentHistory.count, 1)
    }

    func testAgentCanCreateJournalWithCompleteMetadataAndMultiplePartitions() throws {
        let journalID = UUID()
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "journal.create",
          "payload": {
            "id": "\(journalID.uuidString)",
            "name": "Journal of Complete Metadata",
            "rank": 1,
            "impactFactor": 8.7,
            "category": "Artificial Intelligence",
            "averageDecisionDays": 42,
            "issn": "1234-5678",
            "eISSN": "8765-4321",
            "tags": ["AI", "systems"],
            "partitions": [
              { "scheme": "JCR", "year": 2025, "value": "Q1" },
              { "scheme": "CAS", "year": 2024, "value": "1区" },
              { "scheme": "CAS", "year": 2025, "value": "2区" }
            ]
          }
        }
        """
        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        let command = try AgentCommandCodec.command(from: envelope)
        var board = BoardSnapshot.empty

        _ = try BoardReducer.apply(command, to: &board)

        let journal = try XCTUnwrap(board.journals.first)
        XCTAssertEqual(journal.id, JournalID(journalID))
        XCTAssertEqual(journal.metrics.impactFactor, 8.7)
        XCTAssertEqual(journal.metrics.partitions.map(\.displayLabel), ["JCR 2025 Q1", "CAS 2024 1区", "CAS 2025 2区"])
        XCTAssertEqual(journal.issn, "1234-5678")
        XCTAssertEqual(journal.tags, ["AI", "systems"])
    }

    func testAgentRejectsFreeFormPartitionValues() throws {
        let json = """
        {
          "version": 1,
          "commandId": "\(UUID().uuidString)",
          "type": "journal.create",
          "payload": {
            "name": "Invalid Partition Journal",
            "rank": 1,
            "partitions": [
              { "scheme": "CCF", "year": 2026, "value": "未收录" }
            ]
          }
        }
        """
        let envelope = try AgentCommandCodec.decodeEnvelope(from: Data(json.utf8))
        let command = try AgentCommandCodec.command(from: envelope)
        var board = BoardSnapshot.empty

        XCTAssertThrowsError(try BoardReducer.apply(command, to: &board)) {
            XCTAssertEqual($0 as? BoardCommandError, .invalidJournalPartition)
        }
        XCTAssertTrue(board.journals.isEmpty)
    }

    func testPermanentJournalDeletionCascadesAndRequiresConfirmation() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "A")
        let journal = Journal(currentName: "Journal", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [manuscript])
        _ = try BoardReducer.apply(
            .recordSubmission(manuscriptID: manuscript.id, journalID: journal.id, occurredAt: .now, note: nil),
            to: &board
        )

        XCTAssertThrowsError(
            try BoardReducer.apply(.deleteJournal(journalID: journal.id, permanently: false), to: &board)
        ) { XCTAssertEqual($0 as? BoardCommandError, .deletionConfirmationRequired) }

        _ = try BoardReducer.apply(.deleteJournal(journalID: journal.id, permanently: true), to: &board)

        XCTAssertTrue(board.journals.isEmpty)
        XCTAssertTrue(board.submissionEvents.isEmpty)
    }

    func testPermanentManuscriptDeletionRemovesTargetsEventsAndRelationships() throws {
        let first = Manuscript(title: "First", shortTitle: "A")
        let second = Manuscript(title: "Second", shortTitle: "B")
        let journal = Journal(currentName: "Journal", rank: 1)
        var board = BoardSnapshot(journals: [journal], manuscripts: [first, second])
        _ = try BoardReducer.apply(
            .setTarget(manuscriptID: first.id, journalID: journal.id, priority: 1, note: nil),
            to: &board
        )
        _ = try BoardReducer.apply(
            .createRelationship(
                id: RelationshipID(),
                firstManuscriptID: first.id,
                secondManuscriptID: second.id,
                direction: .undirected,
                statement: "Related",
                createdAt: .now
            ),
            to: &board
        )

        _ = try BoardReducer.apply(
            .deleteManuscript(manuscriptID: first.id, permanently: true),
            to: &board
        )

        XCTAssertEqual(board.manuscripts.map(\.id), [second.id])
        XCTAssertTrue(board.targets.isEmpty)
        XCTAssertTrue(board.relationships.isEmpty)
    }
}
