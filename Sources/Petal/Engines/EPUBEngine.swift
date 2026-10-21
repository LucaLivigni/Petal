import AppKit

/// EPUB 3 reading and writing without outside tools.
enum EPUBEngine {
    // MARK: Writing

    static func write(markdown: String, title: String, to dest: URL) async throws {
        let chapters = split(markdown, title: title)
        let id = "urn:uuid:\(UUID().uuidString.lowercased())"
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: "\\.\\d+", with: "", options: .regularExpression)
        let x = OfficePackage.xmlEscape

        var files: [(path: String, data: Data)] = []
        files.append(("META-INF/container.xml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container"><rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>
        """.utf8)))

        var manifest = "<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/><item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>"
        var spine = ""
        var toc = ""
        for (i, chapter) in chapters.enumerated() {
            let name = "chapter\(i + 1).xhtml"
            manifest += "<item id=\"c\(i + 1)\" href=\"\(name)\" media-type=\"application/xhtml+xml\"/>"
            spine += "<itemref idref=\"c\(i + 1)\"/>"
            toc += "<li><a href=\"\(name)\">\(x(chapter.title))</a></li>"
            let page = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en"><head><meta charset="utf-8"/><title>\(x(chapter.title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head><body>\(MarkdownHTML.renderBody(chapter.body, xhtml: true))</body></html>
            """
            files.append(("OEBPS/\(name)", Data(page.utf8)))
        }
        files.append(("OEBPS/nav.xhtml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="en"><head><meta charset="utf-8"/><title>\(x(title))</title></head><body><nav epub:type="toc" id="toc"><h1>\(x(title))</h1><ol>\(toc)</ol></nav></body></html>
        """.utf8)))
        files.append(("OEBPS/style.css", Data("body{font-family:serif;line-height:1.45;margin:5%}h1,h2,h3{font-family:sans-serif;line-height:1.2}code,pre{font-family:monospace}blockquote{color:#555;margin-left:1em}".utf8)))
        files.append(("OEBPS/content.opf", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:identifier id="bookid">\(id)</dc:identifier><dc:title>\(x(title))</dc:title><dc:language>en</dc:language><meta property="dcterms:modified">\(date)</meta></metadata><manifest>\(manifest)</manifest><spine>\(spine)</spine></package>
        """.utf8)))
        try await OfficePackage.write(files, to: dest, mimetype: "application/epub+zip")
    }

    /// Splits at top-level headings so the e-reader gets a table of contents.
    private static func split(_ markdown: String, title: String) -> [(title: String, body: String)] {
        let lines = markdown.components(separatedBy: "\n")
        var chapters: [(String, [String])] = []
        for line in lines {
            if line.hasPrefix("# ") { chapters.append((String(line.dropFirst(2)), [line])) }
            else if chapters.isEmpty { chapters.append((title, [line])) }
            else { chapters[chapters.count - 1].1.append(line) }
        }
        let result = chapters.map { (title: $0.0, body: $0.1.joined(separator: "\n")) }.filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return result.isEmpty ? [(title, markdown)] : result
    }

    // MARK: Reading

    static func read(_ url: URL) async throws -> NSAttributedString {
        let root = try await OfficePackage.unpack(url)
        defer { try? FileManager.default.removeItem(at: root) }

        guard let container = try? Data(contentsOf: root.appendingPathComponent("META-INF/container.xml")),
              let opfPath = XMLCollector.parse(container).first(where: { $0.isStart && $0.name == "rootfile" })?.attributes["full-path"],
              let opf = try? Data(contentsOf: root.appendingPathComponent(opfPath)) else {
            throw PetalError("Can't read \(url.lastPathComponent).")
        }
        var manifest: [String: String] = [:]
        var spine: [String] = []
        for e in XMLCollector.parse(opf) where e.isStart {
            if e.name == "item", let id = e.attributes["id"], let href = e.attributes["href"] { manifest[id] = href }
            if e.name == "itemref", let idref = e.attributes["idref"] { spine.append(idref) }
        }
        let base = root.appendingPathComponent(opfPath).deletingLastPathComponent()
        let result = NSMutableAttributedString()
        for id in spine {
            guard let href = manifest[id]?.removingPercentEncoding else { continue }
            let file = base.appendingPathComponent(href)
            guard let data = try? Data(contentsOf: file) else { continue }
            let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue,
                .baseURL: file,
            ]
            if let chapter = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
                result.append(chapter)
                result.append(NSAttributedString(string: "\n"))
            }
        }
        guard result.length > 0 else { throw PetalError("This EPUB has no readable chapters.") }
        return result
    }
}
