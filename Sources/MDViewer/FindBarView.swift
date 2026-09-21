import SwiftUI

/// Floating find bar shown over the preview: query field, match counter, match-case toggle
/// and previous/next/close controls.
struct FindBarView: View {
    @ObservedObject var findState: FindState
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Find", text: $findState.query)
                .textFieldStyle(.plain)
                .focused($isFieldFocused)
                .frame(width: 180)
                .onSubmit { findState.goToNextMatch() }

            Text(findState.statusText)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)
                .frame(width: 70, alignment: .trailing)

            Toggle(isOn: $findState.isCaseSensitive) {
                Text("Aa").font(.caption.weight(.semibold))
            }
            .toggleStyle(.button)
            .help("Match case")

            Button {
                findState.goToPreviousMatch()
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(!findState.hasMatches)
            .help("Previous match (⇧⌘G)")

            Button {
                findState.goToNextMatch()
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(!findState.hasMatches)
            .help("Next match (⌘G)")

            Button {
                findState.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .help("Close find bar (esc)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.secondary.opacity(0.25))
        }
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
        .onAppear { focusField() }
        .onChange(of: findState.focusRequest) { _ in focusField() }
        .onExitCommand { findState.dismiss() }
    }

    /// Deferred by a run loop turn so the field wins first responder from the web view
    /// that sits underneath it.
    private func focusField() {
        DispatchQueue.main.async {
            isFieldFocused = true
        }
    }
}
