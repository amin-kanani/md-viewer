import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct MarkdownView: View {
    @StateObject private var renderer: RenderState
    @AppStorage("themeMode") private var themeMode: ThemeMode = .system
    @State private var shouldPrint = false
    private let displayName: String

    init(document: MarkdownDocument, fileURL: URL?) {
        _renderer = StateObject(wrappedValue: RenderState(text: document.text, fileURL: fileURL))
        displayName = fileURL?.lastPathComponent ?? "Markdown"
    }

    var body: some View {
        MarkdownWebView(html: renderer.html, baseURL: renderer.baseURL, theme: renderer.theme, shouldPrint: $shouldPrint)
            .overlay(alignment: .top) {
                if let message = renderer.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .padding(8)
                        .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.top, 8)
                }
            }
            .navigationTitle(displayName)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        shouldPrint = true
                    } label: {
                        Label("Print", systemImage: "printer")
                    }
                    .help("Print this document")
                }
                ToolbarItem(placement: .automatic) {
                    Picker("Theme", selection: $themeMode) {
                        ForEach(ThemeMode.allCases) { mode in
                            Label(mode.label, systemImage: mode.iconName)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .help("Switch between light, dark, or system appearance")
                }
            }
            .onChange(of: themeMode) { newTheme in
                renderer.theme = newTheme
            }
            .onAppear {
                renderer.theme = themeMode
                renderer.startWatching()
            }
            .onDisappear { renderer.stopWatching() }
            .onDrop(of: [.fileURL], isTargeted: nil, perform: handleDrop)
    }

    /// Lets the user drag a different Markdown file onto an already-open viewer window
    /// to open it (in a new window), in addition to the standard Finder/Dock/File>Open paths.
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
            DispatchQueue.main.async {
                NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
            }
        }
        return true
    }
}
