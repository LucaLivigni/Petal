import AppKit
import ImageIO
import Observation

/// Drives the "try it" step of the welcome guide. The real drag monitor and wheel report what happens;
/// this turns those events into a step the guide can show.
@MainActor
@Observable
final class PracticeCoordinator {
    static let shared = PracticeCoordinator()

    enum Step: Equatable {
        case idle
        case dragging
        case wheelOpen(PetalAction.Wheel)
        case done(output: URL, title: String)
    }

    private(set) var step: Step = .idle
    private(set) var sample: URL?
    /// Becomes true while the guide's practice page is on screen.
    var isActive = false {
        didSet { if isActive, sample == nil { newSample() } }
    }
    private(set) var attempts = 0
    private(set) var hint: String?

    func newSample() {
        sample = Self.makeSample()
        step = .idle
        hint = nil
    }

    // MARK: Events from the app

    func dragStarted(_ urls: [URL]) {
        guard isActive, let sample, urls == [sample] else { return }
        attempts += 1
        step = .dragging
        hint = nil
    }

    func wheelOpened(_ wheel: PetalAction.Wheel) {
        guard isActive, case .dragging = step else {
            if isActive, case .wheelOpen = step { step = .wheelOpen(wheel) }
            return
        }
        step = .wheelOpen(wheel)
    }

    func dragEnded() {
        guard isActive else { return }
        switch step {
        case .dragging: step = .idle; hint = "You let go before tapping the key. Try again and tap it while you're still holding the picture."
        case .wheelOpen: step = .idle; hint = "No problem. Drop the picture on one of the options next time."
        default: break
        }
    }

    func jobFinished(inputs: [URL], outputs: [URL], title: String) {
        guard isActive, let sample, inputs == [sample], let first = outputs.first else { return }
        step = .done(output: first, title: title)
        hint = nil
    }

    // MARK: The sample picture

    /// A small sunset, drawn with Core Graphics, saved where the conversions can land next to it.
    private static func makeSample() -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Petal Practice", isDirectory: true)
            .appendingPathComponent(String(UUID().uuidString.prefix(8)), isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Sunset.png")

        let w = 1200, h = 800
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return url }
        let sky = CGGradient(colorsSpace: space, colors: [
            CGColor(red: 1.00, green: 0.80, blue: 0.45, alpha: 1), CGColor(red: 1.00, green: 0.50, blue: 0.30, alpha: 1),
            CGColor(red: 0.62, green: 0.30, blue: 0.55, alpha: 1), CGColor(red: 0.20, green: 0.16, blue: 0.40, alpha: 1),
        ] as CFArray, locations: [0, 0.38, 0.72, 1])!
        ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: CGFloat(h) * 0.32), end: CGPoint(x: 0, y: CGFloat(h)), options: [.drawsAfterEndLocation, .drawsBeforeStartLocation])
        ctx.setFillColor(CGColor(red: 1, green: 0.96, blue: 0.82, alpha: 1))
        ctx.fillEllipse(in: CGRect(x: 760, y: 300, width: 190, height: 190))
        for (i, shade) in [(0.30, 0.20), (0.22, 0.16), (0.14, 0.12)].enumerated() {
            ctx.setFillColor(CGColor(red: shade.0 * 0.7, green: shade.1 * 0.6, blue: shade.0 * 0.9, alpha: 1))
            let base = 150 + CGFloat(i) * 60
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: 0, y: base))
            for x in stride(from: 0, through: w, by: 40) {
                path.addLine(to: CGPoint(x: CGFloat(x), y: base + sin(CGFloat(x) / (110 - CGFloat(i) * 25) + CGFloat(i) * 2) * (36 - CGFloat(i) * 8)))
            }
            path.addLine(to: CGPoint(x: w, y: 0))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }
        if let image = ctx.makeImage(), let out = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(out, image, nil)
            CGImageDestinationFinalize(out)
        }
        return url
    }
}
