import Foundation
import UniformTypeIdentifiers

/// Coarse classification of a dropped item. It decides which formats and tools the wheel offers.
nonisolated enum FileKind: String, Sendable, CaseIterable {
    case image, video, audio, pdf, document, slides, spreadsheet, subtitle, archive, folder, other

    static func detect(_ url: URL) -> FileKind {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentTypeKey])
        if values?.isDirectory == true && values?.isPackage != true { return .folder }

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "srt", "vtt": return .subtitle
        case "csv", "tsv", "json", "xlsx", "xlsm", "xls", "ods", "numbers": return .spreadsheet
        case "ppt", "pptx", "pps", "ppsx", "key", "odp": return .slides
        case "md", "markdown", "txt", "rtf", "rtfd", "doc", "docx", "odt", "html", "htm", "webarchive", "epub", "pages", "textclipping": return .document
        case "pdf": return .pdf
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "iso", "cab": return .archive
        case "mkv", "webm", "avi", "wmv", "flv", "m4v", "mp4", "mov", "mpg", "mpeg", "3gp", "ts": return .video
        case "flac", "ogg", "opus", "wma", "aiff", "aif", "caf", "mp3", "m4a", "wav", "aac", "amr", "ac3": return .audio
        case "webp", "avif", "heic", "heif", "jpg", "jpeg", "png", "tif", "tiff", "bmp", "gif", "jp2", "j2k", "svg", "ico", "icns", "psd", "exr", "tga", "dds",
             "cr2", "cr3", "nef", "arw", "dng", "orf", "raf", "rw2", "srw", "pef": return .image
        default: break
        }

        guard let type = values?.contentType ?? UTType(filenameExtension: ext) else { return .other }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .archive) { return .archive }
        if type.conforms(to: .text) || type.conforms(to: .rtf) { return .document }
        return .other
    }

    /// The shared kind of a selection, or `.other` when the selection is mixed.
    static func common(of urls: [URL]) -> FileKind {
        let kinds = Set(urls.map(detect))
        return kinds.count == 1 ? kinds.first! : .other
    }

    var label: String {
        switch self {
        case .image: "Image"
        case .video: "Video"
        case .audio: "Audio"
        case .pdf: "PDF"
        case .document: "Document"
        case .slides: "Presentation"
        case .spreadsheet: "Spreadsheet"
        case .subtitle: "Subtitles"
        case .archive: "Archive"
        case .folder: "Folder"
        case .other: "Files"
        }
    }
}
