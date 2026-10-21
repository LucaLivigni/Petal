import Testing
import Foundation
import AppKit
import PDFKit
import AVFoundation
import ImageIO
@testable import Petal

/// A PDF with a heading and flowing paragraphs, made the same way Petal makes PDFs from documents.
@MainActor
func makeTextPDF(in dir: URL, name: String = "report.pdf") throws -> URL {
    let md = """
    # Quarterly Report

    Revenue grew steadily across all regions during the quarter, driven mostly by new customers in Europe.

    ## Highlights

    - Launch of the new product line
    - Expansion into two markets
    """
    let src = dir.appendingPathComponent("report.md")
    try md.write(to: src, atomically: true, encoding: .utf8)
    let text = try TextEngine.load(src)
    let url = dir.appendingPathComponent(name)
    try TextEngine.renderPDF(text, to: url)
    return url
}

@Suite("Spreadsheets")
struct SpreadsheetTests {
    static let rows = [["name", "note", "qty"], ["Ada", "likes, commas", "3"], ["Bob", "say \"hi\"\nnew line", "4.5"], ["Zoë", "ünïcode ✓", "007"]]

    @Test func xlsxRoundTrip() async throws {
        let dir = Fixture.tempDir()
        let xlsx = dir.appendingPathComponent("t.xlsx")
        try await SpreadsheetEngine.write(Self.rows, toExtension: "xlsx", at: xlsx, title: "t")
        let back = try await SpreadsheetEngine.readRows(xlsx)
        #expect(back == Self.rows)
    }

    @Test func odsRoundTrip() async throws {
        let dir = Fixture.tempDir()
        let ods = dir.appendingPathComponent("t.ods")
        try await SpreadsheetEngine.write(Self.rows, toExtension: "ods", at: ods, title: "t")
        let back = try await SpreadsheetEngine.readRows(ods)
        #expect(back == Self.rows)
    }

    @Test func odsIsAValidPackage() async throws {
        let dir = Fixture.tempDir()
        let ods = dir.appendingPathComponent("t.ods")
        try await SpreadsheetEngine.write(Self.rows, toExtension: "ods", at: ods, title: "t")
        // The first entry must be an uncompressed "mimetype".
        let list = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-v", ods.path])
        let firstEntry = list.output.split(separator: "\n").first { $0.contains("mimetype") || $0.contains("content.xml") }
        #expect(firstEntry?.contains("mimetype") == true)
        #expect(firstEntry?.contains("Stored") == true)
    }

    @Test func csvToXLSXAndBackThroughTheCatalogPath() async throws {
        let dir = Fixture.tempDir()
        let csv = dir.appendingPathComponent("data.csv")
        try DataEngine.writeDelimited(Self.rows, delimiter: ",").write(to: csv, atomically: true, encoding: .utf8)
        let xlsx = try await SpreadsheetEngine.convert(csv, toExtension: "xlsx", ctx: Fixture.context())
        let tsv = try await SpreadsheetEngine.convert(xlsx, toExtension: "tsv", ctx: Fixture.context())
        #expect(try await SpreadsheetEngine.readRows(tsv) == Self.rows)
    }

    @Test func tableToPDFAndHTML() async throws {
        let dir = Fixture.tempDir()
        let big = [["id", "value"]] + (1...120).map { ["\($0)", "row \($0)"] }
        let pdf = dir.appendingPathComponent("t.pdf")
        try await SpreadsheetEngine.write(big, toExtension: "pdf", at: pdf, title: "t")
        let doc = PDFDocument(url: pdf)
        #expect((doc?.pageCount ?? 0) >= 3)
        #expect(doc?.string?.contains("row 120") == true)
        let html = dir.appendingPathComponent("t.html")
        try await SpreadsheetEngine.write(Self.rows, toExtension: "html", at: html, title: "t")
        let text = try String(contentsOf: html, encoding: .utf8)
        #expect(text.contains("<th>name</th>"))
        #expect(text.contains("likes, commas"))
    }
}

