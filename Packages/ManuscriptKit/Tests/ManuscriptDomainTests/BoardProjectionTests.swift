import Foundation
import ManuscriptDomain
import XCTest

final class BoardProjectionTests: XCTestCase {
    func testReadinessSeparatesIncompleteFromPreparingSubmission() {
        let incomplete = Manuscript(
            title: "Draft",
            shortTitle: "Draft",
            readiness: .incomplete
        )
        let ready = Manuscript(
            title: "Complete",
            shortTitle: "Ready",
            readiness: .readyToSubmit
        )
        let board = BoardSnapshot(manuscripts: [incomplete, ready])

        XCTAssertEqual(board.manuscriptProjection(for: incomplete.id).situation, .incomplete)
        XCTAssertEqual(board.manuscriptProjection(for: ready.id).situation, .preparingSubmission)
    }

    func testEveryIntermediatePreparationStageRemainsIncomplete() {
        for readiness in [
            ManuscriptReadiness.incomplete,
            .experimenting,
            .conceptualizing,
            .writing
        ] {
            let manuscript = Manuscript(
                title: readiness.rawValue,
                shortTitle: readiness.rawValue,
                readiness: readiness
            )
            let board = BoardSnapshot(manuscripts: [manuscript])

            XCTAssertEqual(board.manuscriptProjection(for: manuscript.id).situation, .incomplete)
        }
    }

    func testLegacyManuscriptWithoutReadinessDecodesAsReady() throws {
        let original = Manuscript(title: "Legacy", shortTitle: "Legacy")
        let encoded = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "readiness")
        object.removeValue(forKey: "readinessUpdatedAt")
        let legacyData = try JSONSerialization.data(withJSONObject: object)

        let decoded = try JSONDecoder().decode(Manuscript.self, from: legacyData)

        XCTAssertEqual(decoded.readiness, .readyToSubmit)
        XCTAssertEqual(decoded.readinessUpdatedAt, decoded.createdAt)
    }

    func testRejectedSubmissionReturnsManuscriptToStaging() {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal A", rank: 1)
        let submittedAt = Date(timeIntervalSince1970: 1_000)
        let rejectedAt = Date(timeIntervalSince1970: 2_000)
        let board = BoardSnapshot(
            journals: [journal],
            manuscripts: [manuscript],
            submissionEvents: [
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .submitted,
                    occurredAt: submittedAt
                ),
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .rejected,
                    occurredAt: rejectedAt
                )
            ]
        )

        let projection = board.manuscriptProjection(for: manuscript.id)

        XCTAssertEqual(projection.status, .awaitingSubmission)
        XCTAssertNil(projection.activeJournalID)
        XCTAssertNil(projection.liveStartedAt)
        XCTAssertEqual(projection.latestEvent?.kind, .rejected)
        XCTAssertEqual(projection.situation, .rejected)
    }

    func testRejectedSubmissionDecisionDaysAreDerivedFromExistingEvents() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal A", rank: 1)
        let submitted = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .submitted,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let rejected = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .rejected,
            occurredAt: Date(timeIntervalSince1970: 1_000 + (20 * 86_400))
        )

        XCTAssertEqual(rejected.rejectionDecisionDays(in: [rejected, submitted]), 20)
    }

    func testRejectedSubmissionUsesLatestResubmissionForDecisionDays() throws {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal A", rank: 1)
        let submitted = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .submitted,
            occurredAt: Date(timeIntervalSince1970: 1_000)
        )
        let resubmitted = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .resubmitted,
            occurredAt: Date(timeIntervalSince1970: 1_000 + (10 * 86_400))
        )
        let rejected = SubmissionEvent(
            manuscriptID: manuscript.id,
            journalID: journal.id,
            journalNameSnapshot: journal.currentName,
            kind: .rejected,
            occurredAt: Date(timeIntervalSince1970: 1_000 + (25 * 86_400))
        )

        XCTAssertEqual(rejected.rejectionDecisionDays(in: [rejected, submitted, resubmitted]), 15)
    }

    func testRejectAndResubmitRemainsLiveAtOriginalJournal() {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal A", rank: 1)
        let board = BoardSnapshot(
            journals: [journal],
            manuscripts: [manuscript],
            submissionEvents: [
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .submitted,
                    occurredAt: Date(timeIntervalSince1970: 1_000)
                ),
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .rejectAndResubmit,
                    occurredAt: Date(timeIntervalSince1970: 2_000)
                )
            ]
        )

        let projection = board.manuscriptProjection(for: manuscript.id)

        XCTAssertEqual(projection.status, .rejectAndResubmit)
        XCTAssertEqual(projection.activeJournalID, journal.id)
        XCTAssertEqual(projection.situation, .revision)
        XCTAssertEqual(projection.latestActionAt, board.submissionEvents.last?.occurredAt)
    }

    func testResubmissionStartsANewElapsedClock() {
        let manuscript = Manuscript(title: "Full", shortTitle: "Paper A")
        let journal = Journal(currentName: "Journal A", rank: 1)
        let originalSubmission = Date(timeIntervalSince1970: 1_000)
        let resubmission = Date(timeIntervalSince1970: 3_000)
        let board = BoardSnapshot(
            journals: [journal],
            manuscripts: [manuscript],
            submissionEvents: [
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .submitted,
                    occurredAt: originalSubmission
                ),
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .rejectAndResubmit,
                    occurredAt: Date(timeIntervalSince1970: 2_000)
                ),
                SubmissionEvent(
                    manuscriptID: manuscript.id,
                    journalID: journal.id,
                    journalNameSnapshot: journal.currentName,
                    kind: .resubmitted,
                    occurredAt: resubmission
                )
            ]
        )

        let projection = board.manuscriptProjection(for: manuscript.id)

        XCTAssertEqual(projection.status, .submitted)
        XCTAssertEqual(projection.liveStartedAt, resubmission)
        XCTAssertEqual(projection.situation, .awaitingDecision)
    }

    func testLegacyQuartileDecodesIntoJCRPartition() throws {
        let json = """
        {
          "impactFactor": 5.2,
          "quartile": "Q1",
          "category": "Engineering"
        }
        """
        let metrics = try JSONDecoder().decode(JournalMetrics.self, from: Data(json.utf8))

        XCTAssertEqual(metrics.partitions.count, 1)
        XCTAssertEqual(metrics.partitions.first?.scheme, "JCR")
        XCTAssertEqual(metrics.partitions.first?.value, "Q1")
    }

    func testLegacyPartitionPlaceholdersMigrateToMissingValues() throws {
        let json = """
        {
          "partitions": [
            { "scheme": "CCF", "year": 2026, "value": "未收录" },
            { "scheme": "CAS", "year": 2025, "value": "待核对" },
            { "scheme": "JCR", "year": 2026, "value": "Q1/Q2" },
            { "scheme": "JCR", "year": 2025, "value": "2区" },
            { "scheme": "新锐", "year": 2026, "value": "3区" }
          ]
        }
        """

        let metrics = try JSONDecoder().decode(JournalMetrics.self, from: Data(json.utf8))

        XCTAssertEqual(metrics.partitions.map(\.displayLabel), ["JCR 2025 Q2", "新锐 2026 3区"])
    }
}
