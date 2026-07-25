import SwiftUI

/// Sidebar listing the document's headings in order; tapping one scrolls the preview to
/// that heading via `selection`.
struct TableOfContentsView: View {
    let headings: [Heading]
    @Binding var selection: String?

    var body: some View {
        Group {
            if headings.isEmpty {
                emptyState
            } else {
                List(headings) { heading in
                    Button {
                        selection = heading.id
                    } label: {
                        Text(heading.text)
                            .font(font(for: heading.level))
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, CGFloat(heading.level - 1) * 12)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.sidebar)
            }
        }
        .navigationTitle("Contents")
        .frame(minWidth: 180)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.rectangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Headings")
                .font(.headline)
            Text("This document has no headings to outline.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func font(for level: Int) -> Font {
        switch level {
        case 1: return .headline
        case 2: return .subheadline.weight(.semibold)
        default: return .subheadline
        }
    }
}
