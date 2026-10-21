import Foundation

nonisolated enum ProcessRunner {
    struct Result: Sendable {
        var status: Int32
        var output: String
        var error: String
    }

    /// Runs a tool to completion. Cancelling the task terminates the process.
    static func run(_ executable: URL, _ arguments: [String], currentDirectory: URL? = nil) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result, Error>) in
                process.terminationHandler = { finished in
                    let o = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    let e = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    continuation.resume(returning: Result(status: finished.terminationStatus, output: o, error: e))
                }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
    }
}

/// Finds optional helper tools: a copy bundled in the app, one in Application Support, or a Homebrew install.
nonisolated enum ExternalTool {
    static func locate(_ name: String) -> URL? {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "Engines") { candidates.append(bundled.path) }
        if let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            candidates.append(support.appendingPathComponent("Petal/Engines/\(name)").path)
        }
        candidates += ["/opt/homebrew/bin/\(name)", "/usr/local/bin/\(name)", "/opt/local/bin/\(name)"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static let cwebp: URL? = locate("cwebp")
}

/// Optional encoder for formats macOS can't write itself (MP3, WebM, WebP, AVIF, MKV, GIF video…).
nonisolated enum FFmpeg {
    struct Capabilities: Sendable {
        var url: URL?
        var encoders: Set<String> = []

        var isAvailable: Bool { url != nil }
        func has(_ encoder: String) -> Bool { encoders.contains(encoder) }
    }

    static let capabilities: Capabilities = detect()

    private static func detect() -> Capabilities {
        var candidates: [String] = []
        if let bundled = Bundle.main.url(forResource: "ffmpeg", withExtension: nil, subdirectory: "Engines") { candidates.append(bundled.path) }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        if let support { candidates.append(support.appendingPathComponent("Petal/Engines/ffmpeg").path) }
        candidates += ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/opt/local/bin/ffmpeg"]
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return Capabilities() }

        let url = URL(fileURLWithPath: path)
        let process = Process()
        process.executableURL = url
        process.arguments = ["-hide_banner", "-encoders"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return Capabilities(url: url) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
        var names: Set<String> = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 2, parts[0].count == 6 { names.insert(String(parts[1])) }
        }
        return Capabilities(url: url, encoders: names)
    }

    /// Runs ffmpeg with `-progress` parsing. `duration` (seconds) lets us report a fraction.
    static func run(_ arguments: [String], duration: Double?, progress: @escaping @Sendable (Double) -> Void) async throws {
        guard let exe = capabilities.url else { throw PetalError("This conversion needs ffmpeg. Install it in Settings → Engines.") }
        let process = Process()
        process.executableURL = exe
        process.arguments = ["-hide_banner", "-nostats", "-loglevel", "error", "-progress", "pipe:1", "-y"] + arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        let errorTail = LockedBuffer()
        err.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errorTail.append(String(decoding: data, as: UTF8.self)) }
        }
        if let duration, duration > 0 {
            out.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                for line in String(decoding: data, as: UTF8.self).split(separator: "\n") where line.hasPrefix("out_time_us=") {
                    if let micro = Double(line.dropFirst("out_time_us=".count)) {
                        progress(min(1, micro / 1_000_000 / duration))
                    }
                }
            }
        }

        let status: Int32 = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
                do { try process.run() } catch { continuation.resume(throwing: error) }
            }
        } onCancel: {
            if process.isRunning { process.terminate() }
        }
        out.fileHandleForReading.readabilityHandler = nil
        err.fileHandleForReading.readabilityHandler = nil
        if status != 0 {
            let tail = errorTail.value.split(separator: "\n").suffix(2).joined(separator: " ")
            throw PetalError(tail.isEmpty ? "ffmpeg failed (exit \(status))." : "ffmpeg: \(tail)")
        }
        progress(1)
    }
}

nonisolated final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""
    func append(_ s: String) { lock.lock(); storage += s; lock.unlock() }
    var value: String { lock.lock(); defer { lock.unlock() }; return storage }
}
