import Foundation
import ManuscriptDomain

public enum DemoBoardFactory {
    /// Entirely fictional data. Venue names, metrics, manuscripts and dates are illustrative.
    public static func make(referenceDate: Date = .now) -> BoardSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        func daysAgo(_ days: Int) -> Date {
            calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        }

        let journals = [
            Journal(
                currentName: "Journal of Adaptive Systems",
                rank: 1,
                tags: ["AI", "Systems"],
                metrics: JournalMetrics(
                    impactFactor: 23.8,
                    quartile: "Q1",
                    category: "AI",
                    averageDecisionDays: 42,
                    partitions: [
                        JournalPartition(scheme: "JCR", year: 2025, value: "Q1"),
                        JournalPartition(scheme: "CAS", year: 2024, value: "1区"),
                        JournalPartition(scheme: "CAS", year: 2025, value: "1区")
                    ]
                ),
                createdAt: daysAgo(500)
            ),
            Journal(
                currentName: "Transactions on Visual Computing",
                rank: 2,
                tags: ["Vision", "ML"],
                metrics: JournalMetrics(
                    impactFactor: 18.6,
                    quartile: "Q1",
                    category: "Computer Science",
                    averageDecisionDays: 71,
                    partitions: [
                        JournalPartition(scheme: "JCR", year: 2025, value: "Q1"),
                        JournalPartition(scheme: "CAS", year: 2025, value: "1区")
                    ]
                ),
                createdAt: daysAgo(490)
            ),
            Journal(
                currentName: "Journal of Intelligent Architectures",
                rank: 3,
                tags: ["AI Systems"],
                metrics: JournalMetrics(
                    impactFactor: 7.2,
                    quartile: "Q1",
                    category: "AI",
                    averageDecisionDays: 58,
                    partitions: [
                        JournalPartition(scheme: "JCR", year: 2025, value: "Q1"),
                        JournalPartition(scheme: "CCF", value: "B")
                    ]
                ),
                createdAt: daysAgo(480)
            ),
            Journal(
                currentName: "Computational Methods Letters",
                rank: 4,
                tags: ["Vision"],
                metrics: JournalMetrics(impactFactor: 7.6, quartile: "Q1", category: "Pattern Recognition", averageDecisionDays: 49),
                createdAt: daysAgo(470)
            ),
            Journal(
                currentName: "Applied Learning Review",
                rank: 5,
                tags: ["Applied AI"],
                metrics: JournalMetrics(impactFactor: 7.5, quartile: "Q1", category: "AI", averageDecisionDays: 39),
                createdAt: daysAgo(460)
            )
        ]

        let manuscripts = [
            Manuscript(
                title: "First-generation adaptive inference system for uncertain environments",
                shortTitle: "Adaptive System A",
                tags: ["System v1"],
                createdAt: daysAgo(240)
            ),
            Manuscript(
                title: "A unified second-generation architecture for adaptive inference",
                shortTitle: "Unified System B",
                tags: ["System v2"],
                createdAt: daysAgo(130)
            ),
            Manuscript(
                title: "Robust evaluation protocols for real-world intelligent systems",
                shortTitle: "Robust Evaluation",
                tags: ["Evaluation"],
                createdAt: daysAgo(75)
            ),
            Manuscript(
                title: "Compact models for environmental monitoring at the edge",
                shortTitle: "Edge Monitoring",
                tags: ["Example"],
                createdAt: daysAgo(150)
            ),
            Manuscript(
                title: "A benchmark for interpretable distributed learning",
                shortTitle: "Clear Benchmark",
                tags: ["Example"],
                readiness: .writing,
                createdAt: daysAgo(30)
            )
        ]

        let first = manuscripts[0]
        let second = manuscripts[1]
        let third = manuscripts[2]
        let fourth = manuscripts[3]

        let events = [
            SubmissionEvent(
                manuscriptID: first.id,
                journalID: journals[0].id,
                journalNameSnapshot: journals[0].currentName,
                kind: .submitted,
                occurredAt: daysAgo(122)
            ),
            SubmissionEvent(
                manuscriptID: first.id,
                journalID: journals[0].id,
                journalNameSnapshot: journals[0].currentName,
                kind: .rejected,
                occurredAt: daysAgo(64)
            ),
            SubmissionEvent(
                manuscriptID: first.id,
                journalID: journals[2].id,
                journalNameSnapshot: journals[2].currentName,
                kind: .submitted,
                occurredAt: daysAgo(23)
            ),
            SubmissionEvent(
                manuscriptID: second.id,
                journalID: journals[1].id,
                journalNameSnapshot: journals[1].currentName,
                kind: .submitted,
                occurredAt: daysAgo(47)
            ),
            SubmissionEvent(
                manuscriptID: third.id,
                journalID: journals[3].id,
                journalNameSnapshot: journals[3].currentName,
                kind: .submitted,
                occurredAt: daysAgo(32)
            ),
            SubmissionEvent(
                manuscriptID: third.id,
                journalID: journals[3].id,
                journalNameSnapshot: journals[3].currentName,
                kind: .majorRevision,
                occurredAt: daysAgo(6)
            ),
            SubmissionEvent(
                manuscriptID: fourth.id,
                journalID: journals[4].id,
                journalNameSnapshot: journals[4].currentName,
                kind: .submitted,
                occurredAt: daysAgo(93)
            ),
            SubmissionEvent(
                manuscriptID: fourth.id,
                journalID: journals[4].id,
                journalNameSnapshot: journals[4].currentName,
                kind: .accepted,
                occurredAt: daysAgo(3)
            )
        ]

        let targets = [
            TargetChoice(manuscriptID: first.id, journalID: journals[3].id, priority: 1),
            TargetChoice(manuscriptID: first.id, journalID: journals[4].id, priority: 2),
            TargetChoice(manuscriptID: second.id, journalID: journals[0].id, priority: 1),
            TargetChoice(manuscriptID: second.id, journalID: journals[2].id, priority: 2),
            TargetChoice(manuscriptID: third.id, journalID: journals[4].id, priority: 1),
            TargetChoice(manuscriptID: manuscripts[4].id, journalID: journals[1].id, priority: 1),
            TargetChoice(manuscriptID: manuscripts[4].id, journalID: journals[3].id, priority: 2)
        ]

        let relationships = [
            ManuscriptRelationship(
                firstManuscriptID: first.id,
                secondManuscriptID: second.id,
                direction: .firstToSecond,
                statement: "Unified System B is the upgraded generation of Adaptive System A. If B is accepted first, A may lose independent publication value.",
                createdAt: daysAgo(80),
                updatedAt: daysAgo(80)
            )
        ]

        return BoardSnapshot(
            modifiedAt: referenceDate,
            journals: journals,
            manuscripts: manuscripts,
            submissionEvents: events,
            targets: targets,
            relationships: relationships
        )
    }
}
