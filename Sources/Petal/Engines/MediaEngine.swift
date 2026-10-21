import Foundation
import AVFoundation

nonisolated struct AudioFormat: Sendable, Hashable {
    let ext: String
    let name: String
    /// Written by AVFoundation, no ffmpeg required.
    let native: Bool
    /// ffmpeg encoder needed when not native.
    let encoder: String?
    let ffmpegArgs: [String]

    static let m4a = AudioFormat(ext: "m4a", name: "M4A", native: true, encoder: nil, ffmpegArgs: ["-c:a", "aac", "-b:a", "192k"])
    static let wav = AudioFormat(ext: "wav", name: "WAV", native: true, encoder: nil, ffmpegArgs: ["-c:a", "pcm_s16le"])
    static let aiff = AudioFormat(ext: "aiff", name: "AIFF", native: true, encoder: nil, ffmpegArgs: ["-c:a", "pcm_s16be"])
    static let flac = AudioFormat(ext: "flac", name: "FLAC", native: true, encoder: nil, ffmpegArgs: ["-c:a", "flac"])
    static let wma = AudioFormat(ext: "wma", name: "WMA", native: false, encoder: "wmav2", ffmpegArgs: ["-c:a", "wmav2", "-b:a", "192k"])
    static let caf = AudioFormat(ext: "caf", name: "CAF", native: true, encoder: nil, ffmpegArgs: ["-c:a", "pcm_s16le"])
    static let mp3 = AudioFormat(ext: "mp3", name: "MP3", native: false, encoder: "libmp3lame", ffmpegArgs: ["-c:a", "libmp3lame", "-q:a", "2"])
    static let ogg = AudioFormat(ext: "ogg", name: "OGG", native: false, encoder: "libvorbis", ffmpegArgs: ["-c:a", "libvorbis", "-q:a", "5"])
    static let opus = AudioFormat(ext: "opus", name: "Opus", native: false, encoder: "libopus", ffmpegArgs: ["-c:a", "libopus", "-b:a", "128k"])

    static let all: [AudioFormat] = [.m4a, .mp3, .wav, .flac, .aiff, .ogg, .opus, .wma, .caf]
}

nonisolated struct VideoFormat: Sendable, Hashable {
    let ext: String
    let name: String
    let native: Bool
    let encoder: String?
    let ffmpegArgs: [String]

    static let mp4 = VideoFormat(ext: "mp4", name: "MP4", native: true, encoder: nil, ffmpegArgs: ["-c:v", "h264_videotoolbox", "-q:v", "65", "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"])
    static let mov = VideoFormat(ext: "mov", name: "MOV", native: true, encoder: nil, ffmpegArgs: ["-c:v", "h264_videotoolbox", "-q:v", "65", "-c:a", "aac", "-b:a", "192k"])
    static let webm = VideoFormat(ext: "webm", name: "WebM", native: false, encoder: "libvpx-vp9",
                                  ffmpegArgs: ["-c:v", "libvpx-vp9", "-crf", "32", "-b:v", "0", "-row-mt", "1", "-c:a", "libopus", "-b:a", "128k"])
    static let mkv = VideoFormat(ext: "mkv", name: "MKV", native: false, encoder: "h264_videotoolbox", ffmpegArgs: ["-c:v", "h264_videotoolbox", "-q:v", "65", "-c:a", "aac", "-b:a", "192k"])
    static let avi = VideoFormat(ext: "avi", name: "AVI", native: false, encoder: "mpeg4", ffmpegArgs: ["-c:v", "mpeg4", "-q:v", "4", "-c:a", "libmp3lame", "-q:a", "4"])
    static let wmv = VideoFormat(ext: "wmv", name: "WMV", native: false, encoder: "wmv2", ffmpegArgs: ["-c:v", "wmv2", "-q:v", "4", "-c:a", "wmav2", "-b:a", "192k"])
    static let gif = VideoFormat(ext: "gif", name: "GIF", native: false, encoder: "gif",
                                 ffmpegArgs: ["-vf", "fps=15,scale=640:-1:flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse", "-loop", "0", "-an"])

    static let all: [VideoFormat] = [.mp4, .mov, .webm, .mkv, .avi, .wmv, .gif]
}

