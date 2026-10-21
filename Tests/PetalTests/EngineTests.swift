import Testing
import Foundation
import AppKit
import PDFKit
import AVFoundation
import ImageIO
@testable import Petal

enum Fixture {
    static func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("petal-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func context(_ inputs: [URL] = []) -> JobContext {
        JobContext(inputs: inputs, policy: OutputPolicy(folder: nil), imageQuality: 0.8, terminalBundleID: "com.apple.Terminal", progress: { _ in })
    }

    /// Writes a gradient image so compression has something to chew on.
    static func image(at url: URL, width: Int = 64, height: Int = 32, uti: String = "public.png", alpha: Bool = true) {
        let info = alpha ? CGImageAlphaInfo.premultipliedLast : CGImageAlphaInfo.noneSkipLast
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: info.rawValue)!
        for y in 0..<height {
            ctx.setFillColor(CGColor(red: CGFloat(y) / CGFloat(height), green: 0.4, blue: CGFloat((y * 7) % 255) / 255, alpha: alpha ? 0.6 : 1))
            ctx.fill(CGRect(x: 0, y: y, width: width, height: 1))
        }
        let dest = CGImageDestinationCreateWithURL(url as CFURL, uti as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        precondition(CGImageDestinationFinalize(dest))
    }

    static func pixelSize(_ url: URL) -> (Int, Int)? {
        guard let s = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any] else { return nil }
        return (p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    static func imageType(_ url: URL) -> String? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap(CGImageSourceGetType) as String?
    }
}

@Suite("Images")
struct ImageTests {
    @Test func pngToJpgFlattensAlpha() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src)
        let out = try ImageEngine.convert(src, to: .jpg, ctx: Fixture.context())
        #expect(out.lastPathComponent == "a.jpg")
        #expect(Fixture.imageType(out) == "public.jpeg")
        #expect(Fixture.pixelSize(out)! == (64, 32))
    }

    @Test func convertNeverOverwrites() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src)
        let first = try ImageEngine.convert(src, to: .jpg, ctx: Fixture.context())
        let second = try ImageEngine.convert(src, to: .jpg, ctx: Fixture.context())
        #expect(first != second)
        #expect(second.lastPathComponent == "a 2.jpg")
    }

    @Test func resizeHalf() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src, width: 200, height: 100)
        let out = try ImageEngine.resize(src, ctx: Fixture.context(), scale: 0.5)
        #expect(Fixture.pixelSize(out)! == (100, 50))
    }

    @Test func fitDoesNotUpscale() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src, width: 200, height: 100)
        let out = try ImageEngine.resize(src, ctx: Fixture.context(), maxDimension: 1920)
        #expect(Fixture.pixelSize(out)! == (200, 100))
    }

    @Test func rotateSwapsDimensions() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("a.png")
        Fixture.image(at: src, width: 80, height: 40)
        let out = try ImageEngine.transform(src, ctx: Fixture.context(), suffix: "rotated") { $0.oriented(.right) }
        #expect(Fixture.pixelSize(out)! == (40, 80))
    }

    @Test func compressShrinksJpeg() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("big.jpg")
        Fixture.image(at: src, width: 900, height: 900, uti: "public.jpeg", alpha: false)
        let result = try ImageEngine.compress(src, ctx: Fixture.context())
        #expect(result.url != src)
        #expect(ByteFormat.size(of: result.url) < ByteFormat.size(of: src))
        #expect(result.outcome.hasPrefix("Saved"))
    }
}

