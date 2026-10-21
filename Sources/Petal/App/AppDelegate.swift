import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private let settings = AppSettings.shared
    private let recents = RecentStore.shared
    private lazy var wheel = WheelController(settings: settings, recents: recents)
    private lazy var monitor = DragMonitor(settings: settings)
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()
        wireMonitor()
        monitor.start()

        let args = CommandLine.arguments
        if args.contains("--demo") {
            wheel.showDemo(wheel: args.contains("--tools") ? .tools : args.contains("--actions") ? .actions : .convert)
        }
        #if DEBUG
        if let i = args.firstIndex(of: "--edit"), args.count > i + 1 {
            let tab = args.first { $0.hasPrefix("--tab=") }.flatMap { PhotoEditorModel.Tab(rawValue: String($0.dropFirst(6)).capitalized) } ?? .crop
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { try? EditorWindows.shared.openPhoto(URL(fileURLWithPath: args[i + 1]), tab: tab) }
        }
        if let i = args.firstIndex(of: "--trim"), args.count > i + 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { EditorWindows.shared.openTrim(URL(fileURLWithPath: args[i + 1])) }
        }
        if let i = args.firstIndex(of: "--run"), args.count > i + 2 {
            let id = args[i + 1], paths = Array(args[(i + 2)...].filter { !$0.hasPrefix("--") })
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.wheel.debugRun(id: id, urls: paths.map { URL(fileURLWithPath: $0) })
            }
        }
        #endif
        if args.contains("--settings") { showSettings() }
        if !settings.hasOnboarded || args.contains("--onboarding") { showOnboarding() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Opening Petal again (Finder, Spotlight, Dock) shows the settings instead of doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    // MARK: Drag wiring

    private func debugLog(_ text: String) {
        #if DEBUG
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(text)\n"
        let url = URL(fileURLWithPath: "/tmp/petal-debug.log")
        if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data(line.utf8)); try? handle.close() }
        else { try? line.write(to: url, atomically: true, encoding: .utf8) }
        #endif
    }

    private func wireMonitor() {
        monitor.onDragStart = { [weak self] urls in
            self?.debugLog("drag started: \(urls.map(\.lastPathComponent))")
            PracticeCoordinator.shared.dragStarted(urls)
        }
        monitor.onTrigger = { [weak self] wheel, point in
            guard let self else { return }
            self.debugLog("trigger \(wheel.rawValue) at \(Int(point.x)),\(Int(point.y))")
            PracticeCoordinator.shared.wheelOpened(wheel)
            self.wheel.show(urls: self.monitor.dragURLs, wheel: wheel, at: point)
        }
        monitor.onDragEnd = { [weak self] in
            self?.debugLog("drag ended")
            self?.wheel.hideSoonIfIdle()
            // Give a drop that landed on a wedge time to start its job before deciding the attempt was abandoned.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if self?.wheel.isBusy != true { PracticeCoordinator.shared.dragEnded() } }
        }
        monitor.onEscape = { [weak self] in self?.wheel.cancel() }
    }

    // MARK: Status item

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.statusImage()
        item.button?.toolTip = "Petal"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let convert = settings.convertKey.symbol
        let header = NSMenuItem(title: settings.paused ? "Petal is paused" : "Drag a file, then tap \(convert)", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        if let last = monitor.lastDrag {
            let seen = NSMenuItem(title: "Last drag seen: \(last)", action: nil, keyEquivalent: "")
            seen.isEnabled = false
            menu.addItem(seen)
        }
        menu.addItem(.separator())

        let pause = NSMenuItem(title: settings.paused ? "Resume" : "Pause", action: #selector(togglePause), keyEquivalent: "")
        pause.target = self
        menu.addItem(pause)

        let recent = NSMenuItem(title: "Recent", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        if recents.items.isEmpty {
            let empty = NSMenuItem(title: "Nothing yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        } else {
            for item in recents.items {
                let entry = NSMenuItem(title: item.url.lastPathComponent, action: #selector(revealRecent(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = item.url
                entry.image = NSWorkspace.shared.icon(forFile: item.url.path).resized(to: 16)
                submenu.addItem(entry)
            }
        }
        recent.submenu = submenu
        menu.addItem(recent)
        menu.addItem(.separator())

        let demo = NSMenuItem(title: "Preview the Wheel", action: #selector(previewWheel), keyEquivalent: "")
        demo.target = self
        menu.addItem(demo)
        let welcome = NSMenuItem(title: "Welcome Guide…", action: #selector(showOnboardingAction), keyEquivalent: "")
        welcome.target = self
        menu.addItem(welcome)
        let prefs = NSMenuItem(title: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Petal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func togglePause() { settings.paused.toggle() }
    @objc private func revealRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
    @objc private func previewWheel() {
        let screen = NSScreen.main?.frame ?? .zero
        wheel.showDemo(at: NSPoint(x: screen.midX, y: screen.midY))
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.wheel.hide(force: true) }
    }
    @objc private func showSettingsAction() { showSettings() }
    @objc private func showOnboardingAction() { showOnboarding() }

    // MARK: Windows

    func showSettings() {
        if settingsWindow == nil {
            let window = makeWindow(size: NSSize(width: 780, height: 560), title: "Petal Settings", content: SettingsView())
            window.minSize = NSSize(width: 680, height: 480)
            settingsWindow = window
        }
        present(settingsWindow!)
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            let view = OnboardingView(finish: { [weak self] in
                self?.settings.hasOnboarded = true
                self?.onboardingWindow?.close()
            })
            let window = makeWindow(size: NSSize(width: 620, height: 700), title: "Welcome to Petal", content: view)
            window.styleMask.remove(.resizable)
            onboardingWindow = window
        }
        present(onboardingWindow!)
    }

    private func makeWindow<V: View>(size: NSSize, title: String, content: V) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: content)
        window.setContentSize(size)
        window.center()
        window.delegate = self
        return window
    }

    private func present(_ window: NSWindow) {
        AppPresence.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === onboardingWindow { settings.hasOnboarded = true }
        DispatchQueue.main.async { AppPresence.update() }
    }

    // MARK: Status icon

    private static func statusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let c = NSPoint(x: rect.midX, y: rect.midY)
            NSColor.black.setFill()
            for i in 0..<6 {
                let petal = NSBezierPath(roundedRect: NSRect(x: -2.3, y: 2.6, width: 4.6, height: 6.2), xRadius: 2.3, yRadius: 2.3)
                var t = AffineTransform(translationByX: c.x, byY: c.y)
                t.rotate(byDegrees: CGFloat(i) * 60)
                petal.transform(using: t)
                petal.fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension NSImage {
    func resized(to side: CGFloat) -> NSImage {
        let copy = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            self.draw(in: rect)
            return true
        }
        return copy
    }
}