@Suite("Documents")
struct DocumentFormatTests {
    @Test @MainActor func markdownWriterKeepsStructure() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("n.md")
        try "# Title\n\nSome **bold** and *italic* text with a [link](https://example.com).\n\n## Section\n\n- one\n- two\n\n1. first\n2. second\n".write(to: src, atomically: true, encoding: .utf8)
        let md = MarkdownWriter.markdown(from: try TextEngine.load(src))
        #expect(md.contains("# Title"))
        #expect(md.contains("## Section") || md.contains("### Section"))
        #expect(md.contains("**bold**"))
        #expect(md.contains("*italic*"))
        #expect(md.contains("[link](https://example.com"))
        #expect(md.contains("- one"))
        #expect(md.contains("1. first"))
    }

    @Test @MainActor func reflowJoinsWrappedLinesAndHyphenation() {
        let font = NSFont.systemFont(ofSize: 11)
        let text = NSAttributedString(string: "This is a long sentence that was wrapped by\nthe PDF layout and continues with inter-\nnational words.\n\nNew paragraph here.", attributes: [.font: font])
        let out = MarkdownWriter.reflow(text).string
        #expect(out.contains("wrapped by the PDF layout"))
        #expect(out.contains("international words."))
        #expect(out.contains("\n\nNew paragraph"))
    }

    @Test @MainActor func epubWriteAndReadBack() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("book.md")
        try "# One\n\nFirst chapter text.\n\n# Two\n\nSecond chapter text.\n".write(to: src, atomically: true, encoding: .utf8)
        let epub = try await TextEngine.convert(src, to: .epub, ctx: Fixture.context())
        let list = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-v", epub.path])
        #expect(list.output.contains("mimetype"))
        #expect(list.output.contains("chapter2.xhtml"))
        let back = try await TextEngine.loadAsync(epub).string
        #expect(back.contains("First chapter text."))
        #expect(back.contains("Second chapter text."))
    }

    @Test @MainActor func epubToDocxAndPDF() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("book.md")
        try "# One\n\nHello from the e-book.\n".write(to: src, atomically: true, encoding: .utf8)
        let epub = try await TextEngine.convert(src, to: .epub, ctx: Fixture.context())
        let pdf = try await TextEngine.convert(epub, to: .pdf, ctx: Fixture.context())
        #expect(PDFDocument(url: pdf)?.string?.contains("Hello from the e-book.") == true)
    }

    @Test @MainActor func everyDocumentFormatWrites() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("doc.md")
        try "# Heading\n\nBody paragraph.\n".write(to: src, atomically: true, encoding: .utf8)
        for format in DocFormat.all where format != .pages {
            let out = try await TextEngine.convert(src, to: format, ctx: Fixture.context())
            #expect(ByteFormat.size(of: out) > 0, "\(format.name) produced an empty file")
        }
    }
}

@Suite("PDF to office formats")
struct PDFExportTests {
    @Test @MainActor func pdfToDocx() async throws {
        let dir = Fixture.tempDir()
        let pdf = try makeTextPDF(in: dir)
        let docx = try await PDFExport.toDocument(pdf, format: .docx, ctx: Fixture.context())
        let text = try TextEngine.load(docx).string
        #expect(text.contains("Quarterly Report"))
        #expect(text.contains("Revenue grew steadily across all regions"))
        // The two bullet points must stay on separate lines.
        let items = text.components(separatedBy: "\n").filter { $0.contains("new product line") || $0.contains("two markets") }
        #expect(items.count == 2)
    }

    @Test @MainActor func pdfToMarkdownFindsHeadings() async throws {
        let dir = Fixture.tempDir()
        let pdf = try makeTextPDF(in: dir)
        let md = try await PDFExport.toDocument(pdf, format: .md, ctx: Fixture.context())
        let text = try String(contentsOf: md, encoding: .utf8)
        #expect(text.contains("# Quarterly Report"))
        #expect(text.contains("Revenue grew steadily across all regions"))
        #expect(text.contains("- Launch of the new product line"))
    }

    @Test @MainActor func pdfToEPUB() async throws {
        let dir = Fixture.tempDir()
        let pdf = try makeTextPDF(in: dir)
        let epub = try await PDFExport.toDocument(pdf, format: .epub, ctx: Fixture.context())
        #expect(try await TextEngine.loadAsync(epub).string.contains("Quarterly Report"))
    }

    @Test @MainActor func pdfToPPTXHasOneSlidePerPage() async throws {
        let dir = Fixture.tempDir()
        var images: [URL] = []
        for i in 0..<3 { let u = dir.appendingPathComponent("p\(i).png"); Fixture.image(at: u, width: 400, height: 300); images.append(u) }
        let pdf = try PDFEngine.imagesToPDF(images, ctx: Fixture.context())
        let pptx = try await PDFExport.toPPTX(pdf, ctx: Fixture.context(), step: { _ in })
        let list = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-l", pptx.path])
        for n in 1...3 { #expect(list.output.contains("ppt/slides/slide\(n).xml")) }
        #expect(!list.output.contains("slide4.xml"))
        #expect(list.output.contains("ppt/media/image3.jpeg"))
    }

    @Test @MainActor func pdfToXLSXSplitsColumns() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("table.txt")
        try "Item        Qty     Price\nApple       3       1.20\nPear        5       2.40\n".write(to: src, atomically: true, encoding: .utf8)
        let pdf = try await TextEngine.convert(src, to: .pdf, ctx: Fixture.context())
        let xlsx = try await PDFExport.toXLSX(pdf, ctx: Fixture.context())
        let rows = try await SpreadsheetEngine.readRows(xlsx)
        #expect(rows.first == ["Item", "Qty", "Price"])
        #expect(rows.contains(["Apple", "3", "1.20"]), "\(rows)")
    }
}