@Suite("PDF")
struct PDFTests {
    private func makePDF(pages: Int, in dir: URL, name: String = "doc.pdf") throws -> URL {
        var images: [URL] = []
        for i in 0..<pages {
            let url = dir.appendingPathComponent("p\(i)-\(name).png")
            Fixture.image(at: url, width: 300, height: 400)
            images.append(url)
        }
        let ctx = Fixture.context()
        let pdf = try PDFEngine.imagesToPDF(images, ctx: ctx)
        let renamed = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: renamed)
        try FileManager.default.moveItem(at: pdf, to: renamed)
        return renamed
    }

    @Test func imagesMergeIntoOnePDF() throws {
        let dir = Fixture.tempDir()
        let pdf = try makePDF(pages: 3, in: dir)
        #expect(PDFDocument(url: pdf)?.pageCount == 3)
    }

    @Test func splitMakesOneFilePerPage() throws {
        let dir = Fixture.tempDir()
        let pdf = try makePDF(pages: 3, in: dir)
        let folder = try PDFEngine.split(pdf, ctx: Fixture.context())
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".pdf") }
        #expect(files.count == 3)
    }

    @Test func mergeCombinesPages() throws {
        let dir = Fixture.tempDir()
        let a = try makePDF(pages: 2, in: dir, name: "a.pdf")
        let b = try makePDF(pages: 3, in: dir, name: "b.pdf")
        let merged = try PDFEngine.merge([a, b], ctx: Fixture.context())
        #expect(PDFDocument(url: merged)?.pageCount == 5)
    }

    @Test func renderingMultiplePagesCreatesFolder() throws {
        let dir = Fixture.tempDir()
        let pdf = try makePDF(pages: 2, in: dir)
        let out = try PDFEngine.toImages(pdf, format: .png, dpi: 72, ctx: Fixture.context(), step: { _ in })
        let files = try FileManager.default.contentsOfDirectory(atPath: out.path)
        #expect(files.sorted() == ["doc-1.png", "doc-2.png"])
        #expect(Fixture.pixelSize(out.appendingPathComponent("doc-1.png"))! == (300, 400))
    }

    @Test func renderingSinglePageGivesAFile() throws {
        let dir = Fixture.tempDir()
        let pdf = try makePDF(pages: 1, in: dir)
        let out = try PDFEngine.toImages(pdf, format: .jpg, dpi: 144, ctx: Fixture.context(), step: { _ in })
        #expect(out.pathExtension == "jpg")
        #expect(Fixture.pixelSize(out)! == (600, 800))
    }
}

