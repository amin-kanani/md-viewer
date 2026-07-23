import Foundation
import Combine

/// Holds the rendered HTML for the currently open document and keeps it in sync with the
/// file on disk, so edits made in another app show up here without reopening.
@MainActor
final class RenderState: ObservableObject {
    @Published private(set) var html: String
    @Published var errorMessage: String?
    @Published var theme: ThemeMode {
        didSet { rerender() }
    }
    let baseURL: URL?

    private var currentMarkdown: String
    private let fileURL: URL?
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitoredHandle: FileHandle?

    init(text: String, fileURL: URL?, theme: ThemeMode = .system) {
        self.fileURL = fileURL
        self.baseURL = fileURL?.deletingLastPathComponent()
        self.currentMarkdown = text
        self.theme = theme
        self.html = MarkdownRenderer.renderHTML(markdown: text, baseURL: fileURL?.deletingLastPathComponent(), theme: theme)
    }

    func startWatching() {
        guard monitorSource == nil, let fileURL else { return }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
        monitoredHandle = handle

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: handle.fileDescriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.reloadFromDisk()
            self?.stopWatching()
            self?.startWatching()
        }
        source.setCancelHandler { [weak handle] in
            try? handle?.close()
        }
        monitorSource = source
        source.resume()
    }

    func stopWatching() {
        monitorSource?.cancel()
        monitorSource = nil
        monitoredHandle = nil
    }

    func reloadFromDisk() {
        guard let fileURL else { return }
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            currentMarkdown = text
            rerender()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reload \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func rerender() {
        html = MarkdownRenderer.renderHTML(markdown: currentMarkdown, baseURL: baseURL, theme: theme)
    }
}
