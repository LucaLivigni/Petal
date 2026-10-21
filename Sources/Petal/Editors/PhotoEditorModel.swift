import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

/// All the state and image maths behind the photo editor window: crop, rotate, adjust, background.
/// The maths lives in plain functions so it can be tested without any UI.
@MainActor
@Observable
final class PhotoEditorModel {
    enum Tab: String, CaseIterable, Identifiable {
        case crop = "Crop", adjust = "Adjust", background = "Background"
        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .crop: "crop"
            case .adjust: "slider.horizontal.3"
            case .background: "square.on.square.intersection.dashed"
            }
        }
    }

    nonisolated enum Aspect: String, CaseIterable, Identifiable {
        case free, original, square, fourThree, threeTwo, sixteenNine, threeFour, twoThree, nineSixteen
        var id: String { rawValue }
        var label: String {
            switch self {
            case .free: "Free"
            case .original: "Original"
            case .square: "1:1"
            case .fourThree: "4:3"
            case .threeTwo: "3:2"
            case .sixteenNine: "16:9"
            case .threeFour: "3:4"
            case .twoThree: "2:3"
            case .nineSixteen: "9:16"
            }
        }
        /// Width divided by height. `original` uses the given ratio; `free` has none.
        func ratio(original: CGFloat) -> CGFloat? {
            switch self {
            case .free: nil
            case .original: original
            case .square: 1
            case .fourThree: 4.0 / 3
            case .threeTwo: 3.0 / 2
            case .sixteenNine: 16.0 / 9
            case .threeFour: 3.0 / 4
            case .twoThree: 2.0 / 3
            case .nineSixteen: 9.0 / 16
            }
        }
    }

    nonisolated enum Fill: String, CaseIterable, Identifiable {
        case color = "Colour", gradient = "Gradient", blur = "Blur"
        var id: String { rawValue }
    }

    let source: URL
    private let preview: CIImage
    private(set) var originalSize: CGSize

    var tab: Tab
    // Geometry
    var quarterTurns = 0
    var flipH = false
    var flipV = false
    var straighten = 0.0                      // degrees, −15…15
    var aspect: Aspect = .free
    /// Normalised crop rectangle with a top-left origin, relative to the rotated picture.
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    // Adjustments
    var exposure = 0.0                        // EV, −2…2
    var contrast = 1.0                        // 0.6…1.6
    var saturation = 1.0                      // 0…2
    var warmth = 0.0                          // −1…1
    // Background
    var backgroundEnabled = false
    var canvas: Aspect = .original
    var padding = 0.08                        // fraction of the picture's long side
    var fill: Fill = .gradient
    var color1 = Color(red: 1.0, green: 0.62, blue: 0.30)
    var color2 = Color(red: 0.55, green: 0.36, blue: 0.97)
    var cornerRadius = 0.05                   // fraction of the picture's short side
    var shadow = true

    init(source: URL, tab: Tab = .crop) throws {
        self.source = source
        self.tab = tab
        // Arriving through the "Background" action means you want one.
        backgroundEnabled = (tab == .background)
        let full = try ImageEngine.loadOriented(source)
        originalSize = full.extent.size
        // Editing happens on a screen-sized copy; export re-reads the original.
        let longest = max(full.extent.width, full.extent.height)
        if longest > 1800 {
            let scaled = full.applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 1800 / longest, kCIInputAspectRatioKey: 1])
            preview = scaled.transformed(by: CGAffineTransform(translationX: -scaled.extent.minX, y: -scaled.extent.minY))
        } else {
            preview = full
        }
    }

    // MARK: Pipeline (pure functions)

    /// Rotation, flips and straightening. Straightening crops to the biggest rectangle that stays inside the tilted picture.
    nonisolated static func geometry(_ image: CIImage, quarterTurns: Int, flipH: Bool, flipV: Bool, straighten: Double) -> CIImage {
        var out = image
        if flipH { out = out.oriented(.upMirrored) }
        if flipV { out = out.oriented(.downMirrored) }
        for _ in 0..<(((quarterTurns % 4) + 4) % 4) { out = out.oriented(.right) }
        guard abs(straighten) > 0.01 else { return out }

        let w = out.extent.width, h = out.extent.height
        let radians = straighten * .pi / 180
        let center = CGPoint(x: w / 2, y: h / 2)
        let rotation = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: radians).translatedBy(x: -center.x, y: -center.y)
        let c = abs(cos(radians)), s = abs(sin(radians))
        let scale = min(w / (w * c + h * s), h / (w * s + h * c))
        let inner = CGRect(x: center.x - w * scale / 2, y: center.y - h * scale / 2, width: w * scale, height: h * scale)
        let cropped = out.transformed(by: rotation).cropped(to: inner)
        return cropped.transformed(by: CGAffineTransform(translationX: -inner.minX, y: -inner.minY))
    }

    /// `rect` is normalised with a top-left origin.
    nonisolated static func crop(_ image: CIImage, to rect: CGRect) -> CIImage {
        let w = image.extent.width, h = image.extent.height
        let pixels = CGRect(x: (rect.minX * w).rounded(), y: ((1 - rect.maxY) * h).rounded(),
                            width: max(1, (rect.width * w).rounded()), height: max(1, (rect.height * h).rounded()))
        let cropped = image.cropped(to: pixels.intersection(image.extent))
        return cropped.transformed(by: CGAffineTransform(translationX: -cropped.extent.minX, y: -cropped.extent.minY))
    }

    nonisolated static func adjust(_ image: CIImage, exposure: Double, contrast: Double, saturation: Double, warmth: Double) -> CIImage {
        var out = image
        if abs(exposure) > 0.001 {
            let f = CIFilter.exposureAdjust(); f.inputImage = out; f.ev = Float(exposure)
            out = f.outputImage ?? out
        }
        if abs(contrast - 1) > 0.001 || abs(saturation - 1) > 0.001 {
            let f = CIFilter.colorControls(); f.inputImage = out; f.contrast = Float(contrast); f.saturation = Float(saturation); f.brightness = 0
            out = f.outputImage ?? out
        }
        if abs(warmth) > 0.001 {
            let f = CIFilter.temperatureAndTint(); f.inputImage = out
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - warmth * 2800, y: 0)
            out = f.outputImage ?? out
        }
        return out
    }

    nonisolated struct BackgroundStyle {
        var canvas: Aspect, padding: Double, fill: Fill, color1: NSColor, color2: NSColor, cornerRadius: Double, shadow: Bool
    }

    /// Size of the canvas that holds a `w`×`h` picture with the given padding and aspect.
    nonisolated static func canvasSize(pictureWidth w: CGFloat, pictureHeight h: CGFloat, padding: Double, canvas: Aspect) -> CGSize {
        let pad = CGFloat(padding) * max(w, h)
        var cw = w + 2 * pad, ch = h + 2 * pad
        if let ratio = canvas.ratio(original: cw / ch) {
            if cw / ch < ratio { cw = ch * ratio } else { ch = cw / ratio }
        }
        return CGSize(width: cw.rounded(), height: ch.rounded())
    }

    nonisolated static func compose(_ image: CIImage, style: BackgroundStyle) -> CIImage {
        let w = image.extent.width, h = image.extent.height
        let size = canvasSize(pictureWidth: w, pictureHeight: h, padding: style.padding, canvas: style.canvas)
        let canvasRect = CGRect(origin: .zero, size: size)
        let photoRect = CGRect(x: ((size.width - w) / 2).rounded(), y: ((size.height - h) / 2).rounded(), width: w, height: h)
        var photo = image.transformed(by: CGAffineTransform(translationX: photoRect.minX - image.extent.minX, y: photoRect.minY - image.extent.minY))

        // Rounded corners
        let radius = CGFloat(style.cornerRadius) * min(w, h)
        var alpha: CIImage?
        if radius > 0.5 {
            let gen = CIFilter.roundedRectangleGenerator()
            gen.extent = photoRect; gen.radius = Float(radius); gen.color = .white
            if let mask = gen.outputImage?.cropped(to: canvasRect) {
                photo = photo.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask]).cropped(to: canvasRect)
                alpha = mask
            }
        }

        // Backdrop
        let backdrop: CIImage
        switch style.fill {
        case .color:
            backdrop = CIImage(color: CIColor(color: style.color1)!).cropped(to: canvasRect)
        case .gradient:
            let g = CIFilter.linearGradient()
            g.point0 = CGPoint(x: 0, y: size.height); g.point1 = CGPoint(x: size.width, y: 0)
            g.color0 = CIColor(color: style.color1)!; g.color1 = CIColor(color: style.color2)!
            backdrop = (g.outputImage ?? CIImage.empty()).cropped(to: canvasRect)
        case .blur:
            let cover = max(size.width / w, size.height / h) * 1.2
            let scaled = image.transformed(by: CGAffineTransform(scaleX: cover, y: cover))
            let centred = scaled.transformed(by: CGAffineTransform(translationX: (size.width - scaled.extent.width) / 2 - scaled.extent.minX,
                                                                   y: (size.height - scaled.extent.height) / 2 - scaled.extent.minY))
            let blurred = centred.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: max(size.width, size.height) * 0.035])
            backdrop = blurred.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.12, kCIInputBrightnessKey: -0.04]).cropped(to: canvasRect)
        }

        var result = photo.composited(over: backdrop)
        if style.shadow {
            let shape = alpha ?? CIImage(color: .white).cropped(to: photoRect)
            let black = shape.applyingFilter("CIColorMatrix", parameters: ["inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                                                                           "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.34)])
            // CIGaussianBlur's radius is a standard deviation: the visible spread is about three times it.
            let offset = black.transformed(by: CGAffineTransform(translationX: 0, y: -min(w, h) * 0.014))
            // No clamping here: the shape is only as big as the picture, so clamping would smear its edges across the canvas.
            let soft = offset.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: min(w, h) * 0.011]).cropped(to: canvasRect)
            result = photo.composited(over: soft.composited(over: backdrop))
        }
        return result.cropped(to: canvasRect)
    }

    // MARK: Using the pipeline

    private var style: BackgroundStyle {
        BackgroundStyle(canvas: canvas, padding: padding, fill: fill, color1: NSColor(color1).usingColorSpace(.sRGB) ?? .orange,
                        color2: NSColor(color2).usingColorSpace(.sRGB) ?? .purple, cornerRadius: cornerRadius, shadow: shadow)
    }

    /// The picture after rotation, flips and straightening, before cropping. The crop tool draws over this.
    var rotated: CIImage {
        Self.geometry(preview, quarterTurns: quarterTurns, flipH: flipH, flipV: flipV, straighten: straighten)
    }

    private func finish(_ base: CIImage) -> CIImage {
        var image = Self.adjust(Self.crop(Self.geometry(base, quarterTurns: quarterTurns, flipH: flipH, flipV: flipV, straighten: straighten), to: crop),
                                exposure: exposure, contrast: contrast, saturation: saturation, warmth: warmth)
        if backgroundEnabled { image = Self.compose(image, style: style) }
        return image
    }

    /// What the preview shows for the current tab.
    var displayImage: CIImage {
        if tab == .crop {
            return Self.adjust(rotated, exposure: exposure, contrast: contrast, saturation: saturation, warmth: warmth)
        }
        return finish(preview)
    }

    func renderPreview() -> NSImage? {
        let image = displayImage
        guard let cg = ImageEngine.context.createCGImage(image, from: image.extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Pixel size the saved file will have.
    var outputSize: CGSize {
        let r = rotated.extent.size
        var w = (crop.width * r.width), h = (crop.height * r.height)
        let scale = max(originalSize.width, originalSize.height) / max(preview.extent.width, preview.extent.height)
        w *= scale; h *= scale
        if backgroundEnabled { return Self.canvasSize(pictureWidth: w, pictureHeight: h, padding: padding, canvas: canvas) }
        return CGSize(width: w.rounded(), height: h.rounded())
    }

    // MARK: Crop interaction helpers

    /// Pixel aspect ratio (w/h) of the rotated picture, used to turn the crop's normalised rect into pixels.
    var rotatedRatio: CGFloat {
        let r = rotated.extent.size
        return r.width / max(r.height, 1)
    }

    /// Sets a centred crop with the requested ratio, as large as it can be.
    func applyAspect(_ newAspect: Aspect) {
        aspect = newAspect
        guard let ratio = newAspect.ratio(original: rotatedRatio) else { return }
        // In normalised units a crop of ratio r has (w·W)/(h·H) = r  →  w/h = r / rotatedRatio.
        let normalised = ratio / rotatedRatio
        var w = 1.0, h = 1.0
        if normalised >= 1 { h = 1 / normalised } else { w = normalised }
        crop = CGRect(x: (1 - w) / 2, y: (1 - h) / 2, width: w, height: h)
    }

    func rotate(by turns: Int) {
        quarterTurns = (((quarterTurns + turns) % 4) + 4) % 4
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        if aspect != .free { applyAspect(aspect) }
    }

    func resetGeometry() {
        quarterTurns = 0; flipH = false; flipV = false; straighten = 0
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        aspect = .free
    }

    func resetAdjustments() { exposure = 0; contrast = 1; saturation = 1; warmth = 0 }

    var hasEdits: Bool {
        quarterTurns != 0 || flipH || flipV || straighten != 0 || crop != CGRect(x: 0, y: 0, width: 1, height: 1)
            || exposure != 0 || contrast != 1 || saturation != 1 || warmth != 0 || backgroundEnabled
    }

    // MARK: Output

    /// Renders at full resolution and writes a copy next to the original.
    func save(policy: OutputPolicy, quality: Double) throws -> URL {
        let full = try ImageEngine.loadOriented(source)
        let image = finish(full)
        let sourceFormat = ImageFormat.forExtension(source.pathExtension).flatMap { ImageEngine.canWriteNatively($0) ? $0 : nil }
        // A rounded, shadowed picture on no backdrop would need transparency; formats without it get PNG.
        let format = sourceFormat ?? .png
        let dest = policy.destination(for: source, ext: format.ext, suffix: "edited")
        try ImageEngine.write(image, to: dest, format: format, quality: quality)
        return dest
    }

    func copyToClipboard() {
        let image = finish(preview)
        guard let cg = ImageEngine.context.createCGImage(image, from: image.extent) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))])
    }
}
