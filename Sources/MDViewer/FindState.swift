import SwiftUI
import WebKit

/// Drives "find in document": owns the search query and options, asks the page's injected
/// JavaScript to highlight/step through matches, and publishes the counters shown in the
/// find bar. The rendered document lives inside a `WKWebView`, so all of the actual text
/// matching happens in the page itself (see `injectedScript`).
@MainActor
final class FindState: ObservableObject {
    @Published private(set) var isPresented = false
    @Published private(set) var matchCount = 0
    /// 1-based position of the highlighted match, or 0 when there is none.
    @Published private(set) var currentMatch = 0
    /// Bumped whenever the find field should (re)take keyboard focus, e.g. on a second ⌘F.
    @Published private(set) var focusRequest = 0

    @Published var query = "" {
        didSet {
            guard query != oldValue else { return }
            scheduleSearch()
        }
    }

    @Published var isCaseSensitive = false {
        didSet {
            guard isCaseSensitive != oldValue else { return }
            scheduleSearch()
        }
    }

    private weak var webView: WKWebView?
    private var searchTask: Task<Void, Never>?

    var hasMatches: Bool { matchCount > 0 }

    var statusText: String {
        guard !query.isEmpty else { return "" }
        guard matchCount > 0 else { return "Not found" }
        return "\(currentMatch) of \(matchCount)"
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    func present() {
        isPresented = true
        focusRequest &+= 1
        if !query.isEmpty { runSearch() }
    }

    func dismiss() {
        searchTask?.cancel()
        searchTask = nil
        isPresented = false
        matchCount = 0
        currentMatch = 0
        evaluate("window.__mdFind && window.__mdFind.clear();", updatesCounters: false)
    }

    func toggle() {
        if isPresented {
            dismiss()
        } else {
            present()
        }
    }

    func goToNextMatch() { step(1) }

    func goToPreviousMatch() { step(-1) }

    /// Re-applies the current search after the page reloads (live reload from disk), because
    /// reloading wipes the highlight markup back out of the DOM.
    func refreshAfterReload() {
        guard isPresented, !query.isEmpty else { return }
        runSearch()
    }

    private func step(_ delta: Int) {
        guard isPresented else {
            present()
            return
        }
        guard hasMatches else { return }
        evaluate("window.__mdFind && window.__mdFind.step(\(delta));")
    }

    /// Debounced so that typing in a large document doesn't re-walk the DOM on every keystroke.
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            self?.runSearch()
        }
    }

    private func runSearch() {
        let script = "window.__mdFind && window.__mdFind.search(\(Self.jsLiteral(query)), \(isCaseSensitive));"
        evaluate(script)
    }

    private func evaluate(_ script: String, updatesCounters: Bool = true) {
        guard let webView else { return }
        webView.evaluateJavaScript(script) { [weak self] result, _ in
            guard updatesCounters, let self else { return }
            let payload = result as? [String: Any]
            let count = (payload?["count"] as? NSNumber)?.intValue ?? 0
            let index = (payload?["index"] as? NSNumber)?.intValue ?? 0
            Task { @MainActor in
                self.applyMatchCounters(count: count, index: index)
            }
        }
    }

    private func applyMatchCounters(count: Int, index: Int) {
        guard isPresented else { return }
        matchCount = count
        currentMatch = index
    }

    /// Renders a Swift string as a JavaScript string literal (quotes included).
    private static func jsLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count > 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }
}

extension FindState {
    /// Injected into every rendered document at load time. Highlights matches by wrapping
    /// them in `<mark class="md-find-hit">` (styled by `MarkdownRenderer`) and keeps track of
    /// which one is current. Matches are found across the concatenated text of the document,
    /// so a phrase that straddles inline markup (`**bold** text`) still matches; each match is
    /// wrapped per text node, which keeps the surrounding element structure intact.
    static let injectedScript = #"""
    (function () {
        var HIT_CLASS = 'md-find-hit';
        var CURRENT_CLASS = 'md-find-hit-current';
        var hits = [];
        var currentIndex = -1;

        function state() {
            return { count: hits.length, index: currentIndex + 1 };
        }

        function clearHighlights() {
            var marks = document.querySelectorAll('mark.' + HIT_CLASS);
            var parents = [];
            for (var i = 0; i < marks.length; i++) {
                var mark = marks[i];
                var parent = mark.parentNode;
                if (!parent) { continue; }
                while (mark.firstChild) {
                    parent.insertBefore(mark.firstChild, mark);
                }
                parent.removeChild(mark);
                if (parents.indexOf(parent) === -1) { parents.push(parent); }
            }
            for (var p = 0; p < parents.length; p++) {
                parents[p].normalize();
            }
            hits = [];
            currentIndex = -1;
        }

        function collectText() {
            var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                acceptNode: function (node) {
                    if (!node.nodeValue || node.nodeValue.length === 0) {
                        return NodeFilter.FILTER_REJECT;
                    }
                    var parent = node.parentNode;
                    if (!parent) { return NodeFilter.FILTER_REJECT; }
                    var tag = parent.nodeName;
                    if (tag === 'SCRIPT' || tag === 'STYLE' || tag === 'NOSCRIPT' || tag === 'TEXTAREA') {
                        return NodeFilter.FILTER_REJECT;
                    }
                    return NodeFilter.FILTER_ACCEPT;
                }
            });
            var chunks = [];
            var text = '';
            var node;
            while ((node = walker.nextNode())) {
                chunks.push({ node: node, start: text.length, length: node.nodeValue.length });
                text += node.nodeValue;
            }
            return { chunks: chunks, text: text };
        }

