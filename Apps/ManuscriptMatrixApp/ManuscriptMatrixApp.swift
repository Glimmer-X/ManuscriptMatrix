import AppKit
import ManuscriptApplication
import ManuscriptDesignSystem
import ManuscriptInfrastructure
import MatrixFeature
import SwiftUI

@main
struct ManuscriptMatrixApp: App {
    @StateObject private var store: BoardCommandService
    @AppStorage(MMPreferenceKey.appearance) private var appearanceRawValue = MMAppearancePreference.system.rawValue
    @AppStorage(MMPreferenceKey.interfaceLanguage) private var languageRawValue = MMInterfaceLanguage.simplifiedChinese.rawValue
    @State private var exportedScreenshot = false

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let usesDemoBoard = arguments.contains("--demo") || arguments.contains("--export-demo-screenshot")
        if arguments.contains("--export-demo-screenshot") {
            NSApplication.shared.setActivationPolicy(.prohibited)
        }
        let repository: any BoardRepository = usesDemoBoard
            ? InMemoryBoardRepository(snapshot: DemoBoardFactory.make())
            : JSONBoardRepository()
        _store = StateObject(wrappedValue: BoardCommandService(repository: repository))
    }

    var body: some Scene {
        WindowGroup {
            MatrixRootView(store: store)
                .environment(\.locale, interfaceLanguage.locale)
                .preferredColorScheme(appearance.colorScheme)
                .task {
                    await store.load()
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "--export-demo-screenshot"), !exportedScreenshot {
                        exportedScreenshot = true
                        do {
                            guard arguments.indices.contains(index + 1) else {
                                throw CocoaError(.fileNoSuchFile)
                            }
                            try await DemoScreenshotExporter.export(
                                store: store,
                                destination: URL(fileURLWithPath: arguments[index + 1]),
                                language: interfaceLanguage
                            )
                            NSApplication.shared.terminate(nil)
                        } catch {
                            FileHandle.standardError.write(Data("Screenshot export failed: \(error)\n".utf8))
                            exit(1)
                        }
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1_420, height: 860)
        .commands {
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Board Change") {
                    Task { try? await store.undo() }
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!store.canUndo)
            }
        }

        Settings {
            ManuscriptMatrixSettingsView()
        }
    }

    private var appearance: MMAppearancePreference {
        MMAppearancePreference(rawValue: appearanceRawValue) ?? .system
    }

    private var interfaceLanguage: MMInterfaceLanguage {
        MMInterfaceLanguage(rawValue: languageRawValue) ?? .simplifiedChinese
    }
}
