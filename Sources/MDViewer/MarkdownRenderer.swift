import Foundation

/// Converts Markdown source into a complete, styled HTML document ready to hand to a WKWebView.
enum MarkdownRenderer {
    static func renderHTML(markdown: String, baseURL: URL?) -> String {
        let body = MarkdownToHTML.convert(markdown)
        return wrap(body: body, baseURL: baseURL)
    }

    private static func wrap(body: String, baseURL: URL?) -> String {
        let baseTag = baseURL.map { "<base href=\"\($0.absoluteString)\">" } ?? ""
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        \(baseTag)
        <style>\(css)</style>
        </head>
        <body>
        <article class="markdown-body">
        \(body)
        </article>
        </body>
        </html>
        """
    }

    private static let css = """
    :root { color-scheme: light dark; }

    html, body {
        margin: 0;
        padding: 0;
        background: #ffffff;
    }

    body {
        font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
        font-size: 15px;
        line-height: 1.6;
        color: #1f2328;
    }

    .markdown-body {
        max-width: 860px;
        margin: 0 auto;
        padding: 32px 40px 64px;
        word-wrap: break-word;
    }

    .markdown-body h1, .markdown-body h2, .markdown-body h3,
    .markdown-body h4, .markdown-body h5, .markdown-body h6 {
        font-weight: 600;
        margin-top: 24px;
        margin-bottom: 16px;
        line-height: 1.25;
    }
    .markdown-body h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid #d8dee4; }
    .markdown-body h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid #d8dee4; }
    .markdown-body h3 { font-size: 1.25em; }
    .markdown-body h4 { font-size: 1.1em; }
    .markdown-body h5 { font-size: 1em; }
    .markdown-body h6 { font-size: .9em; color: #59636e; }

    .markdown-body p, .markdown-body ul, .markdown-body ol,
    .markdown-body blockquote, .markdown-body table, .markdown-body pre {
        margin-top: 0;
        margin-bottom: 16px;
    }

    .markdown-body a { color: #0969da; text-decoration: none; }
    .markdown-body a:hover { text-decoration: underline; }

    .markdown-body code {
        font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
        font-size: 0.9em;
        background: rgba(175, 184, 193, 0.2);
        padding: 0.2em 0.4em;
        border-radius: 6px;
    }

    .markdown-body pre {
        background: #f6f8fa;
        padding: 16px;
        border-radius: 8px;
        overflow-x: auto;
    }
    .markdown-body pre code {
        background: none;
        padding: 0;
        font-size: 0.85em;
    }

    .markdown-body blockquote {
        margin-left: 0;
        padding: 0 1em;
        color: #59636e;
        border-left: 4px solid #d8dee4;
    }

    .markdown-body table {
        border-collapse: collapse;
        width: 100%;
        display: block;
        overflow-x: auto;
    }
    .markdown-body th, .markdown-body td {
        border: 1px solid #d8dee4;
        padding: 6px 13px;
    }
    .markdown-body tr:nth-child(2n) { background: #f6f8fa; }
    .markdown-body th { font-weight: 600; background: #f6f8fa; }

    .markdown-body img { max-width: 100%; box-sizing: border-box; }

    .markdown-body hr {
        height: .25em;
        border: 0;
        background: #d8dee4;
        margin: 24px 0;
    }

    .markdown-body ul, .markdown-body ol { padding-left: 2em; }
    .markdown-body li + li { margin-top: 0.25em; }

    .markdown-body input[type="checkbox"] { margin-right: 0.5em; }

    @media (prefers-color-scheme: dark) {
        html, body { background: #0d1117; }
        body { color: #e6edf3; }
        .markdown-body h1, .markdown-body h2 { border-bottom-color: #30363d; }
        .markdown-body h6 { color: #9198a1; }
        .markdown-body a { color: #4493f8; }
        .markdown-body code { background: rgba(110, 118, 129, 0.4); }
        .markdown-body pre { background: #161b22; }
        .markdown-body blockquote { color: #9198a1; border-left-color: #30363d; }
        .markdown-body th, .markdown-body td { border-color: #30363d; }
        .markdown-body tr:nth-child(2n) { background: #161b22; }
        .markdown-body th { background: #161b22; }
        .markdown-body hr { background: #30363d; }
    }
    """
}