@Suite("Archives, images, video")
struct MoreFormatTests {
    @Test func zipToTarGzAndTar() async throws {
        let dir = Fixture.tempDir()
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hello".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = try await ArchiveEngine.zipItems([folder], ctx: Fixture.context())
        let tgz = try await ArchiveEngine.convert(zip, to: .tarGz, ctx: Fixture.context())
        #expect(tgz.lastPathComponent == "stuff.tar.gz")
        let tar = try await ArchiveEngine.convert(tgz, to: .tar, ctx: Fixture.context())
        #expect(tar.lastPathComponent == "stuff.tar")
        let out = try await ArchiveEngine.extract(tar, ctx: Fixture.context())
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("stuff/a.txt").path))
    }

    @Test func gzipRoundTrip() async throws {
        let dir = Fixture.tempDir()
        let file = dir.appendingPathComponent("notes.txt")
        try String(repeating: "petal ", count: 500).write(to: file, atomically: true, encoding: .utf8)
        let gz = try await ArchiveEngine.gzip(file, ctx: Fixture.context())
        #expect(gz.lastPathComponent == "notes.txt.gz")
        #expect(ByteFormat.size(of: gz) < ByteFormat.size(of: file))
        try FileManager.default.removeItem(at: file)
        let back = try await ArchiveEngine.extract(gz, ctx: Fixture.context())
        #expect(back.lastPathComponent == "notes.txt")
        #expect(try String(contentsOf: back, encoding: .utf8).hasPrefix("petal petal"))
    }

    @Test func svgConvertsToPNGAndJPG() throws {
        let dir = Fixture.tempDir()
        let svg = dir.appendingPathComponent("logo.svg")
        try """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80" viewBox="0 0 120 80"><rect width="120" height="80" fill="#ff8a1f"/><circle cx="60" cy="40" r="25" fill="white"/></svg>
        """.write(to: svg, atomically: true, encoding: .utf8)
        let png = try ImageEngine.convert(svg, to: .png, ctx: Fixture.context())
        let size = Fixture.pixelSize(png)!
        #expect(size.0 > 0 && Double(size.0) / Double(size.1) > 1.4 && Double(size.0) / Double(size.1) < 1.6)
        let jpg = try ImageEngine.convert(svg, to: .jpg, ctx: Fixture.context())
        #expect(Fixture.imageType(jpg) == "public.jpeg")
    }

    @Test(arguments: [ImageFormat.ico, .icns, .jp2, .tga, .psd, .tiff, .gif, .bmp, .heic])
    func imageFormatsWrite(format: ImageFormat) throws {
        guard ImageEngine.canWriteNatively(format) else { return }
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src, width: 300, height: 200)
        let out = try ImageEngine.convert(src, to: format, ctx: Fixture.context())
        #expect(ByteFormat.size(of: out) > 0)
        #expect(Fixture.imageType(out) == format.uti || format == .tga || format == .heic)
    }

    /// A short solid-colour clip, made with AVAssetWriter.
    private func makeVideo(in dir: URL, seconds: Int = 2) async throws -> URL {
        let url = dir.appendingPathComponent("clip.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 10) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, nil, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 8 % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func videoToGIF() async throws {
        let dir = Fixture.tempDir()
        let video = try await makeVideo(in: dir)
        let gif = try await MediaEngine.videoToGIF(video, ctx: Fixture.context(), step: { _ in })
        let source = CGImageSourceCreateWithURL(gif as CFURL, nil)!
        #expect(CGImageSourceGetCount(source) >= 20)
        #expect(Fixture.imageType(gif) == "com.compuserve.gif")
    }

    @Test func muteKeepsVideoDropsAudio() async throws {
        let dir = Fixture.tempDir()
        let video = try await makeVideo(in: dir)
        let out = try await MediaEngine.mute(video, ctx: Fixture.context(), step: { _ in })
        let asset = AVURLAsset(url: out)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    }

    @Test func videoCatalogOffersGifAndAudioExtraction() {
        let list = Catalog.operations(for: [URL(fileURLWithPath: "/tmp/a.mp4")], wheel: .convert).map(\.id)
        #expect(list.contains("convert.mov"))
        #expect(list.contains("convert.gif"))
        #expect(list.contains("convert.audio.m4a"))
        #expect(!list.contains("convert.mp4"))
    }

    @Test func catalogCoversNewKinds() {
        func ids(_ n: String, _ w: PetalAction.Wheel = .convert) -> [String] {
            Catalog.operations(for: [URL(fileURLWithPath: "/tmp/\(n)")], wheel: w).map(\.id)
        }
        #expect(Set(ids("deck.pptx")) == ["convert.pdf", "convert.jpg", "convert.png"])
        #expect(Set(ids("sheet.xlsx")).isSuperset(of: ["convert.csv", "convert.ods", "convert.pdf", "convert.json"]))
        #expect(!ids("sheet.xlsx").contains("convert.xlsx"))
        #expect(ids("book.epub").contains("convert.pdf") && ids("book.epub").contains("convert.md"))
        #expect(ids("a.zip").contains("convert.tar.gz") && !ids("a.zip").contains("convert.zip") && ids("a.zip").contains("convert.extract"))
        #expect(ids("vector.svg").contains("convert.png") && ids("vector.svg").contains("convert.icns"))
        #expect(ids("raw.cr2").contains("convert.jpg"))
    }
}

