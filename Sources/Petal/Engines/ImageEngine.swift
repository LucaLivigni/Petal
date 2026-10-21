import AppKit
import Foundation
import ImageIO
import CoreImage
import CoreImage.CIFilterBuiltins
import UniformTypeIdentifiers
import Vision

nonisolated struct ImageFormat: Sendable, Hashable {
    let ext: String
    let uti: String
    let name: String
    let alpha: Bool
    let lossy: Bool

    static let jpg = ImageFormat(ext: "jpg", uti: "public.jpeg", name: "JPG", alpha: false, lossy: true)
    static let png = ImageFormat(ext: "png", uti: "public.png", name: "PNG", alpha: true, lossy: false)
    static let heic = ImageFormat(ext: "heic", uti: "public.heic", name: "HEIC", alpha: true, lossy: true)
    static let tiff = ImageFormat(ext: "tiff", uti: "public.tiff", name: "TIFF", alpha: true, lossy: false)
    static let bmp = ImageFormat(ext: "bmp", uti: "com.microsoft.bmp", name: "BMP", alpha: false, lossy: false)
    static let gif = ImageFormat(ext: "gif", uti: "com.compuserve.gif", name: "GIF", alpha: true, lossy: false)
    static let webp = ImageFormat(ext: "webp", uti: "org.webmproject.webp", name: "WebP", alpha: true, lossy: true)
    static let avif = ImageFormat(ext: "avif", uti: "public.avif", name: "AVIF", alpha: true, lossy: true)

    static let jp2 = ImageFormat(ext: "jp2", uti: "public.jpeg-2000", name: "JP2", alpha: false, lossy: true)
    static let ico = ImageFormat(ext: "ico", uti: "com.microsoft.ico", name: "ICO", alpha: true, lossy: false)
    static let icns = ImageFormat(ext: "icns", uti: "com.apple.icns", name: "ICNS", alpha: true, lossy: false)
    static let tga = ImageFormat(ext: "tga", uti: "com.truevision.tga-image", name: "TGA", alpha: true, lossy: false)
    static let psd = ImageFormat(ext: "psd", uti: "com.adobe.photoshop-image", name: "PSD", alpha: true, lossy: false)

    static let all: [ImageFormat] = [.jpg, .png, .webp, .heic, .tiff, .avif, .bmp, .gif, .jp2, .ico, .icns, .tga, .psd]
    static let pdf = ImageFormat(ext: "pdf", uti: "com.adobe.pdf", name: "PDF", alpha: false, lossy: false)

    /// Format for a file extension, when it has one we can write.
    static func forExtension(_ ext: String) -> ImageFormat? {
        switch ext.lowercased() {
        case "jpg", "jpeg": .jpg
        case "png": .png
        case "heic", "heif": .heic
        case "tif", "tiff": .tiff
        case "bmp": .bmp
        case "gif": .gif
        case "webp": .webp
        case "avif": .avif
        case "jp2", "j2k": .jp2
        case "ico": .ico
        case "icns": .icns
        case "tga": .tga
        case "psd": .psd
        default: nil
        }
    }
}

