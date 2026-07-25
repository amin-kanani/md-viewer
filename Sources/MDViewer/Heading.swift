import Foundation

/// A single heading extracted while converting a document to HTML, used to build the
/// Table of Contents sidebar and to scroll the preview to the matching `id` element.
struct Heading: Identifiable, Equatable {
    let id: String
    let level: Int
    let text: String
}
