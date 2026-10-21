import AppKit

/// Turns rich text (from DOCX, RTF, HTML, EPUB or a PDF page) into Markdown, and reflows hard-wrapped PDF text.
nonisolated enum MarkdownWriter {
    static func markdown(from text: NSAttributedString) -> String {
        let full = text.string as NSString
        guard full.length > 0 else { return "" }
        let body = bodySize(text)

        var blocks: [(text: String, isList: Bool)] = []
        full.enumerateSubstrings(in: NSRange(location: 0, length: full.length), options: .byParagraphs) { _, range, _, _ in
            let raw = full.substring(with: range)
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }

            // Which size and weight does this paragraph use?
            var size: CGFloat = body
            var allBold = true
            if let first = (raw as NSString).range(of: trimmed).location as Int?, first != NSNotFound {
                let at = min(range.location + first, full.length - 1)
                if let font = text.attribute(.font, at: at, effectiveRange: nil) as? NSFont { size = font.pointSize }
            }
            text.enumerateAttribute(.font, in: range) { value, _, _ in
                if let font = value as? NSFont, !font.fontDescriptor.symbolicTraits.contains(.bold) { allBold = false }
            }

            var level = 0
            if size >= body * 1.65 { level = 1 } else if size >= body * 1.35 { level = 2 } else if size >= body * 1.15 { level = 3 }
            if level == 0, allBold, trimmed.count < 70, !trimmed.hasSuffix("."), size >= body { level = 4 }

            if level > 0 {
                blocks.append((String(repeating: "#", count: min(level, 4)) + " " + trimmed.replacingOccurrences(of: "\n", with: " "), false))
                return
            }
            if let list = listItem(trimmed) {
                blocks.append((list, true))
                return
            }
            blocks.append((inline(text, range: range), false))
        }

        var out = ""
        for (i, block) in blocks.enumerated() {
            if i > 0 { out += blocks[i - 1].isList && block.isList ? "\n" : "\n\n" }
            out += block.text
        }
        return out + "\n"
    }

    // MARK: Pieces

    private static func bodySize(_ text: NSAttributedString) -> CGFloat {
        var weights: [Int: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont { weights[Int(font.pointSize.rounded()), default: 0] += range.length }
        }
        return CGFloat(weights.max { $0.value < $1.value }?.key ?? 12)
    }

    private static func listItem(_ s: String) -> String? {
        if let m = s.firstMatch(of: /(?s)^[•◦▪‣\-–*]\s+(.*)$/) { return "- " + m.1.replacingOccurrences(of: "\n", with: " ") }
        if let m = s.firstMatch(of: /(?s)^(\d{1,3})[.)]\s+(.*)$/) { return "\(m.1). " + m.2.replacingOccurrences(of: "\n", with: " ") }
        // Lists that came from HTML carry the bare number, a tab, then the text.
        if let m = s.firstMatch(of: /(?s)^(\d{1,3})\t(.*)$/) { return "\(m.1). " + m.2.replacingOccurrences(of: "\n", with: " ") }
        return nil
    }

    private static func inline(_ text: NSAttributedString, range: NSRange) -> String {
        var out = ""
        text.enumerateAttributes(in: range) { attrs, runRange, _ in
            var piece = (text.string as NSString).substring(with: runRange).replacingOccurrences(of: "\n", with: " ")
            guard !piece.trimmingCharacters(in: .whitespaces).isEmpty else { out += piece; return }

            let lead = String(piece.prefix { $0 == " " || $0 == "\t" })
            let trail = String(piece.reversed().prefix { $0 == " " || $0 == "\t" }.reversed())
            piece = piece.trimmingCharacters(in: .whitespaces)

            let traits = (attrs[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if traits.contains(.monoSpace) {
                piece = "`\(piece)`"
            } else {
                let bold = traits.contains(.bold), italic = traits.contains(.italic)
                if bold && italic { piece = "***\(piece)***" } else if bold { piece = "**\(piece)**" } else if italic { piece = "*\(piece)*" }
            }
            if let link = attrs[.link] {
                let url = (link as? URL)?.absoluteString ?? "\(link)"
                piece = "[\(piece)](\(url))"
            }
            out += lead + piece + trail
        }
        // Adjacent runs with the same markers read better merged: "**a** **b**" → "**a b**".
        return out.replacing(/\*\*( +)\*\*/) { String($0.1) }.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Reflow

    /// PDFs break every visual line with a newline. Join lines back into paragraphs and undo hyphenation.
    static func reflow(_ text: NSAttributedString) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let s = result.string as NSString
        var indices: [Int] = []
        var i = 0
        while i < s.length {
            if s.character(at: i) == 10 { indices.append(i) }
            i += 1
        }
        for index in indices.reversed() {
            guard index > 0, index + 1 < s.length else { continue }
            let prev = s.character(at: index - 1), next = s.character(at: index + 1)
            if prev == 10 || next == 10 { continue }                                    // paragraph break already
            let prevChar = Character(UnicodeScalar(prev) ?? " "), nextChar = Character(UnicodeScalar(next) ?? " ")

            // Different type sizes mean a heading boundary: keep the break.
            let a = (result.attribute(.font, at: index - 1, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            let b = (result.attribute(.font, at: index + 1, effectiveRange: nil) as? NSFont)?.pointSize ?? 0
            if abs(a - b) >= 1.2 { result.replaceCharacters(in: NSRange(location: index, length: 1), with: "\n\n"); continue }

            let endsSentence = ".!?:;”\")".contains(prevChar)
            // A list item always starts on its own line.
            let tail = s.substring(with: NSRange(location: index + 1, length: min(10, s.length - index - 1)))
            if tail.firstMatch(of: /^([•◦▪‣]\s?|[-–*]\s|\d{1,3}[.)]\s)/) != nil { continue }
            if prevChar == "-" && nextChar.isLowercase && index >= 2 && Character(UnicodeScalar(s.character(at: index - 2)) ?? " ").isLetter {
                result.replaceCharacters(in: NSRange(location: index - 1, length: 2), with: "")   // "inter-\nnational"
            } else if endsSentence && nextChar.isUppercase && (s.length - index) > 0 && lineIsShort(s, before: index) {
                continue                                                                      // short line ending a sentence
            } else {
                result.replaceCharacters(in: NSRange(location: index, length: 1), with: " ")
            }
        }
        return result
    }

    private static func lineIsShort(_ s: NSString, before index: Int) -> Bool {
        let lineStart = s.range(of: "\n", options: .backwards, range: NSRange(location: 0, length: index)).location
        let length = index - (lineStart == NSNotFound ? 0 : lineStart + 1)
        return length < 45
    }
}