nonisolated enum ImageEngine {
    static let catalogOrder: [ImageFormat] = ImageFormat.all

    private static let writable: Set<String> = {
        Set((CGImageDestinationCopyTypeIdentifiers() as? [String]) ?? [])
    }()

    // CIContext is documented as thread safe.
    static var context: CIContext { ciContext }
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func canWriteNatively(_ format: ImageFormat) -> Bool { writable.contains(format.uti) }

    // MARK: Convert

    static func convert(_ src: URL, to format: ImageFormat, ctx: JobContext) throws -> URL {
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        if format == .ico || format == .icns {
            try writeIcon(try loadOriented(src), to: dest, format: format)
            return dest
        }
        // Vector images have no frames to copy: draw them, then write the pixels.
        if isVector(src) {
            let image = try loadOriented(src)
            let flat = format.alpha ? image : image.composited(over: CIImage(color: .white).cropped(to: image.extent))
            try write(flat, to: dest, format: format, quality: ctx.imageQuality)
            return dest
        }
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil), CGImageSourceGetCount(source) > 0 else {
            throw PetalError("Can't read \(src.lastPathComponent).")
        }
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let hasAlpha = (props?[kCGImagePropertyHasAlpha] as? Bool) ?? false
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, format.uti as CFString, 1, nil) else {
            throw PetalError("\(format.name) export isn't available on this Mac.")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: ctx.imageQuality]
        if !format.alpha && hasAlpha {
            let flat = try flattenedImage(at: src)
            CGImageDestinationAddImage(out, flat, options as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(out, source, 0, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: dest)
            throw PetalError("Couldn't write \(format.name).")
        }
        return dest
    }

    /// WebP through the `cwebp` encoder (macOS can read WebP but not write it).
    static func convertToWebP(_ src: URL, ctx: JobContext) async throws -> URL {
        guard let tool = ExternalTool.cwebp else { throw PetalError("WebP needs the cwebp encoder. See Settings → Formats.") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("petal-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: temp) }
        try write(try loadOriented(src), to: temp, format: .png, quality: 1)
        let dest = ctx.policy.destination(for: src, ext: "webp")
        let result = try await ProcessRunner.run(tool, ["-quiet", "-q", "\(Int(ctx.imageQuality * 100))", "-alpha_q", "100", temp.path, "-o", dest.path])
        guard result.status == 0 else { throw PetalError("cwebp failed: \(result.error)") }
        return dest
    }

    // MARK: Vector and icons

    static func isVector(_ url: URL) -> Bool { url.pathExtension.lowercased() == "svg" }

    /// SVGs are rasterised at up to 2048 px on the long side.
    static func rasterizeVector(_ url: URL) throws -> CGImage {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            throw PetalError("Can't read \(url.lastPathComponent).")
        }
        let scale = min(8, 2048 / max(image.size.width, image.size.height))
        let width = Int((image.size.width * scale).rounded()), height = Int((image.size.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PetalError("This image is too large to draw.")
        }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.restoreGraphicsState()
        guard let cg = ctx.makeImage() else { throw PetalError("Couldn't draw \(url.lastPathComponent).") }
        return cg
    }

    /// App icons need square, standard sizes; fit the picture on a transparent square.
    private static func writeIcon(_ image: CIImage, to dest: URL, format: ImageFormat) throws {
        let longest = max(image.extent.width, image.extent.height)
        let sizes: [CGFloat] = format == .ico ? [16, 32, 48, 64, 128, 256] : [16, 32, 64, 128, 256, 512, 1024]
        let side = sizes.last { $0 <= max(longest, 16) } ?? sizes[0]
        let scale = side / longest
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offset = CGAffineTransform(translationX: (side - scaled.extent.width) / 2 - scaled.extent.minX,
                                       y: (side - scaled.extent.height) / 2 - scaled.extent.minY)
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        let placed = scaled.transformed(by: offset).composited(over: CIImage(color: .clear).cropped(to: canvas)).cropped(to: canvas)
        guard let cg = ciContext.createCGImage(placed, from: canvas, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)),
              let out = CGImageDestinationCreateWithURL(dest as CFURL, format.uti as CFString, 1, nil) else {
            throw PetalError("\(format.name) export isn't available on this Mac.")
        }
        CGImageDestinationAddImage(out, cg, nil)
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: dest)
            throw PetalError("Couldn't write \(format.name).")
        }
    }

    // MARK: Tools

    static func transform(_ src: URL, ctx: JobContext, suffix: String, _ apply: (CIImage) -> CIImage) throws -> URL {
        let image = try loadOriented(src)
        let result = apply(image)
        let format = ImageFormat.forExtension(src.pathExtension).flatMap { canWriteNatively($0) ? $0 : nil } ?? .png
        let dest = ctx.policy.destination(for: src, ext: format.ext, suffix: suffix)
        try write(result, to: dest, format: format, quality: ctx.imageQuality)
        return dest
    }

    static func resize(_ src: URL, ctx: JobContext, scale: Double? = nil, maxDimension: Double? = nil) throws -> URL {
        try transform(src, ctx: ctx, suffix: "resized") { image in
            let extent = image.extent
            var s = scale ?? 1
            if let maxDimension {
                let longest = max(extent.width, extent.height)
                s = min(1, maxDimension / longest)
            }
            guard s < 0.9999 else { return image }
            let f = CIFilter.lanczosScaleTransform()
            f.inputImage = image
            f.scale = Float(s)
            f.aspectRatio = 1
            return f.outputImage ?? image
        }
    }

    static func compress(_ src: URL, ctx: JobContext) throws -> (url: URL, outcome: String) {
        let before = ByteFormat.size(of: src)
        let ext = src.pathExtension.lowercased()
        let target = ImageFormat.forExtension(ext).flatMap { canWriteNatively($0) ? $0 : nil } ?? .jpg
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { throw PetalError("Can't read \(src.lastPathComponent).") }
        let dest = ctx.policy.destination(for: src, ext: target.ext, suffix: "compressed")
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, target.uti as CFString, 1, nil) else {
            throw PetalError("Couldn't create the compressed file.")
        }
        let options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: target.lossy ? 0.6 : 1.0]
        if target.alpha == false, (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])?[kCGImagePropertyHasAlpha] as? Bool == true {
            CGImageDestinationAddImage(out, try flattenedImage(at: src), options as CFDictionary)
        } else {
            CGImageDestinationAddImageFromSource(out, source, 0, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(out) else { throw PetalError("Couldn't compress the image.") }
        let after = ByteFormat.size(of: dest)
        if after >= before {
            try? FileManager.default.removeItem(at: dest)
            return (src, "Already as small as it gets")
        }
        return (dest, ByteFormat.savings(from: before, to: after))
    }

    static func removeBackground(_ src: URL, ctx: JobContext) throws -> URL {
        let oriented = try loadOriented(src)
        guard let cg = ciContext.createCGImage(oriented, from: oriented.extent) else { throw PetalError("Can't read the image.") }
        let handler = VNImageRequestHandler(cgImage: cg)
        let request = VNGenerateForegroundInstanceMaskRequest()
        try handler.perform([request])
        guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            throw PetalError("No subject found in this image.")
        }
        let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
        let cut = CIImage(cvPixelBuffer: buffer)
        let dest = ctx.policy.destination(for: src, ext: "png", suffix: "cutout")
        try write(cut, to: dest, format: .png, quality: 1)
        return dest
    }

    static func recognizeText(_ src: URL) throws -> String {
        let oriented = try loadOriented(src)
        guard let cg = ciContext.createCGImage(oriented, from: oriented.extent) else { throw PetalError("Can't read the image.") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { throw PetalError("No text found in this image.") }
        return lines.joined(separator: "\n")
    }

    // MARK: Helpers

    static func loadOriented(_ url: URL) throws -> CIImage {
        if isVector(url) { return CIImage(cgImage: try rasterizeVector(url)) }
        guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]) else {
            throw PetalError("Can't read \(url.lastPathComponent).")
        }
        return image
    }

    static func flattenedImage(at url: URL) throws -> CGImage {
        let image = try loadOriented(url)
        let white = CIImage(color: .white).cropped(to: image.extent)
        let flat = image.composited(over: white)
        guard let cg = ciContext.createCGImage(flat, from: flat.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else {
            throw PetalError("Couldn't flatten the image.")
        }
        return cg
    }

    static func write(_ image: CIImage, to url: URL, format: ImageFormat, quality: Double) throws {
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        guard let cg = ciContext.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: space) else {
            throw PetalError("Couldn't render the image.")
        }
        guard let out = CGImageDestinationCreateWithURL(url as CFURL, format.uti as CFString, 1, nil) else {
            throw PetalError("\(format.name) export isn't available on this Mac.")
        }
        CGImageDestinationAddImage(out, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: url)
            throw PetalError("Couldn't write \(format.name).")
        }
    }
}
