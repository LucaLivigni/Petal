import Testing
import Foundation
import AppKit
import CoreImage
import ImageIO
@testable import Petal

private func pixel(_ image: CIImage, x: Int, y: Int) -> (r: Double, g: Double, b: Double, a: Double) {
    var bytes = [UInt8](repeating: 0, count: 4)
    let rect = CGRect(x: image.extent.minX + CGFloat(x), y: image.extent.minY + CGFloat(y), width: 1, height: 1)
    ImageEngine.context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: rect, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    return (Double(bytes[0]) / 255, Double(bytes[1]) / 255, Double(bytes[2]) / 255, Double(bytes[3]) / 255)
}

/// 400×300 picture: top-left quadrant red, bottom-right blue, the rest mid-grey. (CIImage y grows upwards.)
private func quadrants() -> CIImage {
    let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 0, y: 0, width: 400, height: 300))
    let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 150, width: 200, height: 150))
    let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(x: 200, y: 0, width: 200, height: 150))
    return blue.composited(over: red.composited(over: grey))
}

@Suite("Photo editor maths")
struct PhotoEditorMathTests {
    @Test func quarterTurnsSwapDimensionsAndFlipsDoNot() {
        let g = quadrants()
        #expect(PhotoEditorModel.geometry(g, quarterTurns: 1, flipH: false, flipV: false, straighten: 0).extent.size == CGSize(width: 300, height: 400))
        #expect(PhotoEditorModel.geometry(g, quarterTurns: 2, flipH: false, flipV: false, straighten: 0).extent.size == CGSize(width: 400, height: 300))
        #expect(PhotoEditorModel.geometry(g, quarterTurns: 0, flipH: true, flipV: true, straighten: 0).extent.size == CGSize(width: 400, height: 300))
        #expect(PhotoEditorModel.geometry(g, quarterTurns: 4, flipH: false, flipV: false, straighten: 0).extent.size == CGSize(width: 400, height: 300))
    }

    @Test func flipHorizontalMovesTheRedQuadrantToTheRight() {
        let flipped = PhotoEditorModel.geometry(quadrants(), quarterTurns: 0, flipH: true, flipV: false, straighten: 0)
        #expect(pixel(flipped, x: 350, y: 250).r > 0.9)       // top-right is red now
        #expect(pixel(flipped, x: 50, y: 250).r < 0.6)
    }

    @Test func rotatingClockwiseMovesTopLeftToTopRight() {
        let turned = PhotoEditorModel.geometry(quadrants(), quarterTurns: 1, flipH: false, flipV: false, straighten: 0)
        #expect(pixel(turned, x: 250, y: 350).r > 0.9)
    }

    @Test func straighteningCropsToTheLargestInscribedRectangleWithTheSameShape() {
        let out = PhotoEditorModel.geometry(quadrants(), quarterTurns: 0, flipH: false, flipV: false, straighten: 10)
        #expect(out.extent.width < 400 && out.extent.height < 300)
        #expect(abs(out.extent.width / out.extent.height - 4.0 / 3) < 0.02)
        #expect(out.extent.origin == .zero)
        // Every pixel must be picture, never transparent corner.
        for (x, y) in [(1, 1), (Int(out.extent.width) - 2, 1), (1, Int(out.extent.height) - 2), (Int(out.extent.width) - 2, Int(out.extent.height) - 2)] {
            #expect(pixel(out, x: x, y: y).a > 0.99)
        }
    }

