import Foundation
import AVFoundation
import ImageIO
import CoreGraphics

/// What the wheel tells you about the files you're holding.
nonisolated struct FileFacts: Sendable, Equatable {
    var title = ""
    /// "HEIC image", "3 files"
    var kind = ""
    /// Extra details, shown after the kind: size, dimensions, pages, duration…
    var details: [String] = []

    var summary: String { ([kind] + details).filter { !$0.isEmpty }.joined(separator: " · ") }
}

nonisolated enum FileInspector {
    /// Cheap, synchronous: enough to draw the card the moment the wheel opens.
    static func quick(_ urls: [URL]) -> FileFacts {
        guard let first = urls.first else { return FileFacts() }
        let kind = FileKind.common(of: urls)
        if urls.count == 1 {
            let ext = first.pathExtension.uppercased()
            var facts = FileFacts(title: first.lastPathComponent)
            facts.kind = kind == .folder ? "Folder" : (ext.isEmpty ? kind.label : "\(ext) \(kind.label.lowercased())")
            if kind != .folder { facts.details.append(ByteFormat.string(ByteFormat.size(of: first))) }
            if kind == .image, let size = imageSize(first) { facts.details.append("\(size.w) × \(size.h)") }
            if kind == .pdf, let pages = CGPDFDocument(first as CFURL)?.numberOfPages {
                facts.details.append(pages == 1 ? "1 page" : "\(pages) pages")
            }
            return facts
        }
        var facts = FileFacts(title: "\(urls.count) items")
        var counts: [String: Int] = [:]
        for url in urls {
            let ext = url.pathExtension.uppercased()
            counts[ext.isEmpty ? "other" : ext, default: 0] += 1
        }
        let top = counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.prefix(3)
        facts.kind = top.map { "\($0.value) \($0.key)" }.joined(separator: ", ")
        let total = urls.reduce(Int64(0)) { $0 + ByteFormat.size(of: $1) }
        facts.details.append(ByteFormat.string(total))
        return facts
    }

    /// Slower details (duration, folder contents). Safe to call off the main actor.
    static func extra(_ urls: [URL]) async -> [String] {
        guard urls.count == 1, let url = urls.first else { return [] }
        switch FileKind.detect(url) {
        case .video:
            let asset = AVURLAsset(url: url)
            var parts: [String] = []
            if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
               let size = try? await track.load(.naturalSize), size.width > 0 {
                parts.append("\(Int(size.width)) × \(Int(size.height))")
            }
            if let d = try? await asset.load(.duration).seconds, d.isFinite { parts.append(clock(d)) }
            return parts
        case .audio:
            if let d = try? await AVURLAsset(url: url).load(.duration).seconds, d.isFinite { return [clock(d)] }
            return []
        case .folder:
            return [folderSummary(url)]
        default:
            return []
        }
    }

    private static func imageSize(_ url: URL) -> (w: Int, h: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let p = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = p[kCGImagePropertyPixelWidth] as? Int, let h = p[kCGImagePropertyPixelHeight] as? Int else { return nil }
        // Orientation 5–8 means the image is stored rotated.
        if let o = p[kCGImagePropertyOrientation] as? Int, o >= 5 { return (h, w) }
        return (w, h)
    }

    private static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return s >= 3600
            ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
            : String(format: "%d:%02d", s / 60, s % 60)
    }

    private static func folderSummary(_ url: URL) -> String {
        var files = 0, size: Int64 = 0
        let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey], options: [.skipsHiddenFiles])
        while let item = walker?.nextObject() as? URL, files < 20_000 {
            let v = try? item.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { files += 1; size += Int64(v?.fileSize ?? 0) }
        }
        return "\(files.formatted()) file\(files == 1 ? "" : "s") · \(ByteFormat.string(size))"
    }
}
