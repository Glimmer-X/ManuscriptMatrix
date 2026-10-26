import AppKit
import ManuscriptApplication
import ManuscriptDesignSystem
import MatrixFeature
import SwiftUI

/// Renders the actual application view with an in-memory fictional board.
/// The caller selects this route before constructing any persistent repository.
@MainActor
enum DemoScreenshotExporter {
    static func export(
        store: BoardCommandService,
        destination: URL,
        language: MMInterfaceLanguage
    ) async throws {
        let content = VStack(spacing: 0) {
            MatrixRootView(store: store)
            Text("DEMO · All manuscripts, venues and metrics are fictional")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.white)
        }
        .environment(\.locale, language.locale)
        .environment(\.colorScheme, .light)
        .frame(width: 1_660, height: 940)

        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_660, height: 940),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: destination, options: .atomic)
    }
}