/// Writes one sample of every office format to $PETAL_SAMPLES_DIR so they can be opened in real apps.
@Suite("Samples")
struct SampleExport {
    @Test @MainActor func writeSamples() async throws {
        guard let path = ProcessInfo.processInfo.environment["PETAL_SAMPLES_DIR"] else { return }
        let dir = URL(fileURLWithPath: path, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = JobContext(inputs: [], policy: OutputPolicy(folder: dir), imageQuality: 0.8, terminalBundleID: "", progress: { _ in })
        let pdf = try makeTextPDF(in: dir)
        _ = try await PDFExport.toDocument(pdf, format: .docx, ctx: ctx)
        _ = try await PDFExport.toDocument(pdf, format: .epub, ctx: ctx)
        _ = try await PDFExport.toPPTX(pdf, ctx: ctx, step: { _ in })
        _ = try await PDFExport.toXLSX(pdf, ctx: ctx)
        let csv = dir.appendingPathComponent("people.csv")
        try DataEngine.writeDelimited(SpreadsheetTests.rows, delimiter: ",").write(to: csv, atomically: true, encoding: .utf8)
        for ext in ["xlsx", "ods", "pdf"] { _ = try await SpreadsheetEngine.convert(csv, toExtension: ext, ctx: ctx) }

        // A short clip to open in the trim window.
        if ProcessInfo.processInfo.environment["PETAL_SAMPLE_CLIP"] != nil {
            let url = dir.appendingPathComponent("clip.mp4")
            try? FileManager.default.removeItem(at: url)
            let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 640, AVVideoHeightKey: 360])
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 640, kCVPixelBufferHeightKey as String: 360])
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            for frame in 0..<150 {
                while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
                var buffer: CVPixelBuffer?
                CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_32BGRA, nil, &buffer)
                CVPixelBufferLockBaseAddress(buffer!, [])
                let base = CVPixelBufferGetBaseAddress(buffer!)!.assumingMemoryBound(to: UInt8.self)
                let row = CVPixelBufferGetBytesPerRow(buffer!)
                for y in 0..<360 { for x in 0..<640 {
                    let p = base + y * row + x * 4
                    p[0] = UInt8((x * 255 / 640 + frame * 3) % 256); p[1] = UInt8(y * 255 / 360); p[2] = UInt8((frame * 6) % 256); p[3] = 255
                } }
                CVPixelBufferUnlockBaseAddress(buffer!, [])
                adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30))
            }
            input.markAsFinished()
            await writer.finishWriting()
        }

        // Photo editor output, to look at.
        if let sunset = ProcessInfo.processInfo.environment["PETAL_SAMPLE_PHOTO"] {
            for (name, fill) in [("gradient", PhotoEditorModel.Fill.gradient), ("blur", .blur), ("colour", .color)] {
                let copy = dir.appendingPathComponent("editor-\(name).png")
                try? FileManager.default.removeItem(at: copy)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: sunset), to: copy)
                let model = try PhotoEditorModel(source: copy, tab: .background)
                model.fill = fill
                model.padding = 0.1
                _ = try model.save(policy: ctx.policy, quality: 0.9)
            }
        }
    }
}
