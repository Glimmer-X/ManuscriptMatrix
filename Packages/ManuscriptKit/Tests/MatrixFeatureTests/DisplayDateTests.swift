import AppKit
import ManuscriptApplication
import ManuscriptDomain
import ManuscriptInfrastructure
import SwiftUI
import XCTest
@testable import MatrixFeature

final class DisplayDateTests: XCTestCase {
    @MainActor
    func testDisplayClockRefreshesImmediatelyAfterActivationWakeAndClockChange() async throws {
        let hosting = NSHostingView(rootView: DisplayDateScope { ClockProbe() })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 60),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }

        let notifications: [(NotificationCenter, Notification.Name)] = [
            (.default, NSApplication.didBecomeActiveNotification),
            (NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification),
            (.default, .NSSystemClockDidChange)
        ]
        for (center, name) in notifications {
            let before = try await pixels(of: hosting)
            center.post(name: name, object: nil)
            let after = try await pixels(of: hosting)
            XCTAssertNotEqual(before, after, "The display clock must catch up immediately after \(name).")
        }
    }

    @MainActor
    func testUnchangedEquatableCellsRefreshWhenOnlyDisplayDateChanges() async throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        var board = DemoBoardFactory.make(referenceDate: now)
        let manuscript = board.manuscripts[0]
        let journal = board.journals[2]
        let revisionDate = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        board.submissionEvents.append(SubmissionEvent(
            manuscriptID: manuscript.id, journalID: journal.id,
            journalNameSnapshot: journal.currentName, kind: .majorRevision,
            occurredAt: revisionDate
        ))
        let store = BoardCommandService(repository: InMemoryBoardRepository(snapshot: board), initialBoard: board)
        let early = Calendar.current.date(byAdding: .day, value: -4, to: now)!
        XCTAssertEqual(MMDateText.elapsed(from: revisionDate, to: early), "1d")
        XCTAssertEqual(MMDateText.elapsed(from: revisionDate, to: now), "5d")

        // Include both a live revision and a historical decision in both matrix densities.
        for venue in [journal, board.journals[0]] {
            for density in [MatrixDensity.overview, .detailed] {
                let source = DateSource(date: early)
                let cell = MatrixCellView(
                    store: store, manuscript: manuscript, journal: venue,
                    projection: board.manuscriptProjection(for: manuscript.id), target: nil,
                    events: board.events(for: manuscript.id, journalID: venue.id),
                    density: density, onInspect: {}
                )
                let root = DateHarness(source: source, content: cell.equatable())
                let hosting = NSHostingView(rootView: root)
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 220, height: 110),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                window.contentView = hosting
                defer { window.close() }
                let before = try await pixels(of: hosting)
                source.date = now
                let after = try await pixels(of: hosting)
                XCTAssertNotEqual(before, after, "A cached cell must update without any board mutation.")
                XCTAssertEqual(store.board, board, "Clock updates must never modify persisted board data.")
            }
        }
    }

    @MainActor
    private func pixels<V: View>(of view: NSHostingView<V>) async throws -> Data {
        view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
    }
}

@MainActor
private final class DateSource: ObservableObject {
    @Published var date: Date
    init(date: Date) { self.date = date }
}

private struct DateHarness<Content: View>: View {
    @ObservedObject var source: DateSource
    let content: Content

    var body: some View {
        content.environment(\.displayDate, source.date)
    }
}

private struct ClockProbe: View {
    @Environment(\.displayDate) private var displayDate

    var body: some View {
        Text(displayDate.timeIntervalSinceReferenceDate, format: .number.precision(.fractionLength(3)))
            .monospacedDigit()
    }
}
