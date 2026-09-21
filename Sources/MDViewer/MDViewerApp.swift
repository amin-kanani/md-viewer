import SwiftUI

@main
struct MDViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            MarkdownView(document: file.document, fileURL: file.fileURL)
        }
        .commands {
            FindCommands()
        }
    }
}

/// Edit-menu entries that drive the find bar of the focused document window.
struct FindCommands: Commands {
    @FocusedValue(\.findState) private var findState

    var body: some Commands {
        CommandGroup(after: .textEditing) {
            Divider()
            Button("Find…") { findState?.present() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findState == nil)
            Button("Find Next") { findState?.goToNextMatch() }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(findState == nil)
            Button("Find Previous") { findState?.goToPreviousMatch() }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(findState == nil)
        }
    }
}
