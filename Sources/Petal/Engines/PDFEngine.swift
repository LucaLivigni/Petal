import AppKit
import Foundation
import PDFKit
import CoreGraphics
import UniformTypeIdentifiers

nonisolated enum PDFEngine {
    /// Renders every page. One page gives a single file; several pages go into a folder.
    static func toImages(_ src: URL, format: ImageFormat, dpi: Double = 300, ctx: JobContext, step: (Double) -> Void) throws -> URL {
        guard let doc = CGPDFDocument(src as CFURL), doc.numberOfPages > 0 else { throw PetalError("Can't read \(src.lastPathComponent).") }
        let count = doc.numberOfPages
        let base = src.deletingPathExtension().lastPathComponent
        let single = count == 1
        let folder = single ? nil : ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: "\(base) pages", ext: "")
        if let folder { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }

        var firstOutput: URL?
        for index in 1...count {
            guard let page = doc.page(at: index) else { continue }
            let image = try render(page: page, dpi: dpi)
            let dest: URL
            if let folder {
                dest = folder.appendingPathComponent("\(base)-\(index).\(format.ext)")
            } else {
                dest = ctx.policy.destination(for: src, ext: format.ext)
            }
            guard let out = CGImageDestinationCreateWithURL(dest as CFURL, format.uti as CFString, 1, nil) else {
                throw PetalError("\(format.name) export isn't available on this Mac.")
            }
            CGImageDestinationAddImage(out, image, [kCGImageDestinationLossyCompressionQuality: ctx.imageQuality] as CFDictionary)
            guard CGImageDestinationFinalize(out) else { throw PetalError("Couldn't write page \(index).") }
            firstOutput = firstOutput ?? dest
            step(Double(index) / Double(count))
        }
        return folder ?? firstOutput!
    }

    static func render(page: CGPDFPage, dpi: Double) throws -> CGImage {
        let box = page.getBoxRect(.mediaBox)
        let rotated = page.rotationAngle % 180 != 0
        let scale = dpi / 72
        let width = Int(((rotated ? box.height : box.width) * scale).rounded())
        let height = Int(((rotated ? box.width : box.height) * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PetalError("This PDF page is too large to render.")
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let transform = page.getDrawingTransform(.mediaBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true)
        context.concatenate(transform)
        context.drawPDFPage(page)
        guard let image = context.makeImage() else { throw PetalError("Couldn't render a PDF page.") }
        return image
    }

    static func extractText(_ src: URL, ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw PetalError("Can't read \(src.lastPathComponent).") }
        guard let text = doc.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PetalError("This PDF has no selectable text.")
        }
        let dest = ctx.policy.destination(for: src, ext: "txt")
        try text.write(to: dest, atomically: true, encoding: .utf8)
        return dest
    }

    static func imagesToPDF(_ urls: [URL], ctx: JobContext) throws -> URL {
        let doc = PDFDocument()
        for url in urls {
            guard let image = NSImageLoader.load(url), let page = PDFPage(image: image) else {
                throw PetalError("Can't read \(url.lastPathComponent).")
            }
            doc.insert(page, at: doc.pageCount)
        }
        guard let first = urls.first else { throw PetalError("Nothing to convert.") }
        let dest = urls.count == 1
            ? ctx.policy.destination(for: first, ext: "pdf")
            : ctx.policy.destination(named: "Images", ext: "pdf", near: first)
        guard doc.write(to: dest) else { throw PetalError("Couldn't write the PDF.") }
        return dest
    }

    static func merge(_ urls: [URL], ctx: JobContext) throws -> URL {
        let merged = PDFDocument()
        for url in urls {
            guard let doc = PDFDocument(url: url) else { throw PetalError("Can't read \(url.lastPathComponent).") }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i) { merged.insert(page, at: merged.pageCount) }
            }
        }
        guard let first = urls.first else { throw PetalError("Nothing to merge.") }
        let dest = ctx.policy.destination(named: "Merged", ext: "pdf", near: first)
        guard merged.write(to: dest) else { throw PetalError("Couldn't write the merged PDF.") }
        return dest
    }

    static func split(_ src: URL, ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src), doc.pageCount > 0 else { throw PetalError("Can't read \(src.lastPathComponent).") }
        let base = src.deletingPathExtension().lastPathComponent
        let folder = ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: "\(base) split", ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i)?.copy() as? PDFPage else { continue }
            let part = PDFDocument()
            part.insert(page, at: 0)
            part.write(to: folder.appendingPathComponent("\(base)-\(i + 1).pdf"))
        }
        return folder
    }

    static func rotate(_ src: URL, ctx: JobContext) throws -> URL {
        guard let doc = PDFDocument(url: src) else { throw PetalError("Can't read \(src.lastPathComponent).") }
        for i in 0..<doc.pageCount { if let page = doc.page(at: i) { page.rotation = (page.rotation + 90) % 360 } }
        let dest = ctx.policy.destination(for: src, ext: "pdf", suffix: "rotated")
        guard doc.write(to: dest) else { throw PetalError("Couldn't write the PDF.") }
        return dest
    }

    static func compress(_ src: URL, ctx: JobContext) throws -> (url: URL, note: String) {
        guard let doc = PDFDocument(url: src) else { throw PetalError("Can't read \(src.lastPathComponent).") }
        let before = ByteFormat.size(of: src)
        let dest = ctx.policy.destination(for: src, ext: "pdf", suffix: "compressed")
        let options: [PDFDocumentWriteOption: Any] = [
            .saveImagesAsJPEGOption: true,
            .optimizeImagesForScreenOption: true,
        ]
        guard doc.write(to: dest, withOptions: options) else { throw PetalError("Couldn't compress the PDF.") }
        let after = ByteFormat.size(of: dest)
        if after >= before {
            try? FileManager.default.removeItem(at: dest)
            return (src, "Already as small as it gets")
        }
        return (dest, ByteFormat.savings(from: before, to: after))
    }
}

/// Small wrapper so the PDF engine can stay nonisolated while loading images.
nonisolated enum NSImageLoader {
    static func load(_ url: URL) -> NSImage? { NSImage(contentsOf: url) }
}