        function findRanges(text, query, caseSensitive) {
            var haystack = text;
            var needle = query;
            if (!caseSensitive) {
                var lowerText = text.toLowerCase();
                var lowerQuery = query.toLowerCase();
                // Some characters change length when lowercased; fall back to an exact
                // match rather than corrupting the offsets.
                if (lowerText.length === text.length && lowerQuery.length === query.length) {
                    haystack = lowerText;
                    needle = lowerQuery;
                }
            }
            var ranges = [];
            var from = 0;
            while (true) {
                var index = haystack.indexOf(needle, from);
                if (index === -1) { break; }
                ranges.push([index, index + needle.length]);
                from = index + needle.length;
            }
            return ranges;
        }

        function wrapSegment(node, startOffset, endOffset) {
            if (endOffset <= startOffset) { return null; }
            var range = document.createRange();
            range.setStart(node, startOffset);
            range.setEnd(node, endOffset);
            var mark = document.createElement('mark');
            mark.className = HIT_CLASS;
            try {
                range.surroundContents(mark);
            } catch (error) {
                return null;
            }
            return mark;
        }

        function highlight(ranges, chunks) {
            var result = [];
            var cursor = chunks.length - 1;
            // Walk backwards so that splitting a text node never invalidates the offsets of
            // the matches that are still to be wrapped (those all sit earlier in the node).
            for (var i = ranges.length - 1; i >= 0; i--) {
                var rangeStart = ranges[i][0];
                var rangeEnd = ranges[i][1];
                while (cursor > 0 && chunks[cursor].start >= rangeEnd) { cursor--; }
                var marks = [];
                var k = cursor;
                while (k >= 0 && chunks[k].start + chunks[k].length > rangeStart) {
                    var chunk = chunks[k];
                    if (chunk.start < rangeEnd) {
                        var startOffset = Math.max(rangeStart, chunk.start) - chunk.start;
                        var endOffset = Math.min(rangeEnd, chunk.start + chunk.length) - chunk.start;
                        var mark = wrapSegment(chunk.node, startOffset, endOffset);
                        if (mark) { marks.unshift(mark); }
                    }
                    k--;
                }
                cursor = Math.min(Math.max(k + 1, 0), chunks.length - 1);
                if (marks.length) { result.unshift(marks); }
            }
            return result;
        }

        function setCurrent(index, scroll) {
            for (var i = 0; i < hits.length; i++) {
                for (var m = 0; m < hits[i].length; m++) {
                    hits[i][m].classList.remove(CURRENT_CLASS);
                }
            }
            currentIndex = (index >= 0 && index < hits.length) ? index : -1;
            if (currentIndex === -1) { return; }
            var marks = hits[currentIndex];
            for (var c = 0; c < marks.length; c++) {
                marks[c].classList.add(CURRENT_CLASS);
            }
            if (scroll && marks[0]) {
                marks[0].scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'smooth' });
            }
        }

        // Prefers the first match at or below the top of the viewport so that searching
        // doesn't yank the reader back to the top of the document.
        function preferredIndex() {
            for (var i = 0; i < hits.length; i++) {
                if (hits[i][0].getBoundingClientRect().top >= 0) { return i; }
            }
            return hits.length ? 0 : -1;
        }

        window.__mdFind = {
            search: function (query, caseSensitive) {
                clearHighlights();
                if (!query || !document.body) { return state(); }
                var collected = collectText();
                var ranges = findRanges(collected.text, query, !!caseSensitive);
                hits = highlight(ranges, collected.chunks);
                setCurrent(preferredIndex(), true);
                return state();
            },
            step: function (delta) {
                if (!hits.length) { return state(); }
                var next = (currentIndex + delta % hits.length + hits.length) % hits.length;
                setCurrent(next, true);
                return state();
            },
            clear: function () {
                clearHighlights();
                return state();
            }
        };
    })();
    """#
}

/// Lets the Find menu commands reach the find bar of whichever document window is focused.
struct FindStateFocusedValueKey: FocusedValueKey {
    typealias Value = FindState
}

extension FocusedValues {
    var findState: FindState? {
        get { self[FindStateFocusedValueKey.self] }
        set { self[FindStateFocusedValueKey.self] = newValue }
    }
}
