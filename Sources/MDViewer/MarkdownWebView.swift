import SwiftUI
import WebKit
import AppKit
import PDFKit

/// Wraps a WKWebView to render the pre-built HTML string, and routes clicked links
/// (http/https/mailto/etc.) out to the user's default apps instead of navigating away
/// inside the preview. In-document anchor links (e.g. a Table of Contents entry or a
/// `[Back to top](#top)` link) are left to WebKit to handle in place.
struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    var theme: ThemeMode = .system
    @Binding var shouldPrint: Bool
    @Binding var scrollToHeadingID: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var lastLoadedHTML: String?
        var lastAppliedTheme: ThemeMode?
        var baseURL: URL?
        weak var webView: WKWebView?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                if isSameDocumentAnchor(url) {
                    // Let WebKit scroll to the in-page heading instead of treating it as
                    // an external navigation.
                    decisionHandler(.allow)
                    return
                }
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// True for a bare `#slug` link that resolves (via the page's `<base>` tag) back to
        /// the document's own directory, i.e. an anchor jump within the currently loaded
        /// document rather than a link to another file or an external URL.
        private func isSameDocumentAnchor(_ target: URL) -> Bool {
            guard let baseURL, target.fragment != nil else { return false }
            var components = URLComponents(url: target, resolvingAgainstBaseURL: true)
            components?.fragment = nil
            return components?.url?.absoluteString == baseURL.absoluteString
        }

        func printContent() {
            guard let webView else { return }
            webView.createPDF(configuration: WKPDFConfiguration()) { result in
                DispatchQueue.main.async {
                    guard case .success(let data) = result,
                          let pdfDoc = PDFDocument(data: data),
                          let window = webView.window else { return }
                    let printInfo = NSPrintInfo.shared.copy() as! NSPrintInfo
                    guard let printOp = pdfDoc.printOperation(
                        for: printInfo,
                        scalingMode: .pageScaleToFit,
                        autoRotate: true
                    ) else { return }
                    printOp.showsPrintPanel = true
                    printOp.showsProgressPanel = true
                    printOp.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                }
            }
        }
    }

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        context.coordinator.baseURL = baseURL
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.baseURL = baseURL

        // Handle print request — deferred to avoid blocking the SwiftUI update cycle.
        if shouldPrint {
            DispatchQueue.main.async {
                self.shouldPrint = false
                coordinator.printContent()
            }
            return
        }

        // Handle a Table of Contents selection — scroll smoothly to the heading's id
        // without reloading the page or disturbing the rest of the scroll position logic.
        if let headingID = scrollToHeadingID {
            DispatchQueue.main.async {
                self.scrollToHeadingID = nil
            }
            let escapedID = headingID.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            webView.evaluateJavaScript(
                "document.getElementById(\"\(escapedID)\")?.scrollIntoView({behavior: 'smooth', block: 'start'});",
                completionHandler: nil
            )
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