nonisolated enum MediaEngine {
    // MARK: Video

    /// True when AVFoundation can open the file (MP4, MOV, M4V…). MKV, WebM, AVI and WMV need ffmpeg.
    static func avfoundationCanRead(_ url: URL) async -> Bool {
        (try? await AVURLAsset(url: url).load(.isPlayable)) == true
    }

    static func convertVideo(_ src: URL, to format: VideoFormat, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        if format.native, await avfoundationCanRead(src) {
            try await export(src, to: dest, preset: AVAssetExportPresetHighestQuality, type: format.ext == "mov" ? .mov : .mp4, step: step)
        } else {
            guard FFmpeg.capabilities.isAvailable else {
                throw PetalError(format.native ? "macOS can't read this video, and the converter engine is missing." : "\(format.name) needs the converter engine, which is missing.")
            }
            let seconds = await duration(of: src)
            try await FFmpeg.run(["-i", src.path, "-map", "0:v:0?", "-map", "0:a:0?"] + format.ffmpegArgs + [dest.path], duration: seconds, progress: step)
        }
        return dest
    }

    static func compressVideo(_ src: URL, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> (url: URL, note: String) {
        let before = ByteFormat.size(of: src)
        let dest = ctx.policy.destination(for: src, ext: "mp4", suffix: "compressed")
        if await avfoundationCanRead(src) {
            try await export(src, to: dest, preset: AVAssetExportPreset1280x720, type: .mp4, step: step)
        } else {
            let seconds = await duration(of: src)
            try await FFmpeg.run(["-i", src.path, "-map", "0:v:0?", "-map", "0:a:0?", "-vf", "scale=-2:'min(720,ih)'",
                                  "-c:v", "h264_videotoolbox", "-q:v", "55", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", dest.path],
                                 duration: seconds, progress: step)
        }
        let after = ByteFormat.size(of: dest)
        if after >= before {
            try? FileManager.default.removeItem(at: dest)
            return (src, "Already as small as it gets")
        }
        return (dest, ByteFormat.savings(from: before, to: after))
    }

    static func extractAudio(_ src: URL, to format: AudioFormat, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        if format == .m4a, await avfoundationCanRead(src) {
            let dest = ctx.policy.destination(for: src, ext: "m4a")
            try await export(src, to: dest, preset: AVAssetExportPresetAppleM4A, type: .m4a, step: step)
            return dest
        }
        return try await convertAudio(src, to: format, ctx: ctx, step: step)
    }

    private static func export(_ src: URL, to dest: URL, preset: String, type: AVFileType, step: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: src)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw PetalError("This file can't be exported on this Mac.")
        }
        let box = SessionBox(session)
        let watcher = Task {
            for await state in box.session.states(updateInterval: 0.1) {
                if case .exporting(let progress) = state { step(progress.fractionCompleted) }
            }
        }
        defer { watcher.cancel() }
        do {
            try await session.export(to: dest, as: type)
        } catch {
            try? FileManager.default.removeItem(at: dest)
            throw PetalError("Export failed: \(error.localizedDescription)")
        }
    }

    // MARK: Audio

    static func convertAudio(_ src: URL, to format: AudioFormat, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        if format.native, (try? AVAudioFile(forReading: src)) != nil {
            try writeNative(src, to: dest, format: format, step: step)
            return dest
        }
        // Video sources or exotic codecs go through ffmpeg when we have it.
        guard FFmpeg.capabilities.isAvailable else {
            if format.native { throw PetalError("macOS can't read this audio. Install ffmpeg in Settings → Engines.") }
            throw PetalError("\(format.name) needs ffmpeg. Install it in Settings → Engines.")
        }
        let seconds = await duration(of: src)
        try await FFmpeg.run(["-i", src.path, "-vn"] + format.ffmpegArgs + [dest.path], duration: seconds, progress: step)
        return dest
    }

    private static func writeNative(_ src: URL, to dest: URL, format: AudioFormat, step: (Double) -> Void) throws {
        let input = try AVAudioFile(forReading: src)
        let processing = input.processingFormat
        var settings: [String: Any] = [AVSampleRateKey: processing.sampleRate, AVNumberOfChannelsKey: Int(processing.channelCount)]
        switch format {
        case .m4a:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = 192_000
        case .flac:
            settings[AVFormatIDKey] = kAudioFormatFLAC
            settings[AVLinearPCMBitDepthKey] = 24
        case .aiff:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsBigEndianKey] = true
            settings[AVLinearPCMIsFloatKey] = false
        default: // wav, caf
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsFloatKey] = false
        }
        let output = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: processing.commonFormat, interleaved: processing.isInterleaved)
        let capacity: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: processing, frameCapacity: capacity) else { throw PetalError("Out of memory.") }
        let total = max(1, input.length)
        while input.framePosition < input.length {
            try input.read(into: buffer, frameCount: capacity)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
            step(Double(input.framePosition) / Double(total))
        }
    }

    static func compressAudio(_ src: URL, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> (url: URL, note: String) {
        let before = ByteFormat.size(of: src)
        let dest = ctx.policy.destination(for: src, ext: "m4a", suffix: "compressed")
        if (try? AVAudioFile(forReading: src)) != nil {
            let input = try AVAudioFile(forReading: src)
            let p = input.processingFormat
            let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: min(p.sampleRate, 44_100),
                                           AVNumberOfChannelsKey: Int(min(p.channelCount, 2)), AVEncoderBitRateKey: 96_000]
            let out = try AVAudioFile(forWriting: dest, settings: settings, commonFormat: p.commonFormat, interleaved: p.isInterleaved)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: p, frameCapacity: 32_768) else { throw PetalError("Out of memory.") }
            while input.framePosition < input.length {
                try input.read(into: buffer, frameCount: 32_768)
                if buffer.frameLength == 0 { break }
                try out.write(from: buffer)
                step(Double(input.framePosition) / Double(max(1, input.length)))
            }
        } else {
            let seconds = await duration(of: src)
            try await FFmpeg.run(["-i", src.path, "-vn", "-c:a", "aac", "-b:a", "96k", dest.path], duration: seconds, progress: step)
        }
        let after = ByteFormat.size(of: dest)
        if after >= before {
            try? FileManager.default.removeItem(at: dest)
            return (src, "Already as small as it gets")
        }
        return (dest, ByteFormat.savings(from: before, to: after))
    }

    // MARK: Images that need ffmpeg (WebP / AVIF)

    static func convertImageWithFFmpeg(_ src: URL, to format: ImageFormat, ctx: JobContext) async throws -> URL {
        let dest = ctx.policy.destination(for: src, ext: format.ext)
        let q = Int(ctx.imageQuality * 100)
        let args: [String]
        switch format {
        case .webp: args = ["-i", src.path, "-c:v", "libwebp", "-quality", "\(q)", dest.path]
        case .avif: args = ["-i", src.path, "-c:v", FFmpeg.capabilities.has("libsvtav1") ? "libsvtav1" : "libaom-av1",
                            "-crf", "\(max(10, 60 - q / 2))", "-still-picture", "1", dest.path]
        default: throw PetalError("Unsupported image format.")
        }
        try await FFmpeg.run(args, duration: nil, progress: { _ in })
        return dest
    }

    // MARK: Mute

    /// Copies the video track only, without re-encoding.
    static func mute(_ src: URL, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: src)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PetalError("This file has no video.") }
        let composition = AVMutableComposition()
        guard let out = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw PetalError("Couldn't build the muted video.")
        }
        let range = CMTimeRange(start: .zero, duration: try await asset.load(.duration))
        try out.insertTimeRange(range, of: track, at: .zero)
        out.preferredTransform = try await track.load(.preferredTransform)
        let type: AVFileType = src.pathExtension.lowercased() == "mov" ? .mov : .mp4
        let dest = ctx.policy.destination(for: src, ext: type == .mov ? "mov" : "mp4", suffix: "muted")
        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw PetalError("This file can't be exported on this Mac.")
        }
        let box = SessionBox(session)
        let watcher = Task { for await state in box.session.states(updateInterval: 0.1) { if case .exporting(let p) = state { step(p.fractionCompleted) } } }
        defer { watcher.cancel() }
        try await session.export(to: dest, as: type)
        return dest
    }

    // MARK: Video → GIF without ffmpeg

    /// Samples the first 30 seconds at 12 fps, 480 px wide, and writes an endlessly looping GIF.
    static func videoToGIF(_ src: URL, ctx: JobContext, step: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let asset = AVURLAsset(url: src)
        let total = await duration(of: src)
        guard total > 0 else { throw PetalError("Can't read the length of this video.") }
        let length = min(total, 30), fps = 12.0
        let count = max(1, Int(length * fps))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let dest = ctx.policy.destination(for: src, ext: "gif")
        guard let out = CGImageDestinationCreateWithURL(dest as CFURL, "com.compuserve.gif" as CFString, count, nil) else {
            throw PetalError("GIF export isn't available on this Mac.")
        }
        CGImageDestinationSetProperties(out, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary

        let times = (0..<count).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }
        var written = 0
        for await result in generator.images(for: times) {
            try Task.checkCancellation()
            if case .success(_, let image, _) = result {
                CGImageDestinationAddImage(out, image, frameProps)
                written += 1
            }
            step(Double(written) / Double(count))
        }
        guard written > 0, CGImageDestinationFinalize(out) else {
            try? FileManager.default.removeItem(at: dest)
            throw PetalError("Couldn't make a GIF from this video.")
        }
        return dest
    }

    // MARK: Helpers

    /// Length in seconds, or 0 when AVFoundation can't tell (MKV, WebM, OGG…), in which case ffmpeg reports no progress fraction.
    static func duration(of url: URL) async -> Double {
        guard let seconds = try? await AVURLAsset(url: url).load(.duration).seconds, seconds.isFinite else { return 0 }
        return seconds
    }
}

/// AVAssetExportSession is safe to observe while it exports; this box says so to the compiler.
nonisolated final class SessionBox: @unchecked Sendable {
    let session: AVAssetExportSession
    init(_ session: AVAssetExportSession) { self.session = session }
}
