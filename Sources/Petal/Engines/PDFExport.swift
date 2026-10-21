import AppKit
import PDFKit
import ImageIO

/// Turns PDFs into editable or presentable formats: DOCX, PAGES, MD, EPUB, PPTX, XLSX and more.
@MainActor
enum PDFExport {
    /// The text of every page, with type sizes kept so headings survive, and lines joined back into paragraphs.
    static func attributedText(_ src: URL) throws -> NSAttributedString {
        guard let doc = PDFDocument(url: src) else { throw PetalError("Can't read \(src.lastPathComponent).") }
        let all = NSMutableAttributedString()
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            if let text = page.attributedString, text.length > 0 {
                all.append(text)
            } else if let plain = page.string {
                all.append(NSAttributedString(string: plain, attributes: [.font: NSFont.systemFont(ofSize: 11)]))
            }
            all.append(NSAttributedString(string: "\n\n"))
        }
        guard !all.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetalError("This PDF has no selectable text. Use Copy text on the Tools wheel to read scanned pages.")
        }
        return MarkdownWriter.reflow(all)
    }

    static func toDocument(_ src: URL, format: DocFormat, ctx: JobContext) async throws -> URL {
        let text = try attributedText(src)
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        try await TextEngine.write(text, as: format, title: src.deletingPathExtension().lastPathComponent, to: dest)
        return dest
    }

    static func toPPTX(_ src: URL, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let slides = try renderSlides(src, step: step)
        let dest = ctx.policy.destination(for: src, ext: "pptx")
        try await PPTXWriter.write(slides, to: dest)
        return dest
    }

    private static func renderSlides(_ src: URL, step: (Double) -> Void) throws -> [PPTXWriter.Slide] {
        guard let doc = CGPDFDocument(src as CFURL), doc.numberOfPages > 0 else { throw PetalError("Can't read \(src.lastPathComponent).") }
        var slides: [PPTXWriter.Slide] = []
        for i in 1...doc.numberOfPages {
            guard let page = doc.page(at: i) else { continue }
            let image = try PDFEngine.render(page: page, dpi: 150)
            let data = NSMutableData()
            guard let out = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw PetalError("JPEG export isn't available.") }
            CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: 0.88] as CFDictionary)
            guard CGImageDestinationFinalize(out) else { throw PetalError("Couldn't render page \(i).") }
            slides.append(.init(jpeg: data as Data, size: CGSize(width: image.width, height: image.height)))
            step(Double(i) / Double(doc.numberOfPages))
        }
        return slides
    }

    /// Rebuilds rows and columns from where the characters sit on the page: a wide horizontal gap starts a new cell.
    static func toXLSX(_ src: URL, ctx: JobContext) async throws -> URL {
        guard let doc = PDFDocument(url: src), let text = doc.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetalError("This PDF has no selectable text.")
        }
        let rows = SpreadsheetEngine.trimmed(tableRows(doc))
        guard !rows.isEmpty else { throw PetalError("No table found in this PDF.") }
        let dest = ctx.policy.destination(for: src, ext: "xlsx")
        try await SpreadsheetEngine.write(rows, toExtension: "xlsx", at: dest, title: src.deletingPathExtension().lastPathComponent)
        return dest
    }

    private static func tableRows(_ doc: PDFDocument) -> [[String]] {
        var rows: [[String]] = []
        for p in 0..<doc.pageCount {
            guard let page = doc.page(at: p), let string = page.string as NSString? else { continue }
            var cells: [String] = []
            var current = ""
            var rowY: CGFloat?
            var lastMaxX: CGFloat?

            func flushCell() {
                let cell = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cell.isEmpty { cells.append(cell) }
                current = ""
            }
            func flushRow() {
                flushCell()
                if !cells.isEmpty { rows.append(cells) }
                cells = []; rowY = nil; lastMaxX = nil
            }

            for i in 0..<string.length {
                let ch = string.substring(with: NSRange(location: i, length: 1))
                if ch == "\n" || ch == "\r" { flushRow(); continue }
                // Spaces only separate words; positions come from the visible characters.
                if ch.trimmingCharacters(in: .whitespaces).isEmpty { current += ch; continue }
                // `characterBounds(at:)` drifts by one after each line break, selections stay aligned with the text.
                guard let b = page.selection(for: NSRange(location: i, length: 1))?.bounds(for: page), b.height > 0 else { current += ch; continue }
                if let y = rowY, abs(b.midY - y) > b.height * 0.6 { flushRow() }
                if let last = lastMaxX, b.minX - last > b.height * 0.6 { flushCell() }
                rowY = rowY ?? b.midY
                current += ch
                lastMaxX = b.maxX
            }
            flushRow()
        }
        return rows
    }
}