    @Test func cropUsesATopLeftOrigin() {
        let topLeft = PhotoEditorModel.crop(quadrants(), to: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
        #expect(topLeft.extent.size == CGSize(width: 200, height: 150))
        #expect(pixel(topLeft, x: 100, y: 75).r > 0.9)
        let bottomRight = PhotoEditorModel.crop(quadrants(), to: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        #expect(pixel(bottomRight, x: 100, y: 75).b > 0.9)
        #expect(bottomRight.extent.origin == .zero)
    }

    @Test func adjustmentsDoWhatTheirSlidersSay() {
        let grey = CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let base = pixel(grey, x: 1, y: 1).r
        #expect(pixel(PhotoEditorModel.adjust(grey, exposure: 1, contrast: 1, saturation: 1, warmth: 0), x: 1, y: 1).r > base + 0.1)
        #expect(pixel(PhotoEditorModel.adjust(grey, exposure: -1, contrast: 1, saturation: 1, warmth: 0), x: 1, y: 1).r < base - 0.05)

        let orange = CIImage(color: CIColor(red: 1, green: 0.5, blue: 0.1)).cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let mono = pixel(PhotoEditorModel.adjust(orange, exposure: 0, contrast: 1, saturation: 0, warmth: 0), x: 1, y: 1)
        #expect(abs(mono.r - mono.g) < 0.02 && abs(mono.g - mono.b) < 0.02)

        let warmer = pixel(PhotoEditorModel.adjust(grey, exposure: 0, contrast: 1, saturation: 1, warmth: 1), x: 1, y: 1)
        let cooler = pixel(PhotoEditorModel.adjust(grey, exposure: 0, contrast: 1, saturation: 1, warmth: -1), x: 1, y: 1)
        #expect(warmer.r - warmer.b > cooler.r - cooler.b + 0.05, "positive warmth must add red and remove blue")
    }

    @Test func canvasSizesFollowPaddingAndAspect() {
        #expect(PhotoEditorModel.canvasSize(pictureWidth: 400, pictureHeight: 300, padding: 0, canvas: .original) == CGSize(width: 400, height: 300))
        #expect(PhotoEditorModel.canvasSize(pictureWidth: 400, pictureHeight: 300, padding: 0.1, canvas: .original) == CGSize(width: 480, height: 380))
        let square = PhotoEditorModel.canvasSize(pictureWidth: 400, pictureHeight: 300, padding: 0.1, canvas: .square)
        #expect(square.width == square.height && square.width >= 480)
        let wide = PhotoEditorModel.canvasSize(pictureWidth: 300, pictureHeight: 400, padding: 0.05, canvas: .sixteenNine)
        #expect(abs(wide.width / wide.height - 16.0 / 9) < 0.01)
        #expect(wide.height >= 440)
    }

    @Test func backgroundPutsThePictureInTheMiddleOnAnOpaqueBackdrop() {
        let picture = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 200, height: 100))
        let style = PhotoEditorModel.BackgroundStyle(canvas: .square, padding: 0.1, fill: .color, color1: NSColor(srgbRed: 0, green: 0.8, blue: 0, alpha: 1),
                                                     color2: .black, cornerRadius: 0.2, shadow: false)
        let out = PhotoEditorModel.compose(picture, style: style)
        #expect(out.extent.width == out.extent.height)
        let mid = Int(out.extent.width / 2)
        #expect(pixel(out, x: mid, y: mid).r > 0.9)                       // picture in the centre
        #expect(pixel(out, x: 2, y: 2).g > 0.7 && pixel(out, x: 2, y: 2).a > 0.99)   // backdrop in the corner
        // Rounded corners: the very corner of the picture shows the backdrop, not red.
        let photoLeft = Int((out.extent.width - 200) / 2), photoBottom = Int((out.extent.height - 100) / 2)
        #expect(pixel(out, x: photoLeft + 1, y: photoBottom + 1).r < 0.5)
    }

