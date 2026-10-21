import AVFoundation
import AppKit
import Observation

/// State behind the trim window for one audio or video file.
@MainActor
@Observable
final class TrimModel {
    let url: URL
    let isVideo: Bool
    let player: AVPlayer
    private let asset: AVURLAsset

    private(set) var duration = 0.0
    var start = 0.0
    var end = 0.0
    var playhead = 0.0
    private(set) var isPlaying = false
    private(set) var waveform: [Float] = []
    private(set) var thumbnails: [CGImage] = []
    private(set) var isLoaded = false
    private(set) var exportProgress: Double?
    /// Video only: cut at the nearest keyframes without re-encoding. Instant, but the edges can be off by a moment.
    var fast = false

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    nonisolated static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    nonisolated static let audioExtensions: Set<String> = ["mp3", "m4a", "wav", "aiff", "aif", "caf", "flac", "aac"]
    static let minimumLength = 0.1

    nonisolated static func canTrim(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return videoExtensions.contains(ext) || audioExtensions.contains(ext)
    }

    init(url: URL) {
        self.url = url
        isVideo = Self.videoExtensions.contains(url.pathExtension.lowercased())
        asset = AVURLAsset(url: url)
        player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
    }

    func load() async {
        let seconds = (try? await asset.load(.duration).seconds) ?? 0
        guard seconds.isFinite, seconds > 0 else { return }
        duration = seconds
        end = seconds
        isLoaded = true

        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1.0 / 30, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finishedPlaying() }
        }

        if isVideo { thumbnails = await Self.makeThumbnails(asset: asset, duration: seconds) }
        else { waveform = await Self.makeWaveform(url: url, bars: 240) }
    }

    func tearDown() {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    // MARK: Playback

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        playhead = seconds
        if isPlaying, seconds >= end - 0.01 { pause(); seek(to: start) }
    }

    private func finishedPlaying() {
        pause()
        seek(to: start)
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        if playhead < start || playhead >= end - 0.05 { seek(to: start) }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func seek(to seconds: Double) {
        let t = min(max(0, seconds), duration)
        playhead = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // MARK: Range

    func setStart(_ value: Double) {
        start = min(max(0, value), end - Self.minimumLength)
        if playhead < start { seek(to: start) }
    }

    func setEnd(_ value: Double) {
        end = max(min(duration, value), start + Self.minimumLength)
        if playhead > end { seek(to: end) }
    }

    var selectionLength: Double { max(0, end - start) }
    var isTrimmed: Bool { start > 0.001 || end < duration - 0.001 }

    static func clock(_ seconds: Double) -> String {
        let s = max(0, seconds)
        let minutes = Int(s) / 60, whole = Int(s) % 60, tenths = Int((s - floor(s)) * 10)
        return String(format: "%d:%02d.%d", minutes, whole, tenths)
    }

    // MARK: Export

    /// Writes the selection as a new file next to the original.
    func export(policy: OutputPolicy) async throws -> URL {
        pause()
        let range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
        exportProgress = 0
        defer { exportProgress = nil }
        let ext = url.pathExtension.lowercased()

        if !isVideo, ["wav", "aiff", "aif", "caf"].contains(ext) {
            let dest = policy.destination(for: url, ext: ext == "aif" ? "aiff" : ext, suffix: "trimmed")
            try await Self.trimPCM(url, to: dest, from: start, to: end)
            return dest
        }

        let type: AVFileType
        let preset: String
        let outExt: String
        if isVideo {
            type = ext == "mov" ? .mov : .mp4
            outExt = ext == "mov" ? "mov" : "mp4"
            preset = fast ? AVAssetExportPresetPassthrough : AVAssetExportPresetHighestQuality
        } else {
            type = .m4a; outExt = "m4a"; preset = AVAssetExportPresetAppleM4A
        }
        let dest = policy.destination(for: url, ext: outExt, suffix: "trimmed")
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { throw PetalError("This file can't be exported on this Mac.") }
        session.timeRange = range
        let box = SessionBox(session)
        let watcher = Task { [weak self] in
            for await state in box.session.states(updateInterval: 0.1) {
                if case .exporting(let p) = state { await MainActor.run { self?.exportProgress = p.fractionCompleted } }
            }
        }
        defer { watcher.cancel() }
        do { try await session.export(to: dest, as: type) } catch {
            try? FileManager.default.removeItem(at: dest)
            throw PetalError("Export failed: \(error.localizedDescription)")
        }
        return dest
    }

    /// Lossless cut for uncompressed audio: copy the frames in the range.
    nonisolated static func trimPCM(_ src: URL, to dest: URL, from start: Double, to end: Double) async throws {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let first = AVAudioFramePosition(start * format.sampleRate)
        let last = min(input.length, AVAudioFramePosition(end * format.sampleRate))
        guard last > first else { throw PetalError("Nothing to save.") }
        input.framePosition = first
        let output = try AVAudioFile(forWriting: dest, settings: input.fileFormat.settings, commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        let capacity: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { throw PetalError("Out of memory.") }
        var remaining = last - first
        while remaining > 0 {
            let count = AVAudioFrameCount(min(AVAudioFramePosition(capacity), remaining))
            try input.read(into: buffer, frameCount: count)
            if buffer.frameLength == 0 { break }
            try output.write(from: buffer)
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
    }

    // MARK: Timeline artwork

    private static func makeThumbnails(asset: AVURLAsset, duration: Double) async -> [CGImage] {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 0, height: 120)
        generator.requestedTimeToleranceBefore = CMTime(seconds: duration / 24, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: duration / 24, preferredTimescale: 600)
        let count = 14
        let times = (0..<count).map { CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600) }
        var images: [CGImage] = []
        for await result in generator.images(for: times) { if case .success(_, let image, _) = result { images.append(image) } }
        return images
    }

    /// Peak levels (0…1) for a bar-style waveform.
    nonisolated static func makeWaveform(url: URL, bars: Int) async -> [Float] {
        guard let file = try? AVAudioFile(forReading: url), file.length > 0 else { return [] }
        let format = file.processingFormat
        let perBar = max(1, Int(file.length) / bars)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { return [] }
        var peaks = [Float](repeating: 0, count: bars)
        var position = 0
        while position < Int(file.length) {
            guard (try? file.read(into: buffer, frameCount: 16_384)) != nil, buffer.frameLength > 0, let data = buffer.floatChannelData else { break }
            let frames = Int(buffer.frameLength)
            for i in 0..<frames {
                var level: Float = 0
                for c in 0..<Int(format.channelCount) { level = max(level, abs(data[c][i])) }
                let bar = min(bars - 1, (position + i) / perBar)
                peaks[bar] = max(peaks[bar], level)
            }
            position += frames
        }
        let top = max(peaks.max() ?? 1, 0.0001)
        return peaks.map { $0 / top }
    }
}
