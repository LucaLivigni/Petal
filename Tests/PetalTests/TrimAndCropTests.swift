import Testing
import Foundation
import AVFoundation
@testable import Petal

@Suite("Crop handles")
struct CropGeometryTests {
    private let crop = CGRect(x: 100, y: 80, width: 200, height: 120)    // view points

    @Test func hitTestingFindsHandlesEdgesAndInside() {
        #expect(CropGeometry.hit(CGPoint(x: 101, y: 81), crop: crop) == .topLeft)
        #expect(CropGeometry.hit(CGPoint(x: 299, y: 199), crop: crop) == .bottomRight)
        #expect(CropGeometry.hit(CGPoint(x: 200, y: 82), crop: crop) == .top)
        #expect(CropGeometry.hit(CGPoint(x: 298, y: 140), crop: crop) == .right)
        #expect(CropGeometry.hit(CGPoint(x: 200, y: 140), crop: crop) == .move)
        #expect(CropGeometry.hit(CGPoint(x: 20, y: 20), crop: crop) == nil)
    }

    @Test func movingNeverLeavesThePicture() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.4)
        let right = CropGeometry.dragged(start, handle: .move, dx: 5, dy: 0, ratio: nil)
        #expect(abs(right.maxX - 1) < 1e-9 && right.width == start.width)
        let up = CropGeometry.dragged(start, handle: .move, dx: 0, dy: -5, ratio: nil)
        #expect(up.minY == 0 && up.height == start.height)
    }

    @Test func freeResizeMovesOnlyTheDraggedSides() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.4)
        let r = CropGeometry.dragged(start, handle: .topLeft, dx: 0.1, dy: 0.05, ratio: nil)
        #expect(abs(r.minX - 0.3) < 1e-9 && abs(r.minY - 0.25) < 1e-9)
        #expect(abs(r.maxX - start.maxX) < 1e-9 && abs(r.maxY - start.maxY) < 1e-9)
        let edge = CropGeometry.dragged(start, handle: .right, dx: 0.1, dy: 0.3, ratio: nil)
        #expect(abs(edge.maxX - 0.8) < 1e-9 && edge.minY == start.minY && edge.maxY == start.maxY)
    }

    @Test func cropCannotCollapseOrEscape() {
        let start = CGRect(x: 0.2, y: 0.2, width: 0.5, height: 0.4)
        let tiny = CropGeometry.dragged(start, handle: .bottomRight, dx: -2, dy: -2, ratio: nil)
        #expect(tiny.width >= CropGeometry.minimumSize - 1e-9 && tiny.height >= CropGeometry.minimumSize - 1e-9)
        let big = CropGeometry.dragged(start, handle: .bottomRight, dx: 5, dy: 5, ratio: nil)
        #expect(big.maxX <= 1 + 1e-9 && big.maxY <= 1 + 1e-9)
    }

    @Test func lockedCornersKeepTheRatioAndTheOppositeCorner() {
        let start = CGRect(x: 0.25, y: 0.25, width: 0.4, height: 0.4)      // ratio 1 in normalised units
        for handle in [CropGeometry.Handle.topLeft, .topRight, .bottomLeft, .bottomRight] {
            let r = CropGeometry.dragged(start, handle: handle, dx: handle.movesLeft ? -0.1 : 0.1, dy: handle.movesTop ? -0.07 : 0.07, ratio: 1)
            #expect(abs(r.width / r.height - 1) < 1e-9, "\(handle)")
            let anchor = CGPoint(x: handle.movesLeft ? start.maxX : start.minX, y: handle.movesTop ? start.maxY : start.minY)
            let corner = CGPoint(x: handle.movesLeft ? r.maxX : r.minX, y: handle.movesTop ? r.maxY : r.minY)
            #expect(abs(corner.x - anchor.x) < 1e-9 && abs(corner.y - anchor.y) < 1e-9, "\(handle) anchor moved")
            #expect(r.minX >= -1e-9 && r.minY >= -1e-9 && r.maxX <= 1 + 1e-9 && r.maxY <= 1 + 1e-9)
        }
    }

    @Test func lockedEdgesGrowFromTheCentreAndStayInside() {
        let start = CGRect(x: 0.3, y: 0.3, width: 0.4, height: 0.2)         // ratio 2
        let r = CropGeometry.dragged(start, handle: .bottom, dx: 0, dy: 0.1, ratio: 2)
        #expect(abs(r.width / r.height - 2) < 1e-9)
        #expect(abs(r.midX - start.midX) < 1e-9 && abs(r.minY - start.minY) < 1e-9)
        let huge = CropGeometry.dragged(start, handle: .right, dx: 3, dy: 0, ratio: 2)
        #expect(huge.maxX <= 1 + 1e-9 && huge.maxY <= 1 + 1e-9 && huge.minY >= -1e-9)
        #expect(abs(huge.width / huge.height - 2) < 1e-9)
    }
}

