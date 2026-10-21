import Testing
import Foundation
import AVFoundation
import ImageIO
@testable import Petal

/// These run against the ffmpeg and cwebp bundled in the app (Contents/Resources/Engines).
/// They are skipped when the engines haven't been built (run tools/build-engines.sh to build them).
@Suite("Bundled engines", .enabled(if: FFmpeg.capabilities.isAvailable && ExternalTool.cwebp != nil, "ffmpeg and cwebp aren't built; run tools/build-engines.sh"))
struct EngineBinaryTests {
    @Test func enginesAreBundledAndSelfContained() async throws {
        let ffmpeg = try #require(FFmpeg.capabilities.url, "ffmpeg is not bundled")
        #expect(ffmpeg.path.contains(".app/Contents/Resources/Engines/"))
        let cwebp = try #require(ExternalTool.cwebp, "cwebp is not bundled")
        #expect(cwebp.path.contains(".app/Contents/Resources/Engines/"))
        for tool in [ffmpeg, cwebp] {
            let links = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/otool"), ["-L", tool.path]).output
            for line in links.split(separator: "\n").dropFirst() {
                let path = line.trimmingCharacters(in: .whitespaces)
                #expect(path.hasPrefix("/usr/lib/") || path.hasPrefix("/System/Library/"), "\(tool.lastPathComponent) links \(path)")
            }
        }
    }

    @Test func ffmpegIsLGPLWithTheEncodersPetalNeeds() throws {
        let caps = FFmpeg.capabilities
        for encoder in ["libmp3lame", "libvorbis", "libopus", "libvpx-vp9", "libwebp", "h264_videotoolbox", "wmv2", "wmav2", "mpeg4", "gif", "flac", "aac"] {
            #expect(caps.has(encoder), "missing encoder \(encoder)")
        }
        #expect(!caps.has("libx264"), "a GPL encoder slipped in")
    }

    @Test func ffmpegBuildIsNotGPL() async throws {
        let out = try await ProcessRunner.run(try #require(FFmpeg.capabilities.url), ["-hide_banner", "-version"]).output
        #expect(out.contains("--disable-gpl"))
        #expect(out.contains("--disable-nonfree"))
        #expect(!out.contains("--enable-gpl"))
    }

    private func wav(in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 { buffer.floatChannelData![0][i] = sinf(Float(i) * 2 * .pi * 440 / 44_100) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    @Test(arguments: [AudioFormat.mp3, .ogg, .opus, .wma])
    func audioEncodersProduceDecodableFiles(format: AudioFormat) async throws {
        let dir = Fixture.tempDir()
        let out = try await MediaEngine.convertAudio(try wav(in: dir), to: format, ctx: Fixture.context(), step: { _ in })
        #expect(out.pathExtension == format.ext)
        #expect(ByteFormat.size(of: out) > 1000)
        // ffmpeg must be able to read it back and report about one second of audio.
        let probe = try await ProcessRunner.run(try #require(FFmpeg.capabilities.url), ["-hide_banner", "-i", out.path, "-f", "null", "-"])
        #expect(probe.error.contains("time=00:00:01") || probe.error.contains("time=00:00:00.9"), "\(probe.error.suffix(200))")
    }

    @Test(arguments: ["webm", "mkv", "avi", "wmv"])
    func videoEncodersProduceDecodableFiles(ext: String) async throws {
        let dir = Fixture.tempDir()
        let clip = dir.appendingPathComponent("clip.mp4")
        try await makeClip(at: clip)
        let format = try #require(VideoFormat.all.first { $0.ext == ext })
        let out = try await MediaEngine.convertVideo(clip, to: format, ctx: Fixture.context(), step: { _ in })
        #expect(ByteFormat.size(of: out) > 100)   // a solid-colour clip compresses to almost nothing
        let probe = try await ProcessRunner.run(try #require(FFmpeg.capabilities.url), ["-hide_banner", "-i", out.path, "-f", "null", "-"])
        #expect(probe.error.contains("Video:"), "\(probe.error.suffix(300))")
    }

    @Test func foreignContainerConvertsBackToMP4() async throws {
        let dir = Fixture.tempDir()
        let clip = dir.appendingPathComponent("clip.mp4")
        try await makeClip(at: clip)
        let mkv = try await MediaEngine.convertVideo(clip, to: .mkv, ctx: Fixture.context(), step: { _ in })
        #expect(await MediaEngine.avfoundationCanRead(mkv) == false)
        let back = try await MediaEngine.convertVideo(mkv, to: .mov, ctx: Fixture.context(), step: { _ in })
        #expect(await MediaEngine.avfoundationCanRead(back))
        let asset = AVURLAsset(url: back)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }

    @Test func webpViaCWebPAndViaFFmpeg() async throws {
        let dir = Fixture.tempDir()
        let png = dir.appendingPathComponent("a.png")
        Fixture.image(at: png, width: 200, height: 120)
        let viaCWebP = try await ImageEngine.convertToWebP(png, ctx: Fixture.context())
        let viaFFmpeg = try await MediaEngine.convertImageWithFFmpeg(png, to: .webp, ctx: Fixture.context())
        for url in [viaCWebP, viaFFmpeg] {
            let header = try Data(contentsOf: url).prefix(12)
            #expect(String(decoding: header.prefix(4), as: UTF8.self) == "RIFF")
            #expect(String(decoding: header.suffix(4), as: UTF8.self) == "WEBP")
            // macOS can read WebP back, so the pixels must decode.
            #expect(Fixture.pixelSize(url)! == (200, 120))
        }
    }

    @Test func catalogNowOffersTheFormatsThatNeededEngines() {
        func ids(_ n: String) -> [String] { Catalog.operations(for: [URL(fileURLWithPath: "/tmp/\(n)")], wheel: .convert).map(\.id) }
        #expect(ids("a.png").contains("convert.webp"))
        #expect(Set(ids("a.mp3")).isSuperset(of: ["convert.ogg", "convert.opus", "convert.wma", "convert.wav", "convert.flac"]))
        #expect(Set(ids("a.mov")).isSuperset(of: ["convert.webm", "convert.mkv", "convert.avi", "convert.wmv", "convert.mp4", "convert.audio.mp3"]))
        #expect(ids("a.mkv").contains("convert.mp4"))
        #expect(ids("a.ogg").contains("convert.mp3"))
    }

    /// A 1 s H.264 clip with silent AAC audio, made without ffmpeg.
    private func makeClip(at url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 160, 96, kCVPixelFormatType_32BGRA, nil, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 20 % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
    }
}