@Suite("Documents and data")
struct TextTests {
    @Test func markdownToPDFRendersText() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("note.md")
        try "# Hello Petal\n\nSome **bold** text and a [link](https://example.com).\n\n- one\n- two\n".write(to: src, atomically: true, encoding: .utf8)
        let out = try await TextEngine.convert(src, to: .pdf, ctx: Fixture.context())
        let text = PDFDocument(url: out)?.string ?? ""
        #expect(text.contains("Hello Petal"))
        #expect(text.contains("bold"))
    }

    @Test func markdownToDocxAndBack() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("note.md")
        try "# Title\n\nBody text here".write(to: src, atomically: true, encoding: .utf8)
        let docx = try await TextEngine.convert(src, to: .docx, ctx: Fixture.context())
        let back = try TextEngine.load(docx)
        #expect(back.string.contains("Body text here"))
    }

    @Test func longTextPaginates() async throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("long.txt")
        try String(repeating: "Petal converts files without leaving your flow.\n", count: 400).write(to: src, atomically: true, encoding: .utf8)
        let out = try await TextEngine.convert(src, to: .pdf, ctx: Fixture.context())
        #expect((PDFDocument(url: out)?.pageCount ?? 0) > 1)
    }

    @Test func csvWithQuotesToJSON() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("t.csv")
        try "name,note,qty\nAda,\"likes, commas\",3\nBob,\"say \"\"hi\"\"\",4.5\n".write(to: src, atomically: true, encoding: .utf8)
        let out = try DataEngine.convertTable(src, toExtension: "json", ctx: Fixture.context())
        let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: out)) as! [[String: Any]]
        #expect(rows.count == 2)
        #expect(rows[0]["note"] as? String == "likes, commas")
        #expect(rows[0]["qty"] as? Int == 3)
        #expect(rows[1]["note"] as? String == "say \"hi\"")
        #expect(rows[1]["qty"] as? Double == 4.5)
    }

    @Test func jsonRoundTripsThroughCSV() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("t.json")
        try #"[{"a":1,"b":"x,y"},{"a":2,"b":"z"}]"#.write(to: src, atomically: true, encoding: .utf8)
        let csv = try DataEngine.convertTable(src, toExtension: "csv", ctx: Fixture.context())
        let text = try String(contentsOf: csv, encoding: .utf8)
        #expect(text == "a,b\n1,\"x,y\"\n2,z\n")
        let tsv = try DataEngine.convertTable(csv, toExtension: "tsv", ctx: Fixture.context())
        #expect(try String(contentsOf: tsv, encoding: .utf8) == "a\tb\n1\tx,y\n2\tz\n")
    }

    @Test func srtToVTT() throws {
        let dir = Fixture.tempDir()
        let src = dir.appendingPathComponent("s.srt")
        try "1\n00:00:01,000 --> 00:00:02,500\nHello\n\n2\n00:01:00,250 --> 00:01:03,000\nWorld\nline two\n".write(to: src, atomically: true, encoding: .utf8)
        let vtt = try DataEngine.convertSubtitles(src, toExtension: "vtt", ctx: Fixture.context())
        let text = try String(contentsOf: vtt, encoding: .utf8)
        #expect(text.hasPrefix("WEBVTT"))
        #expect(text.contains("00:00:01.000 --> 00:00:02.500"))
        #expect(text.contains("00:01:00.250 --> 00:01:03.000\nWorld\nline two"))
        let back = try DataEngine.convertSubtitles(vtt, toExtension: "srt", ctx: Fixture.context())
        #expect(try String(contentsOf: back, encoding: .utf8).contains("00:01:00,250 --> 00:01:03,000"))
    }
}

@Suite("Archives and audio")
struct MediaTests {
    @Test func zipThenExtract() async throws {
        let dir = Fixture.tempDir()
        let folder = dir.appendingPathComponent("stuff")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "hello".write(to: folder.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        let zip = try await ArchiveEngine.zipItems([folder], ctx: Fixture.context())
        #expect(zip.lastPathComponent == "stuff.zip")
        try FileManager.default.removeItem(at: folder)
        let out = try await ArchiveEngine.extract(zip, ctx: Fixture.context())
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("stuff/a.txt").path))
    }

    @Test func tarGzThenExtract() async throws {
        let dir = Fixture.tempDir()
        let file = dir.appendingPathComponent("a.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let tgz = try await ArchiveEngine.tarGz([file], ctx: Fixture.context())
        #expect(tgz.lastPathComponent == "a.tar.gz")
        let out = try await ArchiveEngine.extract(tgz, ctx: Fixture.context())
        #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent("a.txt").path))
    }

    private func makeWAV(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = sinf(Float(i) * 2 * .pi * 440 / 44_100) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    @Test(arguments: [AudioFormat.m4a, .flac, .aiff, .caf])
    func wavConvertsNatively(format: AudioFormat) async throws {
        let dir = Fixture.tempDir()
        let wav = try makeWAV(in: dir)
        let out = try await MediaEngine.convertAudio(wav, to: format, ctx: Fixture.context(), step: { _ in })
        let file = try AVAudioFile(forReading: out)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 1.0) < 0.15)
    }

    @Test func compressedAudioIsSmaller() async throws {
        let dir = Fixture.tempDir()
        let wav = try makeWAV(in: dir)
        let result = try await MediaEngine.compressAudio(wav, ctx: Fixture.context(), step: { _ in })
        #expect(result.url != wav)
        #expect(ByteFormat.size(of: result.url) < ByteFormat.size(of: wav))
    }
}

