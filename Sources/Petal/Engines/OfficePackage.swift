import Foundation

/// Builds and reads the zip containers behind DOCX, XLSX, PPTX, ODS and EPUB.
nonisolated enum OfficePackage {
    /// Writes `files` (relative path → data) into a zip at `url`.
    /// When `mimetype` is given it becomes the first entry, stored uncompressed (required by EPUB and ODS).
    static func write(_ files: [(path: String, data: Data)], to url: URL, mimetype: String? = nil) async throws {
        let fm = FileManager.default
        let stage = fm.temporaryDirectory.appendingPathComponent("petal-pkg-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: stage) }

        var topLevel: [String] = []
        for file in files {
            let target = stage.appendingPathComponent(file.path)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.data.write(to: target)
            let first = file.path.split(separator: "/").first.map(String.init) ?? file.path
            if !topLevel.contains(first) { topLevel.append(first) }
        }

        let zip = URL(fileURLWithPath: "/usr/bin/zip")
        let temp = stage.appendingPathComponent("..package-\(UUID().uuidString).zip")
        if let mimetype {
            try Data(mimetype.utf8).write(to: stage.appendingPathComponent("mimetype"))
            let first = try await ProcessRunner.run(zip, ["-X0", "-q", "-nw", temp.path, "mimetype"], currentDirectory: stage)
            guard first.status == 0 else { throw PetalError("Couldn't create the package: \(first.error)") }
        }
        // Names are passed literally (-nw) because paths like "[Content_Types].xml" contain wildcard characters.
        let rest = try await ProcessRunner.run(zip, ["-X", "-q", "-nw", "-r", temp.path] + topLevel, currentDirectory: stage)
        guard rest.status == 0 else { throw PetalError("Couldn't create the package: \(rest.error)") }

        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.moveItem(at: temp, to: url)
    }

    /// Unpacks a zip into a fresh temporary folder. The caller removes it.
    static func unpack(_ url: URL) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("petal-unpack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/ditto"), ["-x", "-k", url.path, folder.path])
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: folder)
            throw PetalError("Can't open \(url.lastPathComponent).")
        }
        return folder
    }

    static func xmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for scalar in s.unicodeScalars {
            switch scalar {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // XML 1.0 forbids most control characters.
                if scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" || scalar == "\r" { out.unicodeScalars.append(scalar) }
            }
        }
        return out
    }
}

/// Minimal "collect the text of elements" XML reader used by the XLSX / ODS / EPUB parsers.
nonisolated final class XMLCollector: NSObject, XMLParserDelegate {
    struct Event { var name: String; var attributes: [String: String]; var isStart: Bool; var text: String }

    private(set) var events: [Event] = []
    private var text = ""

    static func parse(_ data: Data) -> [Event] {
        let collector = XMLCollector()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = collector
        parser.parse()
        return collector.events
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
        text = ""
        events.append(Event(name: name, attributes: attributes, isStart: true, text: ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        events.append(Event(name: name, attributes: [:], isStart: false, text: text))
        text = ""
    }
}
