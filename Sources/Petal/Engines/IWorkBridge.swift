import AppKit

/// Uses Keynote, Pages and Numbers (free from the App Store) for formats macOS can't read or write itself:
/// PPT/PPTX slides, Pages documents, legacy XLS. Petal drives them through AppleScript, in the background.
nonisolated enum IWorkBridge {
    enum App: String, Sendable {
        case keynote = "com.apple.iWork.Keynote"
        case pages = "com.apple.iWork.Pages"
        case numbers = "com.apple.iWork.Numbers"

        var name: String {
            switch self {
            case .keynote: "Keynote"
            case .pages: "Pages"
            case .numbers: "Numbers"
            }
        }
    }

    static func isInstalled(_ app: App) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.rawValue) != nil
    }

    private static func q(_ path: String) -> String {
        "\"" + path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    @discardableResult
    static func run(_ script: String, app: App) async throws -> String {
        let result = try await ProcessRunner.run(URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", script])
        guard result.status == 0 else {
            if result.error.contains("-1743") || result.error.contains("not allowed") {
                throw PetalError("Allow Petal to control \(app.name): System Settings → Privacy & Security → Automation.")
            }
            let detail = result.error.split(separator: "\n").last.map(String.init) ?? "unknown error"
            throw PetalError("\(app.name) couldn't convert this file (\(detail)).")
        }
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Keynote (slides)

    static func slidesToPDF(_ src: URL, to dest: URL) async throws {
        try await run("""
        tell application "Keynote"
            set theDoc to open POSIX file \(q(src.path))
            export theDoc to POSIX file \(q(dest.path)) as PDF
            close theDoc saving no
        end tell
        """, app: .keynote)
    }

    /// Exports every slide as an image into `folder` (which must exist). `format` is "PNG" or "JPEG".
    static func slidesToImages(_ src: URL, folder: URL, format: String) async throws {
        try await run("""
        tell application "Keynote"
            set theDoc to open POSIX file \(q(src.path))
            export theDoc to POSIX file \(q(folder.path)) as slide images with properties {image format:\(format), skipped slides:false}
            close theDoc saving no
        end tell
        """, app: .keynote)
    }

    // MARK: Pages (documents)

    enum PagesFormat: String, Sendable {
        case pdf = "PDF", word = "Microsoft Word", epub = "EPUB", text = "unformatted text"
    }

    static func pagesExport(_ src: URL, as format: PagesFormat, to dest: URL) async throws {
        try await run("""
        tell application "Pages"
            set theDoc to open POSIX file \(q(src.path))
            export theDoc to POSIX file \(q(dest.path)) as \(format.rawValue)
            close theDoc saving no
        end tell
        """, app: .pages)
    }

    /// Opens a DOCX/RTF/TXT in Pages and saves it as a native .pages file.
    static func saveAsPages(_ src: URL, to dest: URL) async throws {
        try await run("""
        tell application "Pages"
            set theDoc to open POSIX file \(q(src.path))
            save theDoc in POSIX file \(q(dest.path))
            close theDoc saving no
        end tell
        """, app: .pages)
    }

    // MARK: Numbers (spreadsheets)

    enum NumbersFormat: String, Sendable {
        case pdf = "PDF", excel = "Microsoft Excel", csv = "CSV"
    }

    static func numbersExport(_ src: URL, as format: NumbersFormat, to dest: URL) async throws {
        try await run("""
        tell application "Numbers"
            set theDoc to open POSIX file \(q(src.path))
            export theDoc to POSIX file \(q(dest.path)) as \(format.rawValue)
            close theDoc saving no
        end tell
        """, app: .numbers)
    }

    /// Reads an XLS or Numbers file by letting Numbers convert it to XLSX first.
    static func rowsViaNumbers(_ src: URL) async throws -> [[String]] {
        guard isInstalled(.numbers) else { throw PetalError("Reading .\(src.pathExtension) files needs Numbers (free on the App Store).") }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("petal-\(UUID().uuidString).xlsx")
        defer { try? FileManager.default.removeItem(at: temp) }
        try await numbersExport(src, as: .excel, to: temp)
        return try await SpreadsheetEngine.readXLSX(temp)
    }
}
