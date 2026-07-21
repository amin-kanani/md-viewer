import Foundation
import Combine

/// Holds the rendered HTML for the currently open document and keeps it in sync with the
/// file on disk, so edits made in another app show up here without reopening.
@MainActor
final class RenderState: ObservableObject {
    @Published private(set) var html: String
    @Published var errorMessage: String?
    let baseURL: URL?

    private let fileURL: URL?
    private var monitorSource: DispatchSourceFileSystemObject?
    private var monitoredHandle: FileHandle?

    init(text: String, fileURL: URL?) {
        self.fileURL = fileURL
        self.baseURL = fileURL?.deletingLastPathComponent()
        self.html = MarkdownRenderer.renderHTML(markdown: text, baseURL: baseURL)
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
            // Many editors save atomically (write a temp file, then rename it over the
            // original), which invalidates the descriptor we're watching. Re-attach so we
            // keep tracking the file at this path either way.
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
            html = MarkdownRenderer.renderHTML(markdown: text, baseURL: baseURL)
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reload \(fileURL.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
