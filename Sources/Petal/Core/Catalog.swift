import Foundation

/// Decides which wedges each wheel shows for a given selection.
nonisolated enum Catalog {
    static func operations(for urls: [URL], wheel: PetalAction.Wheel, settingsTerminal: String = "com.apple.Terminal") -> [PetalAction] {
        guard !urls.isEmpty else { return [] }
        let kind = FileKind.common(of: urls)
        switch wheel {
        case .convert: return convertOperations(kind: kind, urls: urls)
        case .tools: return toolOperations(kind: kind, urls: urls)
        case .actions: return actionOperations()
        }
    }

    // MARK: Helpers

    private static func each(_ ctx: JobContext, _ body: (URL, @escaping @Sendable (Double) -> Void) async throws -> URL) async throws -> JobOutcome {
        var outputs: [URL] = []
        let total = ctx.inputs.count
        for (index, url) in ctx.inputs.enumerated() {
            try Task.checkCancellation()
            let step: @Sendable (Double) -> Void = { ctx.reportStep(index, of: total, fraction: $0) }
            outputs.append(try await body(url, step))
            ctx.reportStep(index + 1, of: total)
        }
        return JobOutcome(outputs: outputs)
    }

    private static func without(_ ext: String, in urls: [URL]) -> Bool {
        !urls.allSatisfy { $0.pathExtension.lowercased() == ext }
    }

    private static let blurbs: [String: String] = [
        "jpg": "Photos", "png": "Lossless", "heic": "Efficient", "webp": "Web", "avif": "Smallest", "tiff": "Archival",
        "gif": "Animated", "bmp": "Legacy", "pdf": "Document", "mp4": "Universal", "mov": "QuickTime", "webm": "Web video",
        "mkv": "Container", "avi": "Legacy", "m4a": "AAC audio", "mp3": "Universal audio", "wav": "Uncompressed", "flac": "Lossless audio",
        "aiff": "Uncompressed", "ogg": "Vorbis", "opus": "Voice & music", "caf": "Core Audio", "docx": "Word", "rtf": "Rich text",
        "html": "Web page", "odt": "OpenDocument", "txt": "Plain text", "csv": "Spreadsheet", "tsv": "Tab separated", "json": "Structured data",
        "srt": "SubRip", "vtt": "WebVTT", "zip": "Archive", "tar.gz": "Unix archive",
    ]

    private static func format(_ id: String, _ name: String, perform: @escaping @concurrent @Sendable (JobContext) async throws -> JobOutcome) -> PetalAction {
        PetalAction(id: "convert.\(id)", title: name, subtitle: blurbs[id], glyph: .format(name), outputExtension: id, perform: perform)
    }

    private static func tool(_ id: String, _ title: String, _ subtitle: String?, _ symbol: String,
                             perform: @escaping @concurrent @Sendable (JobContext) async throws -> JobOutcome) -> PetalAction {
        PetalAction(id: "tools.\(id)", title: title, subtitle: subtitle, glyph: .symbol(symbol), perform: perform)
    }

    // MARK: Convert

    private static func convertOperations(kind: FileKind, urls: [URL]) -> [PetalAction] {
        var ops: [PetalAction] = []
        let ffmpeg = FFmpeg.capabilities

        switch kind {
        case .image:
            for f in ImageEngine.catalogOrder where without(f.ext, in: urls) {
                if f == .pdf { continue }
                let native = ImageEngine.canWriteNatively(f)
                let viaCWebP = f == .webp && ExternalTool.cwebp != nil
                let viaFFmpeg = (f == .webp && ffmpeg.has("libwebp")) || (f == .avif && (ffmpeg.has("libsvtav1") || ffmpeg.has("libaom-av1")))
                guard native || viaCWebP || viaFFmpeg else { continue }
                ops.append(format(f.ext, f.name) { ctx in
                    try await each(ctx) { url, _ in
                        if viaCWebP { return try await ImageEngine.convertToWebP(url, ctx: ctx) }
                        return native ? try ImageEngine.convert(url, to: f, ctx: ctx) : try await MediaEngine.convertImageWithFFmpeg(url, to: f, ctx: ctx)
                    }
                })
                if f == .gif, without("pdf", in: urls) {
                    ops.append(format("pdf", "PDF") { ctx in
                        try await each(ctx) { url, _ in try PDFEngine.imagesToPDF([url], ctx: ctx) }
                    })
                }
            }

        case .video:
            for f in VideoFormat.all where without(f.ext, in: urls) {
                if f == .gif { continue }
                guard f.native || f.encoder.map(ffmpeg.has) == true else { continue }
                ops.append(format(f.ext, f.name) { ctx in
                    try await each(ctx) { url, step in try await MediaEngine.convertVideo(url, to: f, ctx: ctx, step: step) }
                })
            }
            ops.append(format("gif", "GIF") { ctx in
                try await each(ctx) { url, step in
                    ffmpeg.has("gif") ? try await MediaEngine.convertVideo(url, to: .gif, ctx: ctx, step: step)
                                      : try await MediaEngine.videoToGIF(url, ctx: ctx, step: step)
                }
            })
            for a in [AudioFormat.m4a, .wav, .mp3] where a.native || a.encoder.map(ffmpeg.has) == true {
                ops.append(PetalAction(id: "convert.audio.\(a.ext)", title: a.name, subtitle: "Extract audio", glyph: .format(a.name), outputExtension: a.ext) { ctx in
                    try await each(ctx) { url, step in try await MediaEngine.extractAudio(url, to: a, ctx: ctx, step: step) }
                })
            }

        case .audio:
            for f in AudioFormat.all where without(f.ext, in: urls) {
                guard f.native || f.encoder.map(ffmpeg.has) == true else { continue }
                ops.append(format(f.ext, f.name) { ctx in
                    try await each(ctx) { url, step in try await MediaEngine.convertAudio(url, to: f, ctx: ctx, step: step) }
                })
            }

        case .pdf:
            let pagesOK = IWorkBridge.isInstalled(.pages)
            for f in [DocFormat.docx, .pages, .md, .epub, .txt] where f != .pages || pagesOK {
                ops.append(format(f.ext, f.name) { ctx in
                    try await each(ctx) { url, _ in
                        f == .txt ? try PDFEngine.extractText(url, ctx: ctx) : try await PDFExport.toDocument(url, format: f, ctx: ctx)
                    }
                })
            }
            ops.append(format("pptx", "PPTX") { ctx in
                try await each(ctx) { url, step in try await PDFExport.toPPTX(url, ctx: ctx, step: step) }
            })
            ops.append(format("xlsx", "XLSX") { ctx in
                try await each(ctx) { url, _ in try await PDFExport.toXLSX(url, ctx: ctx) }
            })
            for f in [ImageFormat.jpg, .png, .tiff] {
                ops.append(format(f.ext, f.name) { ctx in
                    try await each(ctx) { url, step in try PDFEngine.toImages(url, format: f, ctx: ctx, step: step) }
                })
            }

        case .document:
            let pagesOK = IWorkBridge.isInstalled(.pages)
            for f in DocFormat.all where without(f.ext, in: urls) && (f != .pages || pagesOK) {
                ops.append(format(f.ext, f.name) { ctx in
                    var outputs: [URL] = []
                    for (i, url) in ctx.inputs.enumerated() {
                        try Task.checkCancellation()
                        outputs.append(try await TextEngine.convert(url, to: f, ctx: ctx))
                        ctx.reportStep(i + 1, of: ctx.inputs.count)
                    }
                    return JobOutcome(outputs: outputs)
                })
            }

        case .slides:
            ops.append(format("pdf", "PDF") { ctx in
                try await each(ctx) { url, _ in
                    guard IWorkBridge.isInstalled(.keynote) else { throw PetalError("Slides need Keynote (free on the App Store).") }
                    let dest = ctx.policy.destination(for: url, ext: "pdf")
                    try await IWorkBridge.slidesToPDF(url, to: dest)
                    return dest
                }
            })
            for (id, name, keynoteFormat) in [("jpg", "JPG", "JPEG"), ("png", "PNG", "PNG")] {
                ops.append(format(id, name) { ctx in
                    try await each(ctx) { url, _ in
                        guard IWorkBridge.isInstalled(.keynote) else { throw PetalError("Slides need Keynote (free on the App Store).") }
                        let folder = ctx.policy.uniqueURL(in: ctx.policy.directory(for: url), base: "\(url.deletingPathExtension().lastPathComponent) slides", ext: "")
                        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                        try await IWorkBridge.slidesToImages(url, folder: folder, format: keynoteFormat)
                        return folder
                    }
                })
            }

        case .spreadsheet:
            for (ext, name) in SpreadsheetEngine.formats where without(ext, in: urls) {
                ops.append(format(ext, name) { ctx in
                    try await each(ctx) { url, _ in try await SpreadsheetEngine.convert(url, toExtension: ext, ctx: ctx) }
                })
            }

        case .subtitle:
            for ext in ["srt", "vtt", "txt"] where without(ext, in: urls) {
                ops.append(format(ext, ext.uppercased()) { ctx in
                    try await each(ctx) { url, _ in try DataEngine.convertSubtitles(url, toExtension: ext, ctx: ctx) }
                })
            }

        case .archive:
            ops.append(PetalAction(id: "convert.extract", title: "Extract", subtitle: "Unpack here", glyph: .symbol("shippingbox")) { ctx in
                try await each(ctx) { url, _ in try await ArchiveEngine.extract(url, ctx: ctx) }
            })
            for (pack, id, name) in [(ArchiveEngine.Pack.zip, "zip", "ZIP"), (.tar, "tar", "TAR"), (.tarGz, "tar.gz", "TAR.GZ")]
            where !urls.allSatisfy({ $0.lastPathComponent.lowercased().hasSuffix("." + id) }) {
                ops.append(format(id, name) { ctx in
                    try await each(ctx) { url, _ in try await ArchiveEngine.convert(url, to: pack, ctx: ctx) }
                })
            }

        case .folder, .other:
            break
        }

        if kind == .folder || kind == .other {
            ops.append(format("zip", "ZIP") { ctx in JobOutcome(outputs: [try await ArchiveEngine.zipItems(ctx.inputs, ctx: ctx)]) })
            ops.append(format("tar", "TAR") { ctx in JobOutcome(outputs: [try await ArchiveEngine.tarPlain(ctx.inputs, ctx: ctx)]) })
            ops.append(format("tar.gz", "TAR.GZ") { ctx in JobOutcome(outputs: [try await ArchiveEngine.tarGz(ctx.inputs, ctx: ctx)]) })
            if urls.count == 1, kind == .other {
                ops.append(format("gz", "GZIP") { ctx in JobOutcome(outputs: [try await ArchiveEngine.gzip(ctx.inputs[0], ctx: ctx)]) })
            }
        }
        return ops
    }

    // MARK: Tools

    private static func toolOperations(kind: FileKind, urls: [URL]) -> [PetalAction] {
        var ops: [PetalAction] = []
        let ffmpeg = FFmpeg.capabilities

        switch kind {
        case .image:
            ops.append(tool("edit", "Edit", "Crop, rotate, adjust", "crop") { ctx in
                try await MainActor.run { try EditorWindows.shared.openPhoto(ctx.inputs[0], tab: .crop) }
                return JobOutcome(message: "Opened in the editor")
            })
            ops.append(tool("background", "Background", "Add a backdrop", "square.on.square.intersection.dashed") { ctx in
                try await MainActor.run { try EditorWindows.shared.openPhoto(ctx.inputs[0], tab: .background) }
                return JobOutcome(message: "Opened in the editor")
            })
            ops.append(tool("compress", "Compress", "Smaller file", "arrow.down.right.and.arrow.up.left") { ctx in
                var outputs: [URL] = []
                var notes: [String] = []
                for (i, url) in ctx.inputs.enumerated() {
                    try Task.checkCancellation()
                    let result = try ImageEngine.compress(url, ctx: ctx)
                    outputs.append(result.url); notes.append(result.outcome)
                    ctx.reportStep(i + 1, of: ctx.inputs.count)
                }
                return JobOutcome(outputs: outputs, message: ctx.inputs.count == 1 ? notes[0] : nil)
            })
            ops.append(tool("resize.half", "Resize ½", "50% of the size", "arrow.up.left.and.down.right.magnifyingglass") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.resize(url, ctx: ctx, scale: 0.5) }
            })
            ops.append(tool("resize.1920", "Fit 1920", "Longest side 1920 px", "rectangle.compress.vertical") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.resize(url, ctx: ctx, maxDimension: 1920) }
            })
            ops.append(tool("cutout", "Cut out", "Remove background", "person.crop.circle.badge.minus") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.removeBackground(url, ctx: ctx) }
            })
            ops.append(tool("ocr", "Copy text", "Recognise text", "text.viewfinder") { ctx in
                let text = try ctx.inputs.map { try ImageEngine.recognizeText($0) }.joined(separator: "\n\n")
                return JobOutcome(message: "Copied \(text.count.formatted()) characters", clipboardText: text)
            })
            ops.append(tool("rotate.left", "Rotate left", nil, "rotate.left") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.transform(url, ctx: ctx, suffix: "rotated") { $0.oriented(.left) } }
            })
            ops.append(tool("rotate.right", "Rotate right", nil, "rotate.right") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.transform(url, ctx: ctx, suffix: "rotated") { $0.oriented(.right) } }
            })
            ops.append(tool("flip", "Flip", "Mirror horizontally", "arrow.left.and.right.righttriangle.left.righttriangle.right") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.transform(url, ctx: ctx, suffix: "flipped") { $0.oriented(.upMirrored) } }
            })
            ops.append(tool("mono", "Black & white", nil, "circle.lefthalf.filled") { ctx in
                try await each(ctx) { url, _ in
                    try ImageEngine.transform(url, ctx: ctx, suffix: "bw") { $0.applyingFilter("CIPhotoEffectMono") }
                }
            })
            ops.append(tool("strip", "Strip metadata", "Remove EXIF & location", "location.slash") { ctx in
                try await each(ctx) { url, _ in try ImageEngine.transform(url, ctx: ctx, suffix: "clean") { $0 } }
            })
            if urls.count > 1 {
                ops.append(tool("pdf.merge", "One PDF", "Merge into a document", "doc.on.doc") { ctx in
                    JobOutcome(outputs: [try PDFEngine.imagesToPDF(ctx.inputs, ctx: ctx)])
                })
            }

        case .pdf:
            ops.append(tool("compress", "Compress", "Smaller file", "arrow.down.right.and.arrow.up.left") { ctx in
                var outputs: [URL] = []; var notes: [String] = []
                for url in ctx.inputs {
                    let r = try PDFEngine.compress(url, ctx: ctx)
                    outputs.append(r.url); notes.append(r.note)
                }
                return JobOutcome(outputs: outputs, message: ctx.inputs.count == 1 ? notes[0] : nil)
            })
            ops.append(tool("split", "Split pages", "One file per page", "square.split.2x1") { ctx in
                try await each(ctx) { url, _ in try PDFEngine.split(url, ctx: ctx) }
            })
            if urls.count > 1 {
                ops.append(tool("merge", "Merge", "Combine PDFs", "doc.on.doc") { ctx in
                    JobOutcome(outputs: [try PDFEngine.merge(ctx.inputs, ctx: ctx)])
                })
            }
            ops.append(tool("rotate", "Rotate", "Quarter turn right", "rotate.right") { ctx in
                try await each(ctx) { url, _ in try PDFEngine.rotate(url, ctx: ctx) }
            })
            ops.append(tool("copytext", "Copy text", "Selectable text", "text.alignleft") { ctx in
                try await MainActor.run { try FileActions.copyText(of: ctx.inputs[0]) }
            })

        case .video:
            if TrimModel.canTrim(urls[0]) {
                ops.append(tool("trim", "Trim", "Cut start and end", "scissors") { ctx in
                    await MainActor.run { EditorWindows.shared.openTrim(ctx.inputs[0]) }
                    return JobOutcome(message: "Opened in the editor")
                })
            }
            ops.append(tool("compress", "Compress", "720p H.264", "arrow.down.right.and.arrow.up.left") { ctx in
                var outputs: [URL] = []; var notes: [String] = []
                for (i, url) in ctx.inputs.enumerated() {
                    let r = try await MediaEngine.compressVideo(url, ctx: ctx) { ctx.reportStep(i, of: ctx.inputs.count, fraction: $0) }
                    outputs.append(r.url); notes.append(r.note)
                }
                return JobOutcome(outputs: outputs, message: ctx.inputs.count == 1 ? notes[0] : nil)
            })
            ops.append(tool("audio", "Extract audio", "M4A", "waveform") { ctx in
                try await each(ctx) { url, step in try await MediaEngine.extractAudio(url, to: .m4a, ctx: ctx, step: step) }
            })
            ops.append(tool("mute", "Mute", "Remove the sound", "speaker.slash") { ctx in
                try await each(ctx) { url, step in try await MediaEngine.mute(url, ctx: ctx, step: step) }
            })
            ops.append(tool("gif", "Make GIF", "First 30 s", "photo.stack") { ctx in
                try await each(ctx) { url, step in
                    ffmpeg.has("gif") ? try await MediaEngine.convertVideo(url, to: .gif, ctx: ctx, step: step)
                                      : try await MediaEngine.videoToGIF(url, ctx: ctx, step: step)
                }
            })

        case .audio:
            if TrimModel.canTrim(urls[0]) {
                ops.append(tool("trim", "Trim", "Cut start and end", "scissors") { ctx in
                    await MainActor.run { EditorWindows.shared.openTrim(ctx.inputs[0]) }
                    return JobOutcome(message: "Opened in the editor")
                })
            }
            ops.append(tool("compress", "Compress", "AAC 96 kbps", "arrow.down.right.and.arrow.up.left") { ctx in
                var outputs: [URL] = []; var notes: [String] = []
                for (i, url) in ctx.inputs.enumerated() {
                    let r = try await MediaEngine.compressAudio(url, ctx: ctx) { ctx.reportStep(i, of: ctx.inputs.count, fraction: $0) }
                    outputs.append(r.url); notes.append(r.note)
                }
                return JobOutcome(outputs: outputs, message: ctx.inputs.count == 1 ? notes[0] : nil)
            })

        case .document:
            ops.append(tool("copytext", "Copy text", "Plain text", "text.alignleft") { ctx in
                try await MainActor.run { try FileActions.copyText(of: ctx.inputs[0]) }
            })

        case .archive:
            ops.append(tool("list", "Copy contents", "File list", "list.bullet") { ctx in
                let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", ctx.inputs[0].path])
                guard result.status == 0 else { throw PetalError("Can't list this archive.") }
                let count = result.output.split(separator: "\n").count
                return JobOutcome(message: "Copied \(count) entries", clipboardText: result.output)
            })

        case .spreadsheet, .slides, .subtitle, .folder, .other:
            break
        }

        if ops.count < 4 {
            if kind != .folder {
                ops.append(tool("checksum", "Checksum", "SHA‑256", "number") { ctx in
                    try Checksums.sha256(of: ctx.inputs)
                })
            }
            ops.append(tool("size", "Size", "Total on disk", "scalemass") { ctx in Checksums.totalSize(of: ctx.inputs) })
            ops.append(tool("zip", "Zip", "Compress to ZIP", "shippingbox") { ctx in
                JobOutcome(outputs: [try await ArchiveEngine.zipItems(ctx.inputs, ctx: ctx)])
            })
        }
        return ops
    }

    // MARK: Actions

    private static func action(_ id: String, _ title: String, _ subtitle: String?, _ symbol: String,
                               perform: @escaping @concurrent @Sendable (JobContext) async throws -> JobOutcome) -> PetalAction {
        PetalAction(id: "actions.\(id)", title: title, subtitle: subtitle, glyph: .symbol(symbol), perform: perform)
    }

    private static func actionOperations() -> [PetalAction] {
        [
            action("airdrop", "AirDrop", "Send nearby", "antenna.radiowaves.left.and.right") { ctx in try await MainActor.run { try FileActions.airDrop(ctx.inputs) } },
            action("copy", "Copy", "To clipboard", "doc.on.doc") { ctx in await MainActor.run { FileActions.copy(ctx.inputs) } },
            action("copypath", "Copy path", nil, "link") { ctx in await MainActor.run { FileActions.copyPaths(ctx.inputs) } },
            action("move", "Move to…", "Choose a folder", "folder") { ctx in try await MainActor.run { try FileActions.moveOrCopy(ctx.inputs, move: true) } },
            action("copyto", "Copy to…", "Choose a folder", "folder.badge.plus") { ctx in try await MainActor.run { try FileActions.moveOrCopy(ctx.inputs, move: false) } },
            action("terminal", "Terminal", "Open here", "terminal") { ctx in try await MainActor.run { try FileActions.openTerminal(ctx.inputs, bundleID: ctx.terminalBundleID) } },
            action("float", "Float", "Keep on screen", "pin.fill") { ctx in
                await MainActor.run { FloatingShelf.shared.add(ctx.inputs); return JobOutcome(message: "Floating on your screen") }
            },
            action("reveal", "Show", "In Finder", "magnifyingglass") { ctx in await MainActor.run { FileActions.reveal(ctx.inputs) } },
        ]
    }
}
