import Foundation

/// Decides where results are written and how they are named. Results never overwrite anything.
nonisolated struct OutputPolicy: Sendable {
    /// `nil` means "next to the original".
    var folder: URL?

    func directory(for source: URL) -> URL {
        folder ?? source.deletingLastPathComponent()
    }

    func destination(for source: URL, ext: String, suffix: String? = nil) -> URL {
        var base = source.deletingPathExtension().lastPathComponent
        if let suffix { base += " \(suffix)" }
        return uniqueURL(in: directory(for: source), base: base, ext: ext)
    }

    func destination(named base: String, ext: String, near source: URL) -> URL {
        uniqueURL(in: directory(for: source), base: base, ext: ext)
    }

    func uniqueURL(in directory: URL, base: String, ext: String) -> URL {
        let fm = FileManager.default
        func candidate(_ n: Int) -> URL {
            let name = n == 1 ? base : "\(base) \(n)"
            let file = ext.isEmpty ? name : "\(name).\(ext)"
            return directory.appendingPathComponent(file)
        }
        var n = 1
        while fm.fileExists(atPath: candidate(n).path) { n += 1 }
        return candidate(n)
    }
}
