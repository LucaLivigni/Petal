import Foundation

/// Reads and writes tables: CSV, TSV, JSON, XLSX and ODS. Everything works on `[[String]]` rows.
nonisolated enum SpreadsheetEngine {
    static let formats: [(ext: String, name: String)] = [
        ("xlsx", "XLSX"), ("ods", "ODS"), ("csv", "CSV"), ("tsv", "TSV"), ("json", "JSON"), ("pdf", "PDF"), ("html", "HTML"),
    ]

    // MARK: Convert

    static func convert(_ src: URL, toExtension ext: String, ctx: JobContext) async throws -> URL {
        let rows = try await readRows(src)
        let dest = ctx.policy.destination(for: src, ext: ext)
        try await write(rows, toExtension: ext, at: dest, title: src.deletingPathExtension().lastPathComponent)
        return dest
    }

    static func write(_ rows: [[String]], toExtension ext: String, at dest: URL, title: String) async throws {
        switch ext {
        case "csv": try Data(DataEngine.writeDelimited(rows, delimiter: ",").utf8).write(to: dest)
        case "tsv": try Data(DataEngine.writeDelimited(rows, delimiter: "\t").utf8).write(to: dest)
        case "json": try DataEngine.jsonFromTable(rows).write(to: dest)
        case "xlsx": try await OfficePackage.write(xlsxFiles(rows), to: dest)
        case "ods": try await OfficePackage.write(odsFiles(rows), to: dest, mimetype: "application/vnd.oasis.opendocument.spreadsheet")
        case "html": try Data(html(rows, title: title).utf8).write(to: dest)
        case "pdf": try await MainActor.run { try TablePDF.render(rows, title: title, to: dest) }
        default: throw PetalError("Unsupported table format.")
        }
    }

    // MARK: Reading

    static func readRows(_ url: URL) async throws -> [[String]] {
        switch url.pathExtension.lowercased() {
        case "csv": return DataEngine.parseDelimited(try DataEngine.readText(url), delimiter: ",")
        case "tsv": return DataEngine.parseDelimited(try DataEngine.readText(url), delimiter: "\t")
        case "json": return try DataEngine.tableFromJSON(Data(try DataEngine.readText(url).utf8))
        case "xlsx", "xlsm": return try await readXLSX(url)
        case "ods": return try await readODS(url)
        case "xls", "numbers":
            return try await IWorkBridge.rowsViaNumbers(url)
        default: throw PetalError("Unsupported table format.")
        }
    }

    static func readXLSX(_ url: URL) async throws -> [[String]] {
        let root = try await OfficePackage.unpack(url)
        defer { try? FileManager.default.removeItem(at: root) }
        func data(_ path: String) -> Data? { try? Data(contentsOf: root.appendingPathComponent(path)) }

        // Find the first sheet's file through workbook.xml and its relationships.
        var sheetPath = "xl/worksheets/sheet1.xml"
        if let wb = data("xl/workbook.xml"), let rels = data("xl/_rels/workbook.xml.rels") {
            let firstRID = XMLCollector.parse(wb).first { $0.isStart && $0.name == "sheet" }?.attributes["r:id"]
            let target = XMLCollector.parse(rels).first { $0.isStart && $0.name == "Relationship" && $0.attributes["Id"] == firstRID }?.attributes["Target"]
            if let target { sheetPath = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target }
        }
        guard let sheetData = data(sheetPath) else { throw PetalError("This workbook has no readable sheet.") }

        var shared: [String] = []
        if let sst = data("xl/sharedStrings.xml") {
            var current = ""
            var inItem = false
            for e in XMLCollector.parse(sst) {
                if e.name == "si" { if e.isStart { inItem = true; current = "" } else { shared.append(current); inItem = false } }
                else if e.name == "t", !e.isStart, inItem { current += e.text }
            }
        }

        var rows: [[String]] = []
        var row: [String] = []
        var ref = "", type = "", value = "", inline = ""
        var inInline = false
        func column(_ ref: String) -> Int {
            var n = 0
            for ch in ref.unicodeScalars { guard ch.value >= 65, ch.value <= 90 else { break }; n = n * 26 + Int(ch.value - 64) }
            return max(0, n - 1)
        }
        for e in XMLCollector.parse(sheetData) {
            switch (e.name, e.isStart) {
            case ("row", true): row = []
            case ("row", false): rows.append(row)
            case ("c", true): ref = e.attributes["r"] ?? ""; type = e.attributes["t"] ?? ""; value = ""; inline = ""
            case ("v", false): value = e.text
            case ("is", true): inInline = true
            case ("is", false): inInline = false
            case ("t", false): if inInline { inline += e.text }
            case ("c", false):
                let text: String
                switch type {
                case "s": text = Int(value).flatMap { shared.indices.contains($0) ? shared[$0] : nil } ?? ""
                case "inlineStr": text = inline
                case "b": text = value == "1" ? "TRUE" : "FALSE"
                default: text = value
                }
                let col = ref.isEmpty ? row.count : column(ref)
                while row.count < col { row.append("") }
                row.append(text)
            default: break
            }
        }
        return trimmed(rows)
    }

    static func readODS(_ url: URL) async throws -> [[String]] {
        let root = try await OfficePackage.unpack(url)
        defer { try? FileManager.default.removeItem(at: root) }
        guard let content = try? Data(contentsOf: root.appendingPathComponent("content.xml")) else { throw PetalError("Can't read \(url.lastPathComponent).") }

        var rows: [[String]] = []
        var row: [String] = []
        var paragraphs: [String] = []
        var numeric: String?
        var tables = 0, depth = 0
        var rowRepeat = 1, colRepeat = 1
        for e in XMLCollector.parse(content) {
            switch (e.name, e.isStart) {
            case ("table:table", true): depth += 1; if depth == 1 { tables += 1 }
            case ("table:table", false): depth -= 1
            case ("table:table-row", true) where tables == 1:
                row = []; rowRepeat = Int(e.attributes["table:number-rows-repeated"] ?? "") ?? 1
            case ("table:table-row", false) where tables == 1:
                let blank = row.allSatisfy(\.isEmpty)
                for _ in 0..<(blank ? 1 : min(rowRepeat, 1000)) { rows.append(row) }
            case ("table:table-cell", true) where tables == 1, ("table:covered-table-cell", true) where tables == 1:
                colRepeat = Int(e.attributes["table:number-columns-repeated"] ?? "") ?? 1
                paragraphs = []
                numeric = e.attributes["office:value-type"] == "string" ? nil : e.attributes["office:value"]
            case ("text:p", false) where tables == 1: paragraphs.append(e.text)
            case ("table:table-cell", false) where tables == 1, ("table:covered-table-cell", false) where tables == 1:
                let text = numeric ?? paragraphs.joined(separator: "\n")
                for _ in 0..<(text.isEmpty ? 1 : min(colRepeat, 200)) { row.append(text) }
            default: break
            }
        }
        return trimmed(rows)
    }

    /// Drops empty trailing rows and columns so converted files don't carry thousands of blanks.
    static func trimmed(_ rows: [[String]]) -> [[String]] {
        var rows = rows
        while let last = rows.last, last.allSatisfy(\.isEmpty) { rows.removeLast() }
        let width = rows.map { r in (r.lastIndex { !$0.isEmpty }).map { $0 + 1 } ?? 0 }.max() ?? 0
        return rows.map { r in Array((r + Array(repeating: "", count: max(0, width - r.count))).prefix(width)) }
    }

    // MARK: Writing XLSX

    private static func columnName(_ index: Int) -> String {
        var n = index + 1, s = ""
        while n > 0 { let r = (n - 1) % 26; s = String(UnicodeScalar(UInt8(65 + r))) + s; n = (n - 1) / 26 }
        return s
    }

    private static func isNumber(_ s: String) -> Bool {
        guard !s.isEmpty, s.count < 16 else { return false }
        return s.wholeMatch(of: /-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?/) != nil
    }

    static func xlsxFiles(_ rows: [[String]]) -> [(path: String, data: Data)] {
        var strings: [String] = []
        var index: [String: Int] = [:]
        func sharedIndex(_ s: String) -> Int {
            if let i = index[s] { return i }
            strings.append(s); index[s] = strings.count - 1
            return strings.count - 1
        }

        let width = rows.map(\.count).max() ?? 0
        var widths = [Double](repeating: 8, count: width)
        var sheetRows = ""
        for (r, row) in rows.enumerated() {
            var cells = ""
            for (c, value) in row.enumerated() where !value.isEmpty {
                let ref = "\(columnName(c))\(r + 1)"
                let style = r == 0 && rows.count > 1 ? " s=\"1\"" : ""
                if isNumber(value) { cells += "<c r=\"\(ref)\"\(style)><v>\(value)</v></c>" }
                else { cells += "<c r=\"\(ref)\"\(style) t=\"s\"><v>\(sharedIndex(value))</v></c>" }
                widths[c] = min(60, max(widths[c], Double(value.prefix(60).count) * 1.15 + 2))
            }
            sheetRows += "<row r=\"\(r + 1)\">\(cells)</row>"
        }
        let cols = widths.enumerated().map { "<col min=\"\($0.offset + 1)\" max=\"\($0.offset + 1)\" width=\"\(String(format: "%.1f", $0.element))\" customWidth=\"1\"/>" }.joined()
        let pane = rows.count > 1 ? "<pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/>" : ""
        let ns = "xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\""
        let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

        let sheet = head + "<worksheet \(ns)><sheetViews><sheetView workbookViewId=\"0\">\(pane)</sheetView></sheetViews><cols>\(cols)</cols><sheetData>\(sheetRows)</sheetData></worksheet>"
        let sst = head + "<sst \(ns) count=\"\(strings.count)\" uniqueCount=\"\(strings.count)\">"
            + strings.map { "<si><t xml:space=\"preserve\">\(OfficePackage.xmlEscape($0))</t></si>" }.joined() + "</sst>"
        let styles = head + "<styleSheet \(ns)><fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>"
            + "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>"
            + "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>"
            + "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>"
            + "<cellXfs count=\"2\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/><xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/></cellXfs>"
            + "<cellStyles count=\"1\"><cellStyle name=\"Normal\" xfId=\"0\" builtinId=\"0\"/></cellStyles></styleSheet>"
        let workbook = head + "<workbook \(ns) xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Sheet1\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>"
        let rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let workbookRels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"\(rel)/worksheet\" Target=\"worksheets/sheet1.xml\"/>"
            + "<Relationship Id=\"rId2\" Type=\"\(rel)/styles\" Target=\"styles.xml\"/>"
            + "<Relationship Id=\"rId3\" Type=\"\(rel)/sharedStrings\" Target=\"sharedStrings.xml\"/></Relationships>"
        let rootRels = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"\(rel)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>"
        let types = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
            + "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/><Default Extension=\"xml\" ContentType=\"application/xml\"/>"
            + "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>"
            + "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>"
            + "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>"
            + "<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/></Types>"

        return [
            ("[Content_Types].xml", Data(types.utf8)), ("_rels/.rels", Data(rootRels.utf8)),
            ("xl/workbook.xml", Data(workbook.utf8)), ("xl/_rels/workbook.xml.rels", Data(workbookRels.utf8)),
            ("xl/worksheets/sheet1.xml", Data(sheet.utf8)), ("xl/styles.xml", Data(styles.utf8)), ("xl/sharedStrings.xml", Data(sst.utf8)),
        ]
    }

    // MARK: Writing ODS

    static func odsFiles(_ rows: [[String]]) -> [(path: String, data: Data)] {
        var body = ""
        for row in rows {
            body += "<table:table-row>"
            for value in row {
                if value.isEmpty { body += "<table:table-cell/>" }
                else if isNumber(value) { body += "<table:table-cell office:value-type=\"float\" office:value=\"\(value)\"><text:p>\(value)</text:p></table:table-cell>" }
                else {
                    let paragraphs = value.components(separatedBy: "\n").map { "<text:p>\(OfficePackage.xmlEscape($0))</text:p>" }.joined()
                    body += "<table:table-cell office:value-type=\"string\">\(paragraphs)</table:table-cell>"
                }
            }
            body += "</table:table-row>"
        }
        let content = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<office:document-content xmlns:office=\"urn:oasis:names:tc:opendocument:xmlns:office:1.0\" xmlns:table=\"urn:oasis:names:tc:opendocument:xmlns:table:1.0\" xmlns:text=\"urn:oasis:names:tc:opendocument:xmlns:text:1.0\" office:version=\"1.2\"><office:body><office:spreadsheet><table:table table:name=\"Sheet1\">\(body)</table:table></office:spreadsheet></office:body></office:document-content>"
        let manifest = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<manifest:manifest xmlns:manifest=\"urn:oasis:names:tc:opendocument:xmlns:manifest:1.0\" manifest:version=\"1.2\"><manifest:file-entry manifest:full-path=\"/\" manifest:media-type=\"application/vnd.oasis.opendocument.spreadsheet\"/><manifest:file-entry manifest:full-path=\"content.xml\" manifest:media-type=\"text/xml\"/></manifest:manifest>"
        return [("content.xml", Data(content.utf8)), ("META-INF/manifest.xml", Data(manifest.utf8))]
    }

    // MARK: HTML

    static func html(_ rows: [[String]], title: String) -> String {
        var out = "<!doctype html><html><head><meta charset=\"utf-8\"><title>\(OfficePackage.xmlEscape(title))</title><style>body{font:14px -apple-system,Helvetica,sans-serif;margin:32px}table{border-collapse:collapse}th,td{border:1px solid #d0d0d5;padding:6px 10px;text-align:left}th{background:#f3f3f6}</style></head><body><table>"
        for (i, row) in rows.enumerated() {
            let tag = i == 0 && rows.count > 1 ? "th" : "td"
            out += "<tr>" + row.map { "<\(tag)>\(OfficePackage.xmlEscape($0))</\(tag)>" }.joined() + "</tr>"
        }
        return out + "</table></body></html>"
    }
}
