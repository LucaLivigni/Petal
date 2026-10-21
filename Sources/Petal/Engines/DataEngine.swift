import Foundation

/// CSV / TSV / JSON tables and SRT / VTT subtitles. Pure text work, no frameworks.
nonisolated enum DataEngine {
    // MARK: Tables

    static func convertTable(_ src: URL, toExtension ext: String, ctx: JobContext) throws -> URL {
        let text = try readText(src)
        let rows: [[String]]
        switch src.pathExtension.lowercased() {
        case "csv": rows = parseDelimited(text, delimiter: ",")
        case "tsv": rows = parseDelimited(text, delimiter: "\t")
        case "json": rows = try tableFromJSON(Data(text.utf8))
        default: throw PetalError("Unsupported table format.")
        }
        let output: Data
        switch ext {
        case "csv": output = Data(writeDelimited(rows, delimiter: ",").utf8)
        case "tsv": output = Data(writeDelimited(rows, delimiter: "\t").utf8)
        case "json": output = try jsonFromTable(rows)
        default: throw PetalError("Unsupported table format.")
        }
        let dest = ctx.policy.destination(for: src, ext: ext)
        try output.write(to: dest)
        return dest
    }

    /// RFC 4180 parsing with quoted fields, doubled quotes and embedded newlines.
    static func parseDelimited(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var iterator = text.makeIterator()
        var pending: Character? = iterator.next()
        while let c = pending {
            pending = iterator.next()
            if quoted {
                if c == "\"" {
                    if pending == "\"" { field.append("\""); pending = iterator.next() } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }

    static func writeDelimited(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { row in
            row.map { value in
                let needsQuotes = value.contains(delimiter) || value.contains("\"") || value.contains("\n") || value.contains("\r")
                return needsQuotes ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
            }.joined(separator: String(delimiter))
        }.joined(separator: "\n") + "\n"
    }

    static func tableFromJSON(_ data: Data) throws -> [[String]] {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let array = object as? [[String: Any]] else {
            throw PetalError("JSON must be a list of objects to become a table.")
        }
        var header: [String] = []
        for item in array { for key in item.keys.sorted() where !header.contains(key) { header.append(key) } }
        let body = array.map { item in header.map { key in stringValue(item[key]) } }
        return [header] + body
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return ""
        case let s as String: return s
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        default:
            if let v = value, JSONSerialization.isValidJSONObject(v),
               let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys]) {
                return String(decoding: d, as: UTF8.self)
            }
            return "\(value!)"
        }
    }

    static func jsonFromTable(_ rows: [[String]]) throws -> Data {
        guard let header = rows.first else { return Data("[]".utf8) }
        let objects: [[String: Any]] = rows.dropFirst().map { row in
            var object: [String: Any] = [:]
            for (i, key) in header.enumerated() where i < row.count { object[key] = inferred(row[i]) }
            return object
        }
        return try JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys])
    }

    private static func inferred(_ s: String) -> Any {
        if s == "true" { return true }
        if s == "false" { return false }
        if s.wholeMatch(of: /-?(0|[1-9]\d*)/) != nil, let i = Int(s) { return i }
        if s.wholeMatch(of: /-?(0|[1-9]\d*)\.\d+/) != nil, let d = Double(s) { return d }
        return s
    }

    // MARK: Subtitles

    struct Cue: Sendable { var start: Int; var end: Int; var text: String }

    static func convertSubtitles(_ src: URL, toExtension ext: String, ctx: JobContext) throws -> URL {
        let cues = parseCues(try readText(src))
        guard !cues.isEmpty else { throw PetalError("No subtitles found in \(src.lastPathComponent).") }
        let output: String
        switch ext {
        case "srt":
            output = cues.enumerated().map { i, c in "\(i + 1)\n\(timestamp(c.start, comma: true)) --> \(timestamp(c.end, comma: true))\n\(c.text)\n" }.joined(separator: "\n")
        case "vtt":
            output = "WEBVTT\n\n" + cues.map { c in "\(timestamp(c.start, comma: false)) --> \(timestamp(c.end, comma: false))\n\(c.text)\n" }.joined(separator: "\n")
        case "txt":
            output = cues.map(\.text).joined(separator: "\n") + "\n"
        default:
            throw PetalError("Unsupported subtitle format.")
        }
        let dest = ctx.policy.destination(for: src, ext: ext)
        try output.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    static func parseCues(_ text: String) -> [Cue] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\u{FEFF}", with: "")
        var cues: [Cue] = []
        for block in normalized.components(separatedBy: "\n\n") {
            let lines = block.components(separatedBy: "\n").filter { !$0.isEmpty }
            guard let timeIndex = lines.firstIndex(where: { $0.contains("-->") }) else { continue }
            let parts = lines[timeIndex].components(separatedBy: "-->")
            guard parts.count == 2, let start = milliseconds(parts[0]), let end = milliseconds(parts[1]) else { continue }
            let body = lines[(timeIndex + 1)...].joined(separator: "\n")
            cues.append(Cue(start: start, end: end, text: body))
        }
        return cues
    }

    private static func milliseconds(_ raw: String) -> Int? {
        let s = raw.trimmingCharacters(in: .whitespaces).split(separator: " ").first.map(String.init) ?? ""
        guard let m = s.firstMatch(of: /^(?:(\d+):)?(\d{1,2}):(\d{2})[,.](\d{1,3})$/) else { return nil }
        let h = m.1.flatMap { Int($0) } ?? 0
        let min = Int(m.2)!, sec = Int(m.3)!
        let ms = Int(String(m.4).padding(toLength: 3, withPad: "0", startingAt: 0))!
        return ((h * 60 + min) * 60 + sec) * 1000 + ms
    }

    private static func timestamp(_ ms: Int, comma: Bool) -> String {
        let h = ms / 3_600_000, m = ms / 60_000 % 60, s = ms / 1000 % 60, f = ms % 1000
        return String(format: "%02d:%02d:%02d%@%03d", h, m, s, comma ? "," : ".", f)
    }

    // MARK: Reading

    static func readText(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        for encoding in [String.Encoding.utf8, .utf16, .windowsCP1252, .macOSRoman] {
            if let s = String(data: data, encoding: encoding) { return s }
        }
        throw PetalError("Can't read \(url.lastPathComponent).")
    }
}
