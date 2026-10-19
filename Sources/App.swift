import SwiftUI

/// App entry point: the editor window, a menu bar item for quick capture, and keyboard commands.
@main
struct ShotPolishStudioApp: App {
    @StateObject private var state = AppState.shared

    var body: some Scene {
        Window("ShotPolishStudio", id: "main") {
            ContentView()
                .environmentObject(state)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open Image…") { state.openImage() }.keyboardShortcut("o")
                Button("Capture Region (\(GlobalHotKey.displayString))") { state.startCapture() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save As…") { state.saveAs() }.keyboardShortcut("s")
                Button("Save to Default Folder") { state.saveToDefaultFolder() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Redaction Change") { state.undo() }.keyboardShortcut("z")
            }
            CommandGroup(replacing: .pasteboard) {
                Button("Copy Image") { state.copyToClipboard() }.keyboardShortcut("c")
                Button("Paste Image") { state.paste() }.keyboardShortcut("v")
            }
            CommandGroup(replacing: .help) {
                Button("Support / Donate ❤️") { AppState.openDonation() }
            }
        }

        MenuBarExtra("ShotPolishStudio", systemImage: "camera.aperture") {
            MenuBarMenu().environmentObject(state)
        }
    }
}

/// Contents of the menu bar item.
struct MenuBarMenu: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Capture Region  \(GlobalHotKey.displayString)") { state.startCapture() }
        Button("Open Image…") { state.openImage() }
        Button("Show Editor") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Support / Donate ❤️") { AppState.openDonation() }
        Divider()
        Button("Quit ShotPolishStudio") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