    @Test func theShadowStaysNextToThePictureAndNeverDarkensTheRestOfTheBackdrop() {
        let picture = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 200))
        func render(shadow: Bool) -> CIImage {
            PhotoEditorModel.compose(picture, style: .init(canvas: .original, padding: 0.3, fill: .color, color1: NSColor(srgbRed: 0.9, green: 0.9, blue: 0.2, alpha: 1),
                                                           color2: .black, cornerRadius: 0.1, shadow: shadow))
        }
        let with = render(shadow: true), without = render(shadow: false)
        let midY = Int(with.extent.height / 2), midX = Int(with.extent.width / 2)
        // Far from the picture (left edge, top edge) the two renders must match.
        for (x, y) in [(3, midY), (midX, Int(with.extent.height) - 3), (Int(with.extent.width) - 3, midY), (midX, 3)] {
            let a = pixel(with, x: x, y: y), b = pixel(without, x: x, y: y)
            #expect(abs(a.r - b.r) < 0.02 && abs(a.g - b.g) < 0.02 && abs(a.b - b.b) < 0.02, "shadow reached \(x),\(y)")
        }
        // Right below the picture there is a visible shadow.
        let photoBottom = Int((with.extent.height - 200) / 2)
        let below = pixel(with, x: midX, y: photoBottom - 3), plain = pixel(without, x: midX, y: photoBottom - 3)
        #expect(below.g < plain.g - 0.02)
    }

    @Test func gradientAndBlurBackdropsFillTheWholeCanvas() {
        let picture = CIImage(color: CIColor(red: 0.2, green: 0.3, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 300, height: 200))
        for fill in [PhotoEditorModel.Fill.gradient, .blur] {
            let style = PhotoEditorModel.BackgroundStyle(canvas: .sixteenNine, padding: 0.2, fill: fill, color1: .orange, color2: .purple, cornerRadius: 0.05, shadow: true)
            let out = PhotoEditorModel.compose(picture, style: style)
            for (x, y) in [(1, 1), (Int(out.extent.width) - 2, 1), (1, Int(out.extent.height) - 2), (Int(out.extent.width) - 2, Int(out.extent.height) - 2)] {
                #expect(pixel(out, x: x, y: y).a > 0.99, "\(fill) left a hole at \(x),\(y)")
            }
        }
    }
}

@Suite("Photo editor model")
struct PhotoEditorModelTests {
    @MainActor private func model(width: Int = 400, height: Int = 300, in dir: URL = Fixture.tempDir(), name: String = "photo.png") throws -> PhotoEditorModel {
        let url = dir.appendingPathComponent(name)
        Fixture.image(at: url, width: width, height: height)
        return try PhotoEditorModel(source: url)
    }

    @Test @MainActor func aspectPresetsGiveTheRightPixelRatio() throws {
        let m = try model()
        for (aspect, ratio) in [(PhotoEditorModel.Aspect.square, 1.0), (.sixteenNine, 16.0 / 9), (.threeFour, 0.75), (.original, 4.0 / 3)] {
            m.applyAspect(aspect)
            let pixels = m.outputSize
            #expect(abs(pixels.width / pixels.height - ratio) < 0.02, "\(aspect.label)")
            #expect(m.crop.minX >= 0 && m.crop.maxX <= 1.0001 && m.crop.minY >= 0 && m.crop.maxY <= 1.0001)
        }
    }

    @Test @MainActor func rotatingResetsTheCropAndKeepsTheLockedRatio() throws {
        let m = try model()
        m.applyAspect(.square)
        m.rotate(by: 1)
        #expect(m.quarterTurns == 1)
        #expect(abs(m.outputSize.width - m.outputSize.height) <= 1)
        m.rotate(by: -2)
        #expect(m.quarterTurns == 3)
    }

    @Test @MainActor func freeCropOutputSizeMatchesTheRectangle() throws {
        let m = try model(width: 800, height: 600)
        m.crop = CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        #expect(m.outputSize == CGSize(width: 400, height: 300))
    }

    @Test @MainActor func savingWritesAFullResolutionEditedCopyNextToTheOriginal() throws {
        let dir = Fixture.tempDir()
        let m = try model(width: 800, height: 600, in: dir)
        m.crop = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        m.exposure = 0.5
        let out = try m.save(policy: OutputPolicy(folder: nil), quality: 0.9)
        #expect(out.lastPathComponent == "photo edited.png")
        #expect(out.deletingLastPathComponent() == dir)
        #expect(Fixture.pixelSize(out)! == (400, 300))
    }

    @Test @MainActor func largePicturesAreEditedOnAPreviewButSavedAtFullSize() throws {
        let dir = Fixture.tempDir()
        let m = try model(width: 3000, height: 2000, in: dir, name: "big.png")
        #expect(m.outputSize == CGSize(width: 3000, height: 2000))
        m.applyAspect(.square)
        let out = try m.save(policy: OutputPolicy(folder: nil), quality: 0.9)
        let size = Fixture.pixelSize(out)!
        #expect(size.0 == size.1 && size.0 >= 1990 && size.0 <= 2000)
    }

