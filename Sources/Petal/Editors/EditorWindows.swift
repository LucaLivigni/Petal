import AppKit
import SwiftUI

/// Keeps Petal a menu-bar app until a window is open, then lets it show in the Dock and the app switcher.
@MainActor
enum AppPresence {
    static func update() {
        let visible = NSApp.windows.contains { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
        NSApp.setActivationPolicy(visible ? .regular : .accessory)
    }

    static func activate() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }
}

/// Opens the editor windows (photo and trim) and cleans up after them.
@MainActor
final class EditorWindows: NSObject, NSWindowDelegate {
    static let shared = EditorWindows()

    private var cleanups: [ObjectIdentifier: () -> Void] = [:]
    private var cascade: CGFloat = 0

    func openPhoto(_ url: URL, tab: PhotoEditorModel.Tab = .crop) throws {
        let model = try PhotoEditorModel(source: url, tab: tab)
        var window: NSWindow?
        let view = PhotoEditorView(model: model, close: { window?.close() })
        window = makeWindow(title: url.lastPathComponent, size: NSSize(width: 1040, height: 720), minSize: NSSize(width: 860, height: 600), content: view)
        present(window!)
    }

    func openTrim(_ url: URL) {
        let model = TrimModel(url: url)
        var window: NSWindow?
        let view = TrimEditorView(model: model, close: { window?.close() })
        window = makeWindow(title: "Trim · \(url.lastPathComponent)", size: NSSize(width: 860, height: model.isVideo ? 700 : 440),
                            minSize: NSSize(width: 640, height: model.isVideo ? 560 : 400), content: view)
        cleanups[ObjectIdentifier(window!)] = { model.tearDown() }
        present(window!)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, minSize: NSSize, content: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = minSize
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        if cascade > 0 { window.setFrameOrigin(NSPoint(x: window.frame.minX + cascade, y: window.frame.minY - cascade)) }
        cascade = cascade >= 90 ? 0 : cascade + 30
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow) {
        AppPresence.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            cleanups.removeValue(forKey: ObjectIdentifier(window))?()
        }
        DispatchQueue.main.async { AppPresence.update() }
    }
}
