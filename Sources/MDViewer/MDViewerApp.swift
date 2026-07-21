import SwiftUI

@main
struct MDViewerApp: App {
    var body: some Scene {
        DocumentGroup(viewing: MarkdownDocument.self) { file in
            MarkdownView(document: file.document, fileURL: file.fileURL)
        }
    }
}