@Suite("Trim")
struct TrimTests {
    private func sineWAV(in dir: URL, seconds: Int = 2) throws -> URL {
        let url = dir.appendingPathComponent("tone.wav")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount(44_100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for i in 0..<Int(frames) { buffer.floatChannelData![0][i] = sinf(Float(i) * 2 * .pi * 440 / 44_100) * 0.5 }
        try file.write(from: buffer)
        return url
    }

    private func length(_ url: URL) async throws -> Double { try await AVURLAsset(url: url).load(.duration).seconds }

    private func clip(in dir: URL) async throws -> URL {
        let url = dir.appendingPathComponent("clip.mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96,
                                                                          AVVideoCompressionPropertiesKey: [AVVideoMaxKeyFrameIntervalKey: 5]])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(nil, 160, 96, kCVPixelFormatType_32BGRA, nil, &buffer)
            CVPixelBufferLockBaseAddress(buffer!, [])
            memset(CVPixelBufferGetBaseAddress(buffer!), Int32(frame * 8 % 255), CVPixelBufferGetDataSize(buffer!))
            CVPixelBufferUnlockBaseAddress(buffer!, [])
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 10))
        }
        input.markAsFinished()
        await writer.finishWriting()
        return url
    }

    @Test func losslessPCMTrimKeepsExactlyTheSelectedFrames() async throws {
        let dir = Fixture.tempDir()
        let src = try sineWAV(in: dir)
        let out = dir.appendingPathComponent("cut.wav")
        try await TrimModel.trimPCM(src, to: out, from: 0.5, to: 1.5)
        let file = try AVAudioFile(forReading: out)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 1.0) < 0.001)
    }

    @Test @MainActor func audioTrimThroughTheModel() async throws {
        let dir = Fixture.tempDir()
        let src = try sineWAV(in: dir)
        let model = TrimModel(url: src)
        await model.load()
        #expect(model.isLoaded && abs(model.duration - 2) < 0.01 && !model.isVideo)
        #expect(!model.isTrimmed)
        model.setStart(0.5); model.setEnd(1.5)
        #expect(model.isTrimmed && abs(model.selectionLength - 1) < 1e-9)
        let out = try await model.export(policy: OutputPolicy(folder: nil))
        #expect(out.lastPathComponent == "tone trimmed.wav")
        #expect(abs(try await length(out) - 1.0) < 0.01)
        model.tearDown()
    }

    @Test @MainActor func compressedAudioIsTrimmedToM4A() async throws {
        let dir = Fixture.tempDir()
        let m4a = try await MediaEngine.convertAudio(try sineWAV(in: dir, seconds: 3), to: .m4a, ctx: Fixture.context(), step: { _ in })
        let model = TrimModel(url: m4a)
        await model.load()
        model.setStart(1); model.setEnd(2.5)
        let out = try await model.export(policy: OutputPolicy(folder: nil))
        #expect(out.pathExtension == "m4a")
        #expect(abs(try await length(out) - 1.5) < 0.15)
        model.tearDown()
    }

    @Test @MainActor func videoTrimReEncodesToTheRequestedRange() async throws {
        let dir = Fixture.tempDir()
        let model = TrimModel(url: try await clip(in: dir))
        await model.load()
        #expect(model.isVideo && abs(model.duration - 3) < 0.1)
        #expect(model.thumbnails.count >= 8)
        model.setStart(0.7); model.setEnd(2.2)
        let out = try await model.export(policy: OutputPolicy(folder: nil))
        #expect(out.lastPathComponent == "clip trimmed.mp4")
        #expect(abs(try await length(out) - 1.5) < 0.2)
        model.tearDown()
    }

    @Test @MainActor func fastCutProducesAShorterFileToo() async throws {
        let dir = Fixture.tempDir()
        let model = TrimModel(url: try await clip(in: dir))
        await model.load()
        model.fast = true
        model.setStart(1); model.setEnd(2)
        let out = try await model.export(policy: OutputPolicy(folder: nil))
        let seconds = try await length(out)
        #expect(seconds > 0.5 && seconds < 2.2)
        model.tearDown()
    }

    @Test @MainActor func handlesCannotCrossOrLeaveTheClip() async throws {
        let dir = Fixture.tempDir()
        let model = TrimModel(url: try await clip(in: dir))
        await model.load()
        model.setEnd(1)
        model.setStart(5)
        #expect(model.start <= model.end - TrimModel.minimumLength + 1e-9)
        model.setStart(0.2); model.setEnd(99)
        #expect(model.end == model.duration)
        model.setStart(-3)
        #expect(model.start == 0)
        model.tearDown()
    }

    @Test func waveformHasNormalisedPeaks() async throws {
        let dir = Fixture.tempDir()
        let bars = await TrimModel.makeWaveform(url: try sineWAV(in: dir, seconds: 1), bars: 120)
        #expect(bars.count == 120)
        #expect(bars.max() == 1)
        #expect(bars.filter { $0 > 0.5 }.count > 100)
    }

    @Test func clockFormatting() {
        #expect(TrimModel.clock(0) == "0:00.0")
        #expect(TrimModel.clock(75.34) == "1:15.3")
    }

    @Test func catalogOffersTheEditorsWhereTheyWork() {
        func tools(_ n: String) -> [String] { Catalog.operations(for: [URL(fileURLWithPath: "/tmp/\(n)")], wheel: .tools).map(\.id) }
        #expect(tools("a.jpg").contains("tools.edit") && tools("a.jpg").contains("tools.background"))
        #expect(tools("a.mp4").contains("tools.trim") && tools("a.mp3").contains("tools.trim"))
        #expect(!tools("a.mkv").contains("tools.trim"), "AVFoundation can't preview MKV")
        #expect(!tools("a.ogg").contains("tools.trim"))
        #expect(TrimModel.canTrim(URL(fileURLWithPath: "/x/y.MOV")))
    }
}
