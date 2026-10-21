import AppKit

/// Detects a file being dragged anywhere on screen and the modifier tap that summons a wheel.
///
/// While a drag session is running macOS stops delivering mouse events to other apps, so a global
/// `leftMouseDragged` monitor never sees the interesting part. Instead, a mouse-down starts a light
/// 60 Hz poll that watches the drag pasteboard, the modifier keys and the mouse button until release.
/// Everything here works without Accessibility or Input Monitoring permission.
@MainActor
final class DragMonitor {
    var onDragStart: (([URL]) -> Void)?
    var onTrigger: ((PetalAction.Wheel, NSPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onEscape: (() -> Void)?

    private let settings: AppSettings
    private var tokens: [Any] = []
    private var pollTimer: Timer?
    private var pasteboardCount = 0
    private var lastFlags: NSEvent.ModifierFlags = []
    private var releasedPolls = 0
    private(set) var isFileDrag = false
    private(set) var dragURLs: [URL] = []
    private(set) var lastDrag: String?

    init(settings: AppSettings) { self.settings = settings }

    func start() {
        stop()
        let global = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.mouseDown() }
            return event
        }
        tokens = [global, local].compactMap { $0 }
    }

    func stop() {
        tokens.forEach(NSEvent.removeMonitor)
        tokens = []
        isFileDrag = false
        stopPolling()
    }

    // MARK: Polling

    private func mouseDown() {
        pasteboardCount = NSPasteboard(name: .drag).changeCount
        isFileDrag = false
        releasedPolls = 0
        lastFlags = Self.currentFlags()
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private static func currentFlags() -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(CGEventSource.flagsState(.combinedSessionState).rawValue))
    }

    /// Hardware button state. `NSEvent.pressedMouseButtons` flickers while a drag session is running.
    private static var leftButtonDown: Bool {
        CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    private func poll() {
        guard Self.leftButtonDown else {
            releasedPolls += 1
            if releasedPolls >= 3 { endDrag(); stopPolling() }   // ~50 ms of confirmed release
            return
        }
        releasedPolls = 0

        if !isFileDrag {
            let board = NSPasteboard(name: .drag)
            guard board.changeCount != pasteboardCount else { return }
            pasteboardCount = board.changeCount
            let urls = (board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
            guard !urls.isEmpty else { return }
            isFileDrag = true
            dragURLs = urls
            lastDrag = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
            lastFlags = Self.currentFlags()
            onDragStart?(urls)
            return
        }

        if CGEventSource.keyState(.combinedSessionState, key: 0x35) { onEscape?(); return }
        let flags = Self.currentFlags()
        defer { lastFlags = flags }
        guard flags != lastFlags, !settings.paused, let wheel = settings.wheel(for: flags) else { return }
        onTrigger?(wheel, NSEvent.mouseLocation)
    }

    private func endDrag() {
        guard isFileDrag else { return }
        isFileDrag = false
        onDragEnd?()
    }
}
