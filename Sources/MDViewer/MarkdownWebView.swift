import SwiftUI
import WebKit
import AppKit

/// Wraps a WKWebView to render the pre-built HTML string, and routes clicked links
/// (http/https/mailto/etc.) out to the user's default apps instead of navigating away
/// inside the preview.
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    var theme: ThemeMode = .system
    @Binding var shouldPrint: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String?
        var lastAppliedTheme: ThemeMode?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator

        // Handle print request.
        if shouldPrint {
            DispatchQueue.main.async {
                self.shouldPrint = false
            }
            webView.printView(nil)
            return
        }

        // If only the theme changed, update via JS to preserve scroll position.
        if coordinator.lastLoadedHTML != nil,
           coordinator.lastLoadedHTML == html.replacingThemeAttribute(with: coordinator.lastAppliedTheme),
           coordinator.lastAppliedTheme != theme {
            coordinator.lastAppliedTheme = theme
            coordinator.lastLoadedHTML = html
            let value = theme.htmlAttribute ?? ""
            let js = value.isEmpty
                ? "document.documentElement.removeAttribute('data-theme');"
                : "document.documentElement.setAttribute('data-theme', '\(value)');"
            webView.evaluateJavaScript(js, completionHandler: nil)
            return
        }

        // Full reload when content actually changed.
        guard coordinator.lastLoadedHTML != html else { return }
        coordinator.lastLoadedHTML = html
        coordinator.lastAppliedTheme = theme
        webView.loadHTMLString(html, baseURL: baseURL)
    }
}

private extension String {
    /// Replaces the data-theme attribute in an HTML string for comparison purposes.
    func replacingThemeAttribute(with theme: ThemeMode?) -> String {
        guard let theme else { return self }
        let target: String
        switch theme {
        case .system:
            target = "<html>"
        case .light:
            target = "<html data-theme=\"light\">"
        case .dark:
            target = "<html data-theme=\"dark\">"
        }
        // Replace current theme attribute with the target's equivalent
        let patterns = [
            "<html>",
            "<html data-theme=\"light\">",
            "<html data-theme=\"dark\">"
        ]
        var result = self
        for pattern in patterns {
            if result.contains(pattern) {
                result = result.replacingOccurrences(of: pattern, with: target)
                break
            }
        }
        return result
    }
}
