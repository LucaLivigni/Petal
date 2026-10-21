import AppKit

/// Draws a table onto paginated PDF pages, with a repeating header and zebra rows.
@MainActor
enum TablePDF {
    static func render(_ rows: [[String]], title: String, to url: URL) throws {
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { throw PetalError("This table is empty.") }

        let landscape = columns > 5
        let page = landscape ? CGSize(width: 841.89, height: 595.28) : CGSize(width: 595.28, height: 841.89)
        let margin: CGFloat = 36
        let content = CGSize(width: page.width - margin * 2, height: page.height - margin * 2 - 16)
        let rowHeight: CGFloat = 19
        let padding: CGFloat = 5

        let body = NSFont.systemFont(ofSize: 9)
        let bold = NSFont.systemFont(ofSize: 9, weight: .semibold)
        var natural = [CGFloat](repeating: 30, count: columns)
        for (r, row) in rows.prefix(400).enumerated() {
            for (c, value) in row.enumerated() {
                let font = r == 0 ? bold : body
                let width = (value as NSString).size(withAttributes: [.font: font]).width + padding * 2
                natural[c] = min(240, max(natural[c], width))
            }
        }
        let total = natural.reduce(0, +)
        let scale = total > content.width ? content.width / total : 1
        let widths = natural.map { $0 * scale }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        func attributes(_ font: NSFont, _ color: NSColor = .black) -> [NSAttributedString.Key: Any] {
            [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
        }

        let header = rows.count > 1 ? rows[0] : nil
        let bodyRows = header == nil ? rows : Array(rows.dropFirst())
        let perPage = max(1, Int((content.height - (header == nil ? 0 : rowHeight)) / rowHeight))
        let pages = max(1, (bodyRows.count + perPage - 1) / perPage)

        var box = CGRect(origin: .zero, size: page)
        guard let consumer = CGDataConsumer(url: url as CFURL), let pdf = CGContext(consumer: consumer, mediaBox: &box, nil) else {
            throw PetalError("Couldn't create the PDF.")
        }

        func drawRow(_ row: [String], y: CGFloat, font: NSFont, fill: NSColor?) {
            if let fill {
                fill.setFill()
                NSRect(x: margin, y: y, width: widths.reduce(0, +), height: rowHeight).fill()
            }
            var x = margin
            for c in 0..<columns {
                let value = c < row.count ? row[c] : ""
                (value as NSString).draw(in: NSRect(x: x + padding, y: y + 4, width: widths[c] - padding * 2, height: rowHeight - 4),
                                         withAttributes: attributes(font))
                x += widths[c]
            }
        }

        for p in 0..<pages {
            pdf.beginPDFPage(nil)
            pdf.saveGState()
            pdf.translateBy(x: 0, y: page.height)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)

            var y = margin
            if let header {
                drawRow(header, y: y, font: bold, fill: NSColor(white: 0.93, alpha: 1))
                y += rowHeight
            }
            let slice = bodyRows[(p * perPage)..<min((p + 1) * perPage, bodyRows.count)]
            for (i, row) in slice.enumerated() {
                drawRow(row, y: y, font: body, fill: i % 2 == 1 ? NSColor(white: 0.97, alpha: 1) : nil)
                y += rowHeight
            }
            let footer = "\(title)    \(p + 1) / \(pages)"
            (footer as NSString).draw(at: NSPoint(x: margin, y: page.height - margin + 2), withAttributes: [.font: NSFont.systemFont(ofSize: 8), .foregroundColor: NSColor.gray])

            NSGraphicsContext.restoreGraphicsState()
            pdf.restoreGState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }
}
