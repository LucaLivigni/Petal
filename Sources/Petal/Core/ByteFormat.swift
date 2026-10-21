import Foundation

nonisolated enum ByteFormat {
    static func size(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .totalFileAllocatedSizeKey]
        let v = try? url.resourceValues(forKeys: keys)
        return Int64(v?.fileSize ?? v?.totalFileAllocatedSize ?? 0)
    }

    static func string(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "Saved 62% (4.1 MB → 1.6 MB)"
    static func savings(from before: Int64, to after: Int64) -> String {
        guard before > 0 else { return "Done" }
        let pct = Int((1 - Double(after) / Double(before)) * 100)
        return "Saved \(pct)% (\(string(before)) → \(string(after)))"
    }
}
