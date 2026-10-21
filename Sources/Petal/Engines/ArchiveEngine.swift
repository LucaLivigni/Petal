import Foundation

nonisolated enum ArchiveEngine {
    private static let ditto = URL(fileURLWithPath: "/usr/bin/ditto")
    private static let tar = URL(fileURLWithPath: "/usr/bin/tar")
    private static let zip = URL(fileURLWithPath: "/usr/bin/zip")

    static func zipItems(_ items: [URL], ctx: JobContext) async throws -> URL {
        guard let first = items.first else { throw PetalError("Nothing to compress.") }
        if items.count == 1 {
            let dest = ctx.policy.destination(for: first, ext: "zip")
            let result = try await ProcessRunner.run(ditto, ["-c", "-k", "--keepParent", first.path, dest.path])
            guard result.status == 0 else { throw PetalError("Couldn't create the ZIP: \(result.error)") }
            return dest
        }
        let dest = ctx.policy.destination(named: "Archive", ext: "zip", near: first)
        let parents = Set(items.map { $0.deletingLastPathComponent().path })
        if parents.count == 1 {
            let result = try await ProcessRunner.run(zip, ["-r", "-q", dest.path] + items.map(\.lastPathComponent), currentDirectory: first.deletingLastPathComponent())
            guard result.status == 0 else { throw PetalError("Couldn't create the ZIP: \(result.error)") }
        } else {
            let result = try await ProcessRunner.run(zip, ["-r", "-q", "-j", dest.path] + items.map(\.path))
            guard result.status == 0 else { throw PetalError("Couldn't create the ZIP: \(result.error)") }
        }
        return dest
    }

    static func tarGz(_ items: [URL], ctx: JobContext) async throws -> URL {
        guard let first = items.first else { throw PetalError("Nothing to compress.") }
        let dest = items.count == 1
            ? ctx.policy.destination(for: first, ext: "tar.gz")
            : ctx.policy.destination(named: "Archive", ext: "tar.gz", near: first)
        let parents = Set(items.map { $0.deletingLastPathComponent().path })
        guard parents.count == 1 else { throw PetalError("Select items from a single folder to make a TAR.GZ.") }
        let result = try await ProcessRunner.run(tar, ["-czf", dest.path, "-C", first.deletingLastPathComponent().path] + items.map(\.lastPathComponent))
        guard result.status == 0 else { throw PetalError("Couldn't create the archive: \(result.error)") }
        return dest
    }

    enum Pack: String, Sendable { case zip, tar, tarGz }

    /// Packs the *contents* of a folder (used when converting between archive formats).
    private static func pack(contentsOf dir: URL, as format: Pack, to dest: URL) async throws {
        let result: ProcessRunner.Result
        switch format {
        case .zip: result = try await ProcessRunner.run(ditto, ["-c", "-k", dir.path, dest.path])
        case .tar: result = try await ProcessRunner.run(tar, ["-cf", dest.path, "-C", dir.path, "."])
        case .tarGz: result = try await ProcessRunner.run(tar, ["-czf", dest.path, "-C", dir.path, "."])
        }
        guard result.status == 0 else { throw PetalError("Couldn't create the archive: \(result.error)") }
    }

    /// ZIP ⇄ TAR ⇄ TAR.GZ (and RAR / 7Z input): unpack to a scratch folder, then pack again.
    static func convert(_ src: URL, to format: Pack, ctx: JobContext) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("petal-repack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let unpack = src.pathExtension.lowercased() == "zip"
            ? try await ProcessRunner.run(ditto, ["-x", "-k", src.path, scratch.path])
            : try await ProcessRunner.run(tar, ["-xf", src.path, "-C", scratch.path])
        guard unpack.status == 0 else { throw PetalError("Couldn't read \(src.lastPathComponent).") }
        var base = src.deletingPathExtension().lastPathComponent
        if base.hasSuffix(".tar") { base = String(base.dropLast(4)) }
        let ext = format == .zip ? "zip" : format == .tar ? "tar" : "tar.gz"
        let dest = ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: base, ext: ext)
        try await pack(contentsOf: scratch, as: format, to: dest)
        return dest
    }

    static func tarPlain(_ items: [URL], ctx: JobContext) async throws -> URL {
        guard let first = items.first else { throw PetalError("Nothing to compress.") }
        let dest = items.count == 1 ? ctx.policy.destination(for: first, ext: "tar") : ctx.policy.destination(named: "Archive", ext: "tar", near: first)
        guard Set(items.map { $0.deletingLastPathComponent().path }).count == 1 else { throw PetalError("Select items from a single folder to make a TAR.") }
        let result = try await ProcessRunner.run(tar, ["-cf", dest.path, "-C", first.deletingLastPathComponent().path] + items.map(\.lastPathComponent))
        guard result.status == 0 else { throw PetalError("Couldn't create the archive: \(result.error)") }
        return dest
    }

    /// Single-file gzip, like `gzip -k`.
    static func gzip(_ src: URL, ctx: JobContext) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("petal-gz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(src.lastPathComponent)
        try FileManager.default.copyItem(at: src, to: copy)
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/gzip"), ["-9", copy.path])
        guard result.status == 0 else { throw PetalError("Couldn't compress \(src.lastPathComponent).") }
        let dest = ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: src.lastPathComponent, ext: "gz")
        try FileManager.default.moveItem(at: scratch.appendingPathComponent(src.lastPathComponent + ".gz"), to: dest)
        return dest
    }

    /// Plain `.gz` (not a tarball): restores the original file.
    static func gunzip(_ src: URL, ctx: JobContext) async throws -> URL {
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("petal-gz-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let copy = scratch.appendingPathComponent(src.lastPathComponent)
        try FileManager.default.copyItem(at: src, to: copy)
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/gzip"), ["-d", copy.path])
        guard result.status == 0 else { throw PetalError("Couldn't decompress \(src.lastPathComponent).") }
        let name = src.deletingPathExtension().lastPathComponent
        let restored = scratch.appendingPathComponent(name)
        let dest = ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: (name as NSString).deletingPathExtension, ext: (name as NSString).pathExtension)
        try FileManager.default.moveItem(at: restored, to: dest)
        return dest
    }

    /// Extracts into a new folder beside the archive. bsdtar reads zip, tar, 7z, rar, iso and cab.
    static func extract(_ src: URL, ctx: JobContext) async throws -> URL {
        let lower = src.lastPathComponent.lowercased()
        if lower.hasSuffix(".gz"), !lower.hasSuffix(".tar.gz") { return try await gunzip(src, ctx: ctx) }
        var base = src.deletingPathExtension().lastPathComponent
        if base.hasSuffix(".tar") { base = String(base.dropLast(4)) }
        let folder = ctx.policy.uniqueURL(in: ctx.policy.directory(for: src), base: base, ext: "")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let result: ProcessRunner.Result
        if src.pathExtension.lowercased() == "zip" {
            result = try await ProcessRunner.run(ditto, ["-x", "-k", src.path, folder.path])
        } else {
            result = try await ProcessRunner.run(tar, ["-xf", src.path, "-C", folder.path])
        }
        guard result.status == 0 else {
            try? FileManager.default.removeItem(at: folder)
            throw PetalError("Couldn't extract \(src.lastPathComponent).")
        }
        return folder
    }
}
