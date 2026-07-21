import SwiftUI
import UniformTypeIdentifiers

/// A read-only Markdown document. Used with `DocumentGroup(viewing:)`, so only reading
/// is ever exercised by the app; `fileWrapper(configuration:)` exists solely to satisfy
/// the `FileDocument` protocol and is never invoked because the viewer exposes no save UI.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [UTType(importedAs: "net.daringfireball.markdown"), .plainText]
    }

    var text: String

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let string = String(data: data, encoding: .utf8) {
            text = string
        } else if let string = String(data: data, encoding: .isoLatin1) {
            text = string
        } else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
