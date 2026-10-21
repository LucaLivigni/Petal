import AppKit
import Observation
import ImageIO

enum WheelGeometry {
    /// Full canvas: ring in the middle, information card above or below it.
    static let canvas = CGSize(width: 440, height: 640)
    /// Canvas without the card, used in onboarding and settings previews.
    static let compactCanvas = CGSize(width: 430, height: 470)

    static let disc: CGFloat = 178         // radius of the frosted disc, including its rim
    static let ringInner: CGFloat = 68     // segments start here…
    static let ringOuter: CGFloat = 164    // …and end here
    static let hole: CGFloat = 58          // radius of the centre circle
    static let gap: CGFloat = 5            // constant width between neighbouring segments
    static let slotsPerPage = 8

    /// Slot under a point given relative to the ring centre (y up). `nil` in the centre or far outside.
    static func slot(at point: CGPoint, count: Int, scale: CGFloat = 1) -> Int? {
        guard count > 0 else { return nil }
        let p = CGPoint(x: point.x / scale, y: point.y / scale)
        let r = hypot(p.x, p.y)
        guard r > ringInner - 20, r < disc + 70 else { return nil }
        let step = 2 * Double.pi / Double(count)
        var theta = atan2(Double(p.x), Double(p.y))      // clockwise from 12 o'clock
        if theta < 0 { theta += 2 * .pi }
        return Int(((theta + step / 2).truncatingRemainder(dividingBy: 2 * .pi)) / step) % count
    }
}

@MainActor
@Observable
final class WheelModel {
    enum Slot: Identifiable {
        case op(PetalAction)
        case more(nextPage: Int)

        var id: String {
            switch self {
            case .op(let op): op.id
            case .more(let page): "more.\(page)"
            }
        }
    }

    enum Phase: Equatable {
        case choosing
        case running(title: String, progress: Double)
        case success(String)
        case failure(String)
    }

    var wheel: PetalAction.Wheel = .convert
    var operations: [PetalAction] = []
    var page = 0
    var hovered: Int?
    var activeID: String?
    var phase: Phase = .choosing
    var isVisible = false
    var keys: [PetalAction.Wheel: TriggerKey] = [:]

    var urls: [URL] = []
    var facts = FileFacts()
    var icon: NSImage?
    /// The information card sits above the ring when there's no room for it below.
    var cardOnTop = false
    var showsDetails = true

    var slots: [Slot] {
        guard operations.count > WheelGeometry.slotsPerPage else { return operations.map(Slot.op) }
        let perPage = WheelGeometry.slotsPerPage - 1
        let pages = (operations.count + perPage - 1) / perPage
        let current = min(page, pages - 1)
        let slice = operations[(current * perPage)..<min((current + 1) * perPage, operations.count)]
        return slice.map(Slot.op) + [.more(nextPage: (current + 1) % pages)]
    }

    var hoveredSlot: Slot? {
        guard let hovered, slots.indices.contains(hovered) else { return nil }
        return slots[hovered]
    }

    func configure(wheel: PetalAction.Wheel, operations: [PetalAction]) {
        self.wheel = wheel
        self.operations = operations
        page = 0
        hovered = nil
    }

    func describe(_ urls: [URL]) {
        self.urls = urls
        facts = FileInspector.quick(urls)
        let kind = FileKind.common(of: urls)
        icon = urls.first.map { Self.thumbnail(for: $0, kind: kind) }
        // Slower details arrive a moment later and are ignored if the selection changed meanwhile.
        Task { [urls] in
            let extra = await FileInspector.extra(urls)
            guard self.urls == urls, !extra.isEmpty else { return }
            self.facts.details.append(contentsOf: extra)
        }
    }

    /// Fills the model with a sample file so previews have something to show.
    func loadDemo(wheel: PetalAction.Wheel = .convert) {
        let sample = URL(fileURLWithPath: "/tmp/Holiday.jpg")
        urls = [sample]
        facts = FileFacts(title: "Holiday.jpg", kind: "JPG image", details: ["3.2 MB", "4032 × 3024"])
        icon = NSApp.applicationIconImage
        keys = Dictionary(uniqueKeysWithValues: PetalAction.Wheel.allCases.map { ($0, AppSettings.shared.key(for: $0)) })
        configure(wheel: wheel, operations: Catalog.operations(for: [sample], wheel: wheel))
    }

    /// "photo.png" — the name the result would get, for conversions.
    func outputHint(for op: PetalAction) -> String? {
        guard let ext = op.outputExtension, let first = urls.first else { return nil }
        if urls.count > 1 { return "\(urls.count) files → .\(ext)" }
        return AppSettings.shared.outputPolicy.destination(for: first, ext: ext).lastPathComponent
    }

    static func thumbnail(for url: URL, kind: FileKind) -> NSImage {
        if kind == .image,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceCreateThumbnailWithTransform: true,
               kCGImageSourceThumbnailMaxPixelSize: 220,
           ] as CFDictionary) {
            return NSImage(cgImage: cg, size: NSSize(width: cg.width / 2, height: cg.height / 2))
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
