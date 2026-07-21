import Foundation

/// A small, dependency-free Markdown → HTML converter covering the CommonMark/GitHub-flavored
/// Markdown subset used by the overwhelming majority of real-world README-style documents: ATX
/// and setext headings, paragraphs, emphasis/strong/strikethrough, inline code, fenced code
/// blocks, block quotes, ordered/unordered/task lists, links, images, tables, thematic breaks
/// and hard line breaks. It does not attempt full CommonMark spec compliance (e.g. raw HTML
/// passthrough or exhaustive nested-emphasis edge cases) — an acceptable trade-off so the app
/// can ship with zero external dependencies.
enum MarkdownToHTML {
    static func convert(_ markdown: String) -> String {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        return renderBlocks(normalized.components(separatedBy: "\n"))
    }

    // MARK: - Block level

    private static func renderBlocks(_ lines: [String]) -> String {
        var html = ""
        var i = 0
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).isEmpty {
                i += 1
                continue
            }
            if let (block, next) = matchFencedCode(lines, i) { html += block; i = next; continue }
            if let (block, next) = matchThematicBreak(lines, i) { html += block; i = next; continue }
            if let (block, next) = matchHeading(lines, i) { html += block; i = next; continue }
            if let (block, next) = matchTable(lines, i) { html += block; i = next; continue }
            if let (block, next) = matchBlockquote(lines, i) { html += block; i = next; continue }
            if let (block, next) = matchList(lines, i) { html += block; i = next; continue }
            let (block, next) = matchParagraph(lines, i)
            html += block
            i = next
        }
        return html
    }

    // MARK: Fenced code blocks

    private static func matchFencedCode(_ lines: [String], _ i: Int) -> (String, Int)? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard let fenceChar = trimmed.first, fenceChar == "`" || fenceChar == "~" else { return nil }
        let fenceLen = trimmed.prefix(while: { $0 == fenceChar }).count
        guard fenceLen >= 3 else { return nil }
        let info = trimmed.dropFirst(fenceLen).trimmingCharacters(in: .whitespaces)
        let language = info.split(separator: " ").first.map(String.init) ?? ""

        var j = i + 1
        var codeLines: [String] = []
        while j < lines.count {
            let closeTrimmed = lines[j].trimmingCharacters(in: .whitespaces)
            if closeTrimmed.count >= fenceLen, closeTrimmed.allSatisfy({ $0 == fenceChar }) {
                j += 1
                break
            }
            codeLines.append(lines[j])
            j += 1
        }

        let code = codeLines.joined(separator: "\n")
        let langAttr = language.isEmpty ? "" : " class=\"language-\(escapeHTML(language))\""
        return ("<pre><code\(langAttr)>\(escapeHTML(code))</code></pre>\n", j)
    }

    // MARK: Thematic breaks

    private static func isThematicBreakLine(_ trimmed: String) -> Bool {
        guard trimmed.count >= 3 else { return false }
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func matchThematicBreak(_ lines: [String], _ i: Int) -> (String, Int)? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard isThematicBreakLine(trimmed) else { return nil }
        return ("<hr />\n", i + 1)
    }

    // MARK: ATX headings

    private static func matchHeading(_ lines: [String], _ i: Int) -> (String, Int)? {
        let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard level >= 1, level <= 6 else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.isEmpty || rest.first == " " else { return nil }
        var content = rest.trimmingCharacters(in: .whitespaces)
        if let closingRange = content.range(of: #"[ \t]+#+$"#, options: .regularExpression) {
            content.removeSubrange(closingRange)
        }
        return ("<h\(level)>\(renderInline(content))</h\(level)>\n", i + 1)
    }

    // MARK: Block quotes

    private static func isBlockquoteLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix(">")
    }

    private static func stripBlockquoteMarker(_ line: String) -> String {
        var s = Substring(line)
        while s.first == " " { s.removeFirst() }
        guard s.first == ">" else { return line }
        s.removeFirst()
        if s.first == " " { s.removeFirst() }
        return String(s)
    }

    private static func matchBlockquote(_ lines: [String], _ i: Int) -> (String, Int)? {
        guard isBlockquoteLine(lines[i]) else { return nil }
        var inner: [String] = []
        var j = i
        while j < lines.count {
            let line = lines[j]
            if isBlockquoteLine(line) {
                inner.append(stripBlockquoteMarker(line))
                j += 1
            } else if j > i, !line.trimmingCharacters(in: .whitespaces).isEmpty {
                // Lazy continuation of a quoted paragraph.
                inner.append(line)
                j += 1
            } else {
                break
            }
        }
        let innerHTML = renderBlocks(inner)
        return ("<blockquote>\n\(innerHTML)</blockquote>\n", j)
    }

    // MARK: Lists

    private struct ListMarker {
        let ordered: Bool
        let start: Int
        let markerWidth: Int
        let content: String
        let checkbox: Bool?
    }

    private static func parseListMarker(_ line: String) -> ListMarker? {
        let chars = Array(line)
        var idx = 0
        var leadingSpaces = 0
        while idx < chars.count, chars[idx] == " " {
            leadingSpaces += 1
            idx += 1
        }
        guard leadingSpaces <= 3, idx < chars.count else { return nil }

        var ordered = false
        var start = 1
        if chars[idx] == "-" || chars[idx] == "*" || chars[idx] == "+" {
            idx += 1
        } else if chars[idx].isNumber {
            var numStr = ""
            let numStart = idx
            while idx < chars.count, chars[idx].isNumber {
                numStr.append(chars[idx])
                idx += 1
            }
            guard idx - numStart <= 9, idx < chars.count, (chars[idx] == "." || chars[idx] == ")") else { return nil }
            ordered = true
            start = Int(numStr) ?? 1
            idx += 1
        } else {
            return nil
        }

        if idx == chars.count {
            return ListMarker(ordered: ordered, start: start, markerWidth: idx, content: "", checkbox: nil)
        }
        guard chars[idx] == " " else { return nil }
        idx += 1

        let markerWidth = idx
        var content = String(chars[idx...])

        var checkbox: Bool?
        let lowerPrefix = content.lowercased()
        if lowerPrefix.hasPrefix("[ ] ") {
            checkbox = false
            content = String(content.dropFirst(4))
        } else if lowerPrefix.hasPrefix("[x] ") {
            checkbox = true
            content = String(content.dropFirst(4))
        }

        return ListMarker(ordered: ordered, start: start, markerWidth: markerWidth, content: content, checkbox: checkbox)
    }

    private static func startsWithIndent(_ line: String, atLeast width: Int) -> Bool {
        guard width > 0, line.count > width else { return false }
        return line.prefix(width).allSatisfy { $0 == " " }
    }

    private static func matchList(_ lines: [String], _ i: Int) -> (String, Int)? {
        guard let first = parseListMarker(lines[i]) else { return nil }
        let ordered = first.ordered

        struct RawItem { var contentLines: [String]; var checkbox: Bool? }
        var items: [RawItem] = []
        var j = i

        while j < lines.count {
            guard let marker = parseListMarker(lines[j]), marker.ordered == ordered else { break }
            items.append(RawItem(contentLines: [marker.content], checkbox: marker.checkbox))
            j += 1

            while j < lines.count {
                let line = lines[j]
                if line.trimmingCharacters(in: .whitespaces).isEmpty {
                    if j + 1 < lines.count, startsWithIndent(lines[j + 1], atLeast: max(marker.markerWidth, 2)) {
                        items[items.count - 1].contentLines.append("")
                        j += 1
                        continue
                    } else {
                        break
                    }
                } else if startsWithIndent(line, atLeast: marker.markerWidth) {
                    items[items.count - 1].contentLines.append(String(line.dropFirst(marker.markerWidth)))
                    j += 1
                } else {
                    break
                }
            }
        }

        let tag = ordered ? "ol" : "ul"
        let startAttr = (ordered && first.start != 1) ? " start=\"\(first.start)\"" : ""
        var html = "<\(tag)\(startAttr)>\n"
        for item in items {
            let checkboxHTML: String
            switch item.checkbox {
            case .some(true): checkboxHTML = "<input type=\"checkbox\" checked disabled> "
            case .some(false): checkboxHTML = "<input type=\"checkbox\" disabled> "
            case .none: checkboxHTML = ""
            }
            let inner = item.contentLines.count == 1
                ? renderInline(item.contentLines[0])
                : renderBlocks(item.contentLines)
            html += "<li>\(checkboxHTML)\(inner)</li>\n"
        }
        html += "</\(tag)>\n"
        return (html, j)
    }

    // MARK: Tables (GFM)

    private static func splitTableRow(_ line: String) -> [String] {
        var s = line.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }

        var cells: [String] = []
        var current = ""
        var escaping = false
        for ch in s {
            if escaping {
                current.append(ch)
                escaping = false
            } else if ch == "\\" {
                // Consume the backslash itself so `\|` collapses to a literal `|`.
                escaping = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }

    private static func parseTableSeparator(_ line: String) -> [String?]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return nil }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return nil }
        var alignments: [String?] = []
        for cell in cells {
            let c = cell.trimmingCharacters(in: .whitespaces)
            guard !c.isEmpty, c.allSatisfy({ $0 == "-" || $0 == ":" }), c.contains("-") else { return nil }
            let left = c.hasPrefix(":")
            let right = c.hasSuffix(":")
            if left && right { alignments.append("center") }
            else if right { alignments.append("right") }
            else if left { alignments.append("left") }
            else { alignments.append(nil) }
        }
        return alignments
    }

    private static func alignAttr(_ align: String?) -> String {
        guard let align else { return "" }
        return " align=\"\(align)\""
    }

    private static func matchTable(_ lines: [String], _ i: Int) -> (String, Int)? {
        guard i + 1 < lines.count, lines[i].contains("|") else { return nil }
        guard let alignments = parseTableSeparator(lines[i + 1]) else { return nil }

        let headerCells = splitTableRow(lines[i])
        guard !headerCells.isEmpty else { return nil }

        var html = "<table>\n<thead>\n<tr>\n"
        for (idx, cell) in headerCells.enumerated() {
            let align = idx < alignments.count ? alignments[idx] : nil
            html += "<th\(alignAttr(align))>\(renderInline(cell))</th>\n"
        }
        html += "</tr>\n</thead>\n<tbody>\n"

        var j = i + 2
        while j < lines.count {
            let line = lines[j]
            if line.trimmingCharacters(in: .whitespaces).isEmpty || !line.contains("|") { break }
            let cells = splitTableRow(line)
            html += "<tr>\n"
            let columnCount = max(cells.count, headerCells.count)
            for idx in 0..<columnCount {
                let content = idx < cells.count ? cells[idx] : ""
                let align = idx < alignments.count ? alignments[idx] : nil
                html += "<td\(alignAttr(align))>\(renderInline(content))</td>\n"
            }
            html += "</tr>\n"
            j += 1
        }
        html += "</tbody>\n</table>\n"
        return (html, j)
    }

    // MARK: Paragraphs (+ setext headings)

    /// A bare run of all `=` or all `-` characters. Recognized so the paragraph-gathering loop
    /// stops *before* consuming it, leaving it for `matchParagraph`'s setext-heading lookahead
    /// to classify (rather than swallowing it as ordinary paragraph text).
    private static func isSetextUnderline(_ trimmed: String) -> Bool {
        guard !trimmed.isEmpty else { return false }
        return trimmed.allSatisfy { $0 == "=" } || trimmed.allSatisfy { $0 == "-" }
    }

    private static func startsNewBlock(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }
        if let first = trimmed.first, (first == "`" || first == "~"), trimmed.prefix(while: { $0 == first }).count >= 3 {
            return true
        }
        if isThematicBreakLine(trimmed) { return true }
        if isSetextUnderline(trimmed) { return true }
        if trimmed.hasPrefix("#") {
            let level = trimmed.prefix(while: { $0 == "#" }).count
            if level >= 1, level <= 6 {
                let rest = trimmed.dropFirst(level)
                if rest.isEmpty || rest.first == " " { return true }
            }
        }
        if trimmed.hasPrefix(">") { return true }
        if parseListMarker(line) != nil { return true }
        return false
    }

    private static func matchParagraph(_ lines: [String], _ i: Int) -> (String, Int) {
        var j = i
        var collected: [String] = []
        while j < lines.count {
            let line = lines[j]
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            if j > i, startsNewBlock(line) { break }
            collected.append(line)
            j += 1
        }

        // Setext heading: one or more text lines immediately followed by an underline of
        // '=' (H1) or '-' (H2), with no intervening blank line.
        if !collected.isEmpty, j < lines.count {
            let underline = lines[j].trimmingCharacters(in: .whitespaces)
            if !underline.isEmpty, underline.allSatisfy({ $0 == "=" }) {
                return ("<h1>\(renderInline(collected.joined(separator: " ")))</h1>\n", j + 1)
            }
            if !underline.isEmpty, underline.allSatisfy({ $0 == "-" }) {
                return ("<h2>\(renderInline(collected.joined(separator: " ")))</h2>\n", j + 1)
            }
        }

        var htmlLines: [String] = []
        for line in collected {
            let hardBreak = line.hasSuffix("  ") || line.hasSuffix("\\")
            var text = line
            if hardBreak {
                while text.hasSuffix(" ") { text.removeLast() }
                if text.hasSuffix("\\") { text.removeLast() }
            }
            htmlLines.append(renderInline(text) + (hardBreak ? "<br>" : ""))
        }
        return ("<p>\(htmlLines.joined(separator: "\n"))</p>\n", j)
    }

    // MARK: - Inline level

    private static func renderInline(_ rawText: String) -> String {
        var placeholders: [String] = []

        // Autolinks must be matched on the *raw* text, before HTML-escaping turns their
        // '<'/'>' delimiters into entities.
        var text = replaceAutolinks(rawText, &placeholders)
        text = escapeHTML(text)

        text = replaceCodeSpans(text, &placeholders)
        text = replaceImages(text, &placeholders)
        text = replaceLinks(text, &placeholders)
        text = replaceEmphasisAndStrong(text)
        text = replaceStrikethrough(text)

        for (idx, value) in placeholders.enumerated() {
            text = text.replacingOccurrences(of: placeholderToken(idx), with: value)
        }
        return text
    }

    private static func placeholderToken(_ idx: Int) -> String {
        "\u{0}\(idx)\u{0}"
    }

    private static func escapeHTML(_ s: String) -> String {
        var result = s
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }

    private static func escapeAttr(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func replaceCodeSpans(_ text: String, _ placeholders: inout [String]) -> String {
        var result = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "`" {
                var tickCount = 0
                var j = i
                while j < chars.count, chars[j] == "`" { tickCount += 1; j += 1 }

                var k = j
                var closeStart: Int?
                while k < chars.count {
                    if chars[k] == "`" {
                        var closeCount = 0
                        var m = k
                        while m < chars.count, chars[m] == "`" { closeCount += 1; m += 1 }
                        if closeCount == tickCount {
                            closeStart = k
                            break
                        }
                        k = m
                    } else {
                        k += 1
                    }
                }

                if let closeStart {
                    var content = String(chars[j..<closeStart])
                    if content.count >= 2, content.hasPrefix(" "), content.hasSuffix(" ") {
                        content = String(content.dropFirst().dropLast())
                    }
                    let idx = placeholders.count
                    placeholders.append("<code>\(content)</code>")
                    result += placeholderToken(idx)
                    i = closeStart + tickCount
                    continue
                }
            }
            result.append(chars[i])
            i += 1
        }
        return result
    }

    private static func regexReplace(_ text: String, pattern: String, _ transform: (NSTextCheckingResult, String) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        var result = ""
        var lastEnd = 0
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for match in matches {
            guard match.range.location >= lastEnd else { continue }
            result += ns.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
            result += transform(match, text)
            lastEnd = match.range.location + match.range.length
        }
        result += ns.substring(from: lastEnd)
        return result
    }

    private static func group(_ match: NSTextCheckingResult, _ idx: Int, in text: String) -> String? {
        guard idx < match.numberOfRanges else { return nil }
        let range = match.range(at: idx)
        guard range.location != NSNotFound else { return nil }
        return (text as NSString).substring(with: range)
    }

    private static func replaceImages(_ text: String, _ placeholders: inout [String]) -> String {
        var local = placeholders
        let result = regexReplace(text, pattern: #"!\[([^\]]*)\]\(([^()\s]+)(?:\s+"([^"]*)")?\)"#) { match, t in
            let alt = group(match, 1, in: t) ?? ""
            let url = group(match, 2, in: t) ?? ""
            let title = group(match, 3, in: t)
            let titleAttr = title.map { " title=\"\(escapeAttr($0))\"" } ?? ""
            let idx = local.count
            local.append("<img src=\"\(escapeAttr(url))\" alt=\"\(escapeAttr(alt))\"\(titleAttr)>")
            return placeholderToken(idx)
        }
        placeholders = local
        return result
    }

    private static func replaceLinks(_ text: String, _ placeholders: inout [String]) -> String {
        var local = placeholders
        let result = regexReplace(text, pattern: #"\[([^\]]*)\]\(([^()\s]+)(?:\s+"([^"]*)")?\)"#) { match, t in
            let label = group(match, 1, in: t) ?? ""
            let url = group(match, 2, in: t) ?? ""
            let title = group(match, 3, in: t)
            let titleAttr = title.map { " title=\"\(escapeAttr($0))\"" } ?? ""
            let idx = local.count
            local.append("<a href=\"\(escapeAttr(url))\"\(titleAttr)>\(label)</a>")
            return placeholderToken(idx)
        }
        placeholders = local
        return result
    }

    private static func replaceAutolinks(_ text: String, _ placeholders: inout [String]) -> String {
        var local = placeholders
        var result = regexReplace(text, pattern: #"<((?:https?|mailto):[^<>\s]+)>"#) { match, t in
            let url = group(match, 1, in: t) ?? ""
            let escaped = escapeHTML(url)
            let idx = local.count
            local.append("<a href=\"\(escapeAttr(escaped))\">\(escaped)</a>")
            return placeholderToken(idx)
        }
        // Bare email autolinks, e.g. <name@example.com>, which don't spell out "mailto:".
        result = regexReplace(result, pattern: #"<([a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,})>"#) { match, t in
            let email = group(match, 1, in: t) ?? ""
            let escaped = escapeHTML(email)
            let idx = local.count
            local.append("<a href=\"mailto:\(escapeAttr(escaped))\">\(escaped)</a>")
            return placeholderToken(idx)
        }
        placeholders = local
        return result
    }

    private static func replaceEmphasisAndStrong(_ text: String) -> String {
        var result = text
        result = regexReplace(result, pattern: #"\*\*\*([^*]+?)\*\*\*"#) { m, t in "<strong><em>\(group(m, 1, in: t) ?? "")</em></strong>" }
        result = regexReplace(result, pattern: #"___([^_]+?)___"#) { m, t in "<strong><em>\(group(m, 1, in: t) ?? "")</em></strong>" }
        result = regexReplace(result, pattern: #"\*\*([^*]+?)\*\*"#) { m, t in "<strong>\(group(m, 1, in: t) ?? "")</strong>" }
        result = regexReplace(result, pattern: #"__([^_]+?)__"#) { m, t in "<strong>\(group(m, 1, in: t) ?? "")</strong>" }
        result = regexReplace(result, pattern: #"\*([^*]+?)\*"#) { m, t in "<em>\(group(m, 1, in: t) ?? "")</em>" }
        result = regexReplace(result, pattern: #"(?<![a-zA-Z0-9])_([^_]+?)_(?![a-zA-Z0-9])"#) { m, t in "<em>\(group(m, 1, in: t) ?? "")</em>" }
        return result
    }

    private static func replaceStrikethrough(_ text: String) -> String {
        regexReplace(text, pattern: #"~~([^~]+?)~~"#) { m, t in "<del>\(group(m, 1, in: t) ?? "")</del>" }
    }
}