@Suite("Catalog and wheel")
struct CatalogTests {
    private func ids(_ urls: [String], _ wheel: PetalAction.Wheel) -> [String] {
        Catalog.operations(for: urls.map { URL(fileURLWithPath: "/tmp/\($0)") }, wheel: wheel).map(\.id)
    }

    @Test func imageConvertOffersOtherFormatsOnly() {
        let list = ids(["photo.jpg"], .convert)
        #expect(list.contains("convert.png"))
        #expect(list.contains("convert.pdf"))
        #expect(!list.contains("convert.jpg"))
    }

    @Test func pdfOffersImagesAndText() {
        let list = ids(["doc.pdf"], .convert)
        #expect(Set(list).isSuperset(of: ["convert.docx", "convert.md", "convert.epub", "convert.txt", "convert.pptx", "convert.xlsx",
                                          "convert.png", "convert.jpg", "convert.tiff"]))
    }

    @Test func mixedSelectionOnlyZips() {
        let list = ids(["a.jpg", "b.pdf"], .convert)
        #expect(list == ["convert.zip", "convert.tar", "convert.tar.gz"])
    }

    @Test func multipleImagesCanMergeToPDF() {
        #expect(ids(["a.png", "b.png"], .tools).contains("tools.pdf.merge"))
        #expect(!ids(["a.png"], .tools).contains("tools.pdf.merge"))
    }

    @Test func actionsAlwaysAvailable() {
        #expect(ids(["x.bin"], .actions).count == 8)
    }

    @Test func everyKindHasSomethingToDoOnEveryWheel() {
        for name in ["a.jpg", "a.mp4", "a.mp3", "a.pdf", "a.docx", "a.csv", "a.srt", "a.zip", "a.bin"] {
            for wheel in PetalAction.Wheel.allCases {
                #expect(!ids([name], wheel).isEmpty, "\(name) \(wheel)")
            }
        }
    }

    @Test func slotHitTesting() {
        #expect(WheelGeometry.slot(at: CGPoint(x: 0, y: 120), count: 8) == 0)      // straight up
        #expect(WheelGeometry.slot(at: CGPoint(x: 120, y: 0), count: 8) == 2)      // right
        #expect(WheelGeometry.slot(at: CGPoint(x: 0, y: -120), count: 8) == 4)     // down
        #expect(WheelGeometry.slot(at: CGPoint(x: -120, y: 0), count: 8) == 6)     // left
        #expect(WheelGeometry.slot(at: CGPoint(x: 5, y: 5), count: 8) == nil)      // hole
        #expect(WheelGeometry.slot(at: CGPoint(x: 0, y: 400), count: 8) == nil)    // far outside
        #expect(WheelGeometry.slot(at: CGPoint(x: 10, y: 120), count: 3) == 0)
    }

    @Test func manyOperationsPageWithMoreSlot() {
        let model = WheelModel()
        let ops = ids(["a.jpg"], .tools).count > 8
            ? Catalog.operations(for: [URL(fileURLWithPath: "/tmp/a.jpg")], wheel: .tools) : []
        model.configure(wheel: .tools, operations: ops)
        #expect(model.slots.count == 8)
        if case .more(let next) = model.slots.last! { #expect(next == 1) } else { Issue.record("last slot should be More") }
        model.page = 1
        if case .more(let next) = model.slots.last! { #expect(next == 0) } else { Issue.record("last slot should be More") }
    }

    @Test func triggerKeysStayUnique() {
        let settings = AppSettings()
        settings.convertKey = .shift; settings.toolsKey = .command; settings.actionsKey = .control
        settings.setKey(.command, for: .convert)
        #expect(settings.convertKey == .command)
        #expect(settings.toolsKey == .shift)
        #expect(settings.actionsKey == .control)
        #expect(settings.wheel(for: .command) == .convert)
        #expect(settings.wheel(for: [.command, .shift]) == nil)
        settings.convertKey = .shift; settings.toolsKey = .command
    }
}
