import Foundation

/// A small Markdown → HTML renderer: headings, emphasis, code, lists, quotes, links, rules.
nonisolated enum MarkdownHTML {
    /// A full HTML page.
    static func render(_ markdown: String) -> String {
        """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica; font-size: 12pt; color: #000; }
        code, pre { font-family: Menlo, monospace; font-size: 10.5pt; }
        blockquote { color: #555; }
        </style></head><body>\(renderBody(markdown))</body></html>
        """
    }

    /// Just the body markup. With `xhtml` every tag is well-formed, as EPUB requires.
    static func renderBody(_ markdown: String, xhtml: Bool = false) -> String {
        var html: [String] = []
        var paragraph: [String] = []
        var listKind: String?
        var inCode = false
        var codeLines: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }
        func closeList() {
            if let kind = listKind { html.append("</\(kind)>"); listKind = nil }
        }

        for raw in markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .init(charactersIn: "\t "))
            if line.hasPrefix("```") {
                if inCode {
                    html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines.removeAll()
                } else {
                    flushParagraph(); closeList()
                }
                inCode.toggle()
                continue
            }
            if inCode { codeLines.append(raw); continue }

            if line.isEmpty { flushParagraph(); closeList(); continue }

            if let match = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flushParagraph(); closeList()
                let level = match.1.count
                html.append("<h\(level)>\(inline(String(match.2)))</h\(level)>")
            } else if line.wholeMatch(of: /^(-{3,}|\*{3,}|_{3,})$/) != nil {
                flushParagraph(); closeList()
                html.append(xhtml ? "<hr/>" : "<hr>")
            } else if let match = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flushParagraph()
                if listKind != "ul" { closeList(); html.append("<ul>"); listKind = "ul" }
                html.append("<li>\(inline(String(match.1)))</li>")
            } else if let match = line.firstMatch(of: /^\d+[.)]\s+(.*)$/) {
                flushParagraph()
                if listKind != "ol" { closeList(); html.append("<ol>"); listKind = "ol" }
                html.append("<li>\(inline(String(match.1)))</li>")
            } else if let match = line.firstMatch(of: /^>\s?(.*)$/) {
                flushParagraph(); closeList()
                html.append("<blockquote>\(inline(String(match.1)))</blockquote>")
            } else {
                closeList()
                paragraph.append(line)
            }
        }
        if inCode { html.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>") }
        flushParagraph(); closeList()

        return html.joined(separator: "\n")
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func inline(_ text: String) -> String {
        var s = escape(text)
        s = s.replacing(/`([^`]+)`/) { "<code>\($0.1)</code>" }
        s = s.replacing(/\*\*(.+?)\*\*/) { "<b>\($0.1)</b>" }
        s = s.replacing(/__(.+?)__/) { "<b>\($0.1)</b>" }
        s = s.replacing(/\*(.+?)\*/) { "<i>\($0.1)</i>" }
        s = s.replacing(/(^|[^\w])_(.+?)_(?![\w])/) { "\($0.1)<i>\($0.2)</i>" }
        s = s.replacing(/\[([^\]]+)\]\(([^)\s]+)\)/) { "<a href=\"\($0.2)\">\($0.1)</a>" }
        return s
    }
}
