import AppKit
import Foundation

nonisolated struct DocFormat: Sendable, Hashable {
    let ext: String
    let name: String

    static let pdf = DocFormat(ext: "pdf", name: "PDF")
    static let docx = DocFormat(ext: "docx", name: "DOCX")
    static let pages = DocFormat(ext: "pages", name: "PAGES")
    static let md = DocFormat(ext: "md", name: "MD")
    static let epub = DocFormat(ext: "epub", name: "EPUB")
    static let rtf = DocFormat(ext: "rtf", name: "RTF")
    static let html = DocFormat(ext: "html", name: "HTML")
    static let odt = DocFormat(ext: "odt", name: "ODT")
    static let txt = DocFormat(ext: "txt", name: "TXT")

    static let all: [DocFormat] = [.pdf, .docx, .pages, .md, .epub, .html, .rtf, .odt, .txt]
}

/// Rich-text conversions built on AppKit's text system. AppKit text work must stay on the main actor.
enum TextEngine {
    static func convert(_ src: URL, to format: DocFormat, ctx: JobContext) async throws -> URL {
        let text = try await loadAsync(src)
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        try await write(text, as: format, title: src.deletingPathExtension().lastPathComponent, to: dest)
        return dest
    }

    /// Writes rich text in any document format.
    static func write(_ text: NSAttributedString, as format: DocFormat, title: String, to dest: URL) async throws {
        let range = NSRange(location: 0, length: text.length)
        switch format {
        case .pdf:
            try renderPDF(text, to: dest)
        case .txt:
            try text.string.write(to: dest, atomically: true, encoding: .utf8)
        case .md:
            try MarkdownWriter.markdown(from: text).write(to: dest, atomically: true, encoding: .utf8)
        case .epub:
            try await EPUBEngine.write(markdown: MarkdownWriter.markdown(from: text), title: title, to: dest)
        case .rtf:
            try text.rtf(from: range, documentAttributes: [:])!.write(to: dest)
        case .html:
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.html]).write(to: dest)
        case .docx:
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: dest)
        case .odt:
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.openDocument]).write(to: dest)
        case .pages:
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(title)-\(UUID().uuidString).docx")
            defer { try? FileManager.default.removeItem(at: temp) }
            try text.data(from: range, documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: temp)
            try await IWorkBridge.saveAsPages(temp, to: dest)
        default:
            throw PetalError("Unsupported document format.")
        }
    }

    /// Like `load`, but also reads EPUB and Pages files, which need unpacking or another app.
    static func loadAsync(_ url: URL) async throws -> NSAttributedString {
        switch url.pathExtension.lowercased() {
        case "epub":
            return try await EPUBEngine.read(url)
        case "pages":
            guard IWorkBridge.isInstalled(.pages) else { throw PetalError("Reading Pages files needs Pages (free on the App Store).") }
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("petal-\(UUID().uuidString).docx")
            defer { try? FileManager.default.removeItem(at: temp) }
            try await IWorkBridge.pagesExport(url, as: .word, to: temp)
            return try load(temp)
        default:
            return try load(url)
        }
    }

    static func load(_ url: URL) throws -> NSAttributedString {
        switch url.pathExtension.lowercased() {
        case "md", "markdown":
            let md = try readString(url)
            return try attributed(fromHTML: MarkdownHTML.render(md))
        case "txt":
            let font = NSFont.systemFont(ofSize: 12)
            return NSAttributedString(string: try readString(url), attributes: [.font: font, .foregroundColor: NSColor.black])
        case "html", "htm":
            return try attributed(fromHTML: try readString(url))
        default:
            do {
                return try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            } catch {
                throw PetalError("Can't read \(url.lastPathComponent).")
            }
        }
    }

    private static func attributed(fromHTML html: String) throws -> NSAttributedString {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        return try NSAttributedString(data: Data(html.utf8), options: options, documentAttributes: nil)
    }

    private static func readString(_ url: URL) throws -> String {
        var encoding = String.Encoding.utf8
        if let s = try? String(contentsOf: url, usedEncoding: &encoding) { return s }
        let data = try Data(contentsOf: url)
        for candidate in [String.Encoding.windowsCP1252, .macOSRoman, .isoLatin1] {
            if let s = String(data: data, encoding: candidate) { return s }
        }
        throw PetalError("Can't read \(url.lastPathComponent).")
    }

    /// Paginates attributed text onto A4 pages with TextKit.
    static func renderPDF(_ text: NSAttributedString, to url: URL) throws {
        let pageSize = CGSize(width: 595.28, height: 841.89)
        let margin: CGFloat = 56
        let content = CGSize(width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)

        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)

        var containers: [NSTextContainer] = []
        repeat {
            let container = NSTextContainer(size: content)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            layout.ensureLayout(for: container)
        } while NSMaxRange(layout.glyphRange(for: containers.last!)) < layout.numberOfGlyphs && containers.count < 2_000

        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PetalError("Couldn't create the PDF.")
        }
        for container in containers {
            pdf.beginPDFPage(nil)
            pdf.saveGState()
            pdf.translateBy(x: margin, y: pageSize.height - margin)
            pdf.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: pdf, flipped: true)
            let glyphs = layout.glyphRange(for: container)
            layout.drawBackground(forGlyphRange: glyphs, at: .zero)
            layout.drawGlyphs(forGlyphRange: glyphs, at: .zero)
            NSGraphicsContext.restoreGraphicsState()
            pdf.restoreGState()
            pdf.endPDFPage()
        }
        pdf.closePDF()
    }
}
