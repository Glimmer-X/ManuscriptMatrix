import AppKit
import SwiftUI

private struct DisplayDateKey: EnvironmentKey {
    static var defaultValue: Date { .now }
}

extension EnvironmentValues {
    var displayDate: Date {
        get { self[DisplayDateKey.self] }
        set { self[DisplayDateKey.self] = newValue }
    }
}

/// A presentation-only clock. Its lifetime follows the window, without writing board data.
struct DisplayDateScope<Content: View>: View {
    @State private var anchor = Date.now
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        TimelineView(.periodic(from: anchor, by: 60)) { context in
            content.environment(\.displayDate, context.date)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            anchor = .now
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            anchor = .now
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            anchor = .now
        }
    }
}