    @Test @MainActor func backgroundGrowsTheCanvasAndSavesAsTheSameFormat() throws {
        let dir = Fixture.tempDir()
        let m = try model(width: 400, height: 300, in: dir)
        m.backgroundEnabled = true
        m.canvas = .square
        m.padding = 0.1
        let out = try m.save(policy: OutputPolicy(folder: nil), quality: 0.9)
        let size = Fixture.pixelSize(out)!
        #expect(size.0 == size.1 && size.0 >= 480)
        #expect(m.outputSize == CGSize(width: size.0, height: size.1))
    }

    @Test @MainActor func jpegSourcesStayJPEG() throws {
        let dir = Fixture.tempDir()
        let url = dir.appendingPathComponent("a.jpg")
        Fixture.image(at: url, width: 200, height: 100, uti: "public.jpeg", alpha: false)
        let m = try PhotoEditorModel(source: url)
        m.flipH = true
        let out = try m.save(policy: OutputPolicy(folder: nil), quality: 0.8)
        #expect(Fixture.imageType(out) == "public.jpeg")
    }

    @Test @MainActor func editTrackingAndResets() throws {
        let m = try model()
        #expect(!m.hasEdits)
        m.straighten = 3; m.exposure = 1
        #expect(m.hasEdits)
        m.resetGeometry(); m.resetAdjustments()
        #expect(!m.hasEdits)
        #expect(m.renderPreview() != nil)
    }
}

@Suite("Guided practice")
struct PracticeTests {
    @Test @MainActor func theSamplePictureIsARealPNGBesideWhichResultsCanBeSaved() throws {
        let practice = PracticeCoordinator()
        practice.newSample()
        let url = try #require(practice.sample)
        #expect(url.lastPathComponent == "Sunset.png")
        #expect(Fixture.pixelSize(url)! == (1200, 800))
        #expect(FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path))
    }

    @Test @MainActor func stepsFollowWhatTheUserDoes() throws {
        let practice = PracticeCoordinator()
        practice.isActive = true
        let sample = try #require(practice.sample)
        #expect(practice.step == .idle)

        practice.dragStarted([URL(fileURLWithPath: "/tmp/other.png")])          // a different file doesn't count
        #expect(practice.step == .idle)

        practice.dragStarted([sample])
        #expect(practice.step == .dragging)
        practice.wheelOpened(.convert)
        #expect(practice.step == .wheelOpen(.convert))
        practice.wheelOpened(.tools)                                            // switching wheels keeps the step
        #expect(practice.step == .wheelOpen(.tools))

        let output = sample.deletingLastPathComponent().appendingPathComponent("Sunset.jpg")
        practice.jobFinished(inputs: [sample], outputs: [output], title: "JPG")
        #expect(practice.step == .done(output: output, title: "JPG"))
    }

    @Test @MainActor func lettingGoEarlyExplainsWhatToDoAndAllowsRetry() throws {
        let practice = PracticeCoordinator()
        practice.isActive = true
        let sample = try #require(practice.sample)
        practice.dragStarted([sample])
        practice.dragEnded()
        #expect(practice.step == .idle)
        #expect(practice.hint?.contains("tapping the key") == true)

        practice.dragStarted([sample])
        practice.wheelOpened(.convert)
        practice.dragEnded()
        #expect(practice.step == .idle)
        #expect(practice.hint?.contains("Drop the picture") == true)
        #expect(practice.attempts == 2)
    }

    @Test @MainActor func nothingHappensWhenThePracticePageIsNotOpen() throws {
        let practice = PracticeCoordinator()
        practice.newSample()
        let sample = try #require(practice.sample)
        practice.dragStarted([sample])
        practice.wheelOpened(.convert)
        #expect(practice.step == .idle)
    }

    @Test @MainActor func tryAgainMakesAFreshPicture() throws {
        let practice = PracticeCoordinator()
        practice.isActive = true
        let first = try #require(practice.sample)
        practice.jobFinished(inputs: [first], outputs: [first], title: "x")
        practice.newSample()
        #expect(practice.sample != first)
        #expect(practice.step == .idle)
    }
}
