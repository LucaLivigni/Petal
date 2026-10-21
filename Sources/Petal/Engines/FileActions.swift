import AppKit
import CryptoKit
import PDFKit

/// The user dismissed a chooser. Not an error; the wheel just closes.
struct UserCancelled: Error {}

/// File actions: sharing, clipboard, moving, terminal, floating shelf. All main-actor, all UI-adjacent.
enum FileActions {
    static func airDrop(_ urls: [URL]) throws -> JobOutcome {
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else {
            throw PetalError("AirDrop isn't available. Turn on Wi‑Fi and Bluetooth.")
        }
        service.perform(withItems: urls)
        return JobOutcome(message: "AirDrop ready")
    }

    static func copy(_ urls: [URL]) -> JobOutcome {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(urls as [NSURL])
        return JobOutcome(message: urls.count == 1 ? "Copied" : "Copied \(urls.count) items")
    }

    static func copyPaths(_ urls: [URL]) -> JobOutcome {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
        return JobOutcome(message: "Path copied")
    }

    static func moveOrCopy(_ urls: [URL], move: Bool) throws -> JobOutcome {
        NSApp.activate()
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move Here" : "Copy Here"
        panel.message = move ? "Choose where to move \(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")" : "Choose where to copy to"
        guard panel.runModal() == .OK, let folder = panel.url else { throw UserCancelled() }

        let policy = OutputPolicy(folder: folder)
        var outputs: [URL] = []
        for url in urls {
            let dest = policy.uniqueURL(in: folder, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
            if move { try FileManager.default.moveItem(at: url, to: dest) } else { try FileManager.default.copyItem(at: url, to: dest) }
            outputs.append(dest)
        }
        return JobOutcome(outputs: outputs, message: "\(move ? "Moved" : "Copied") to \(folder.lastPathComponent)")
    }

    static func openTerminal(_ urls: [URL], bundleID: String) throws -> JobOutcome {
        guard let first = urls.first else { return JobOutcome() }
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir)
        let folder = isDir.boolValue ? first : first.deletingLastPathComponent()
        let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal")
        guard let appURL else { throw PetalError("Terminal isn't installed.") }
        NSWorkspace.shared.open([folder], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        return JobOutcome(message: "Opened in Terminal")
    }

    static func reveal(_ urls: [URL]) -> JobOutcome {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        return JobOutcome(message: "Shown in Finder")
    }

    static func copyText(of url: URL) throws -> JobOutcome {
        let text: String
        switch FileKind.detect(url) {
        case .pdf:
            guard let s = PDFDocument(url: url)?.string, !s.isEmpty else { throw PetalError("This PDF has no selectable text.") }
            text = s
        default:
            text = try TextEngine.load(url).string
        }
        return JobOutcome(message: "Copied \(text.count.formatted()) characters", clipboardText: text)
    }
}

nonisolated enum Checksums {
    static func sha256(of urls: [URL]) throws -> JobOutcome {
        var lines: [String] = []
        for url in urls {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hasher = SHA256()
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
            let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            lines.append(urls.count == 1 ? hex : "\(hex)  \(url.lastPathComponent)")
        }
        return JobOutcome(message: "SHA‑256 copied", clipboardText: lines.joined(separator: "\n"))
    }

    static func totalSize(of urls: [URL]) -> JobOutcome {
        var total: Int64 = 0
        let fm = FileManager.default
        for url in urls {
            if let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                for case let file as URL in walker {
                    let v = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
                }
            }
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true { total += ByteFormat.size(of: url) }
        }
        return JobOutcome(message: ByteFormat.string(total), clipboardText: ByteFormat.string(total))
    }
}
