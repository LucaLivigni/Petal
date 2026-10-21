import AppKit
import SwiftUI

final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The surface that actually receives the drop and works out which wedge is under the file.
final class WheelDropView: NSView {
    weak var controller: WheelController?
    private let host: NSHostingView<WheelView>

    init(model: WheelModel) {
        host = NSHostingView(rootView: WheelView(model: model))
        super.init(frame: NSRect(origin: .zero, size: WheelGeometry.canvas))
        host.frame = bounds
        host.autoresizingMask = [.width, .height]
        addSubview(host)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { self }

    private func relativePoint(_ sender: any NSDraggingInfo) -> CGPoint {
        let p = convert(sender.draggingLocation, from: nil)
        return CGPoint(x: p.x - bounds.midX, y: p.y - bounds.midY)
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }

    private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { controller?.hover(at: relativePoint(sender)) == true ? .copy : [] }
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        MainActor.assumeIsolated { controller?.setHover(nil) }
    }

    override func draggingEnded(_ sender: any NSDraggingInfo) {
        MainActor.assumeIsolated { controller?.hideSoonIfIdle() }
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        return MainActor.assumeIsolated { controller?.commit(urls: urls) ?? false }
    }
}

@MainActor
final class WheelController {
    let model = WheelModel()
    private let settings: AppSettings
    private let recents: RecentStore
    private let panel: WheelPanel
    private let dropView: WheelDropView
    private var urls: [URL] = []
    private var task: Task<Void, Never>?
    private var demoTimer: Timer?
    private var dwellTimer: Timer?
    private var lastHover: Int?
    private(set) var isVisible = false
    var isBusy: Bool { model.phase != .choosing }

    init(settings: AppSettings, recents: RecentStore) {
        self.settings = settings
        self.recents = recents
        dropView = WheelDropView(model: model)
        panel = WheelPanel(contentRect: NSRect(origin: .zero, size: dropView.frame.size),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.contentView = dropView
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        dropView.controller = self
    }

    // MARK: Showing

    func show(urls: [URL], wheel: PetalAction.Wheel, at mouse: NSPoint) {
        guard !isBusy else { return }
        self.urls = urls
        refreshKeys()
        model.describe(urls)
        let kind = FileKind.common(of: urls)
        let ops = WheelPreferences.shared.arrange(Catalog.operations(for: urls, wheel: wheel), kind: kind, wheel: wheel)
        guard !ops.isEmpty else { return }

        if !isVisible {
            model.configure(wheel: wheel, operations: ops)
            place(at: mouse)
            model.phase = .choosing
            model.activeID = nil
            model.isVisible = false
            panel.orderFrontRegardless()
            isVisible = true
            DispatchQueue.main.async { [model] in model.isVisible = true }
            perform(haptic: .levelChange)
        } else if wheel != model.wheel {
            model.configure(wheel: wheel, operations: ops)
            perform(haptic: .generic)
        }
    }

    func refreshKeys() {
        model.keys = Dictionary(uniqueKeysWithValues: PetalAction.Wheel.allCases.map { ($0, settings.key(for: $0)) })
    }

    private func place(at mouse: NSPoint) {
        let size = panel.frame.size
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        var center = mouse
        model.cardOnTop = false
        if let frame = screen?.visibleFrame {
            let margin = WheelGeometry.disc * settings.wheelSize.scale + 24
            center.x = min(max(center.x, frame.minX + margin), frame.maxX - margin)
            center.y = min(max(center.y, frame.minY + margin), frame.maxY - margin)
            // The information card goes below the ring unless that would run off the screen.
            model.cardOnTop = center.y - frame.minY < WheelGeometry.disc * settings.wheelSize.scale + 160
        }
        panel.setFrameOrigin(NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2))
    }

    func hide(force: Bool = false) {
        guard isVisible, force || !isBusy else { return }
        demoTimer?.invalidate(); dwellTimer?.invalidate()
        isVisible = false
        model.isVisible = false
        model.hovered = nil
        let panel = self.panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
            guard self?.isVisible == false else { return }
            panel.orderOut(nil)
            self?.model.phase = .choosing
            self?.model.activeID = nil
        }
    }

    func hideSoonIfIdle() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self, !self.isBusy else { return }
            self.hide()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        hide(force: true)
    }

    // MARK: Hovering

    @discardableResult
    func hover(at point: CGPoint) -> Bool {
        let slot = WheelGeometry.slot(at: point, count: model.slots.count, scale: settings.wheelSize.scale)
        setHover(slot)
        return slot != nil
    }

    func setHover(_ slot: Int?) {
        guard model.phase == .choosing, slot != lastHover else { return }
        lastHover = slot
        model.hovered = slot
        dwellTimer?.invalidate()
        guard let slot else { return }
        perform(haptic: .alignment)
        if case .more(let next) = model.slots[slot] {
            // Dwelling on "more" flips to the next page, like turning the wheel over.
            dwellTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.model.hovered == slot else { return }
                    self.model.page = next
                    self.model.hovered = nil
                    self.lastHover = nil
                }
            }
        }
    }

    private func perform(haptic: NSHapticFeedbackManager.FeedbackPattern) {
        guard settings.haptics else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(haptic, performanceTime: .now)
    }

    // MARK: Running

    func commit(urls dropped: [URL]) -> Bool {
        guard let hovered = model.hovered, model.slots.indices.contains(hovered) else { return false }
        switch model.slots[hovered] {
        case .more(let next):
            model.page = next
            return false
        case .op(let operation):
            let inputs = dropped.isEmpty ? urls : dropped
            run(operation, on: inputs)
            return true
        }
    }

    private func run(_ operation: PetalAction, on inputs: [URL]) {
        model.activeID = operation.id
        model.phase = .running(title: operation.title, progress: 0)
        perform(haptic: .levelChange)
        let model = self.model
        let context = JobContext(
            inputs: inputs,
            policy: settings.outputPolicy,
            imageQuality: settings.imageQuality,
            terminalBundleID: settings.terminalBundleID,
            progress: { value in
                Task { @MainActor in
                    if case .running(let title, _) = model.phase { model.phase = .running(title: title, progress: value) }
                }
            }
        )
        task = Task { [weak self] in
            do {
                let outcome = try await operation.perform(context)
                self?.finish(operation: operation, outcome: outcome)
            } catch is UserCancelled {
                self?.hide(force: true)
            } catch is CancellationError {
                self?.hide(force: true)
            } catch {
                self?.fail(error)
            }
        }
    }

    private func finish(operation: PetalAction, outcome: JobOutcome) {
        if let text = outcome.clipboardText {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
        let message = outcome.message ?? Self.defaultMessage(for: outcome.outputs, operation: operation)
        model.phase = .success(message)
        if settings.sounds { NSSound(named: "Tink")?.play() }
        perform(haptic: .generic)
        if !outcome.outputs.isEmpty { recents.add(outcome.outputs, title: operation.title) }
        WheelPreferences.shared.record(kind: FileKind.common(of: urls), wheel: model.wheel, id: operation.id)
        PracticeCoordinator.shared.jobFinished(inputs: urls, outputs: outcome.outputs, title: operation.title)

        let outputs = outcome.outputs
        let anchor = panel.frame
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak self] in
            guard let self else { return }
            self.hide(force: true)
            if !outputs.isEmpty {
                if self.settings.revealAfter { NSWorkspace.shared.activateFileViewerSelecting(outputs) }
                ResultHUD.shared.show(outputs: outputs, message: message, near: NSPoint(x: anchor.midX, y: anchor.midY))
            }
        }
    }

    private func fail(_ error: Error) {
        model.phase = .failure(error.localizedDescription)
        if settings.sounds { NSSound(named: "Basso")?.play() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in self?.hide(force: true) }
    }

    private static func defaultMessage(for outputs: [URL], operation: PetalAction) -> String {
        switch outputs.count {
        case 0: "Done"
        case 1: "Saved \(outputs[0].lastPathComponent)"
        default: "Saved \(outputs.count) files"
        }
    }

    // MARK: Demo

    /// Shows a non-functional wheel that sweeps its options. Used for previews and screenshots.
    func showDemo(wheel: PetalAction.Wheel = .convert, at point: NSPoint? = nil) {
        let mouse = point ?? NSPoint(x: NSScreen.main?.frame.midX ?? 600, y: NSScreen.main?.frame.midY ?? 400)
        model.loadDemo(wheel: wheel)
        urls = model.urls
        place(at: mouse)
        model.phase = .choosing
        model.isVisible = false
        panel.orderFrontRegardless()
        isVisible = true
        DispatchQueue.main.async { [model] in model.isVisible = true }

        var step = 0
        demoTimer?.invalidate()
        demoTimer = Timer.scheduledTimer(withTimeInterval: 1.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                step += 1
                if step % 10 == 0 {
                    let all = PetalAction.Wheel.allCases
                    let next = all[(all.firstIndex(of: self.model.wheel)! + 1) % all.count]
                    self.model.loadDemo(wheel: next)
                }
                self.model.hovered = step % max(1, self.model.slots.count)
            }
        }
    }

    #if DEBUG
    /// Simulates dropping `urls` on the wedge with `id`. Used by `--run <id> <path>` for end-to-end checks.
    func debugRun(id: String, urls: [URL]) {
        let wheel = PetalAction.Wheel(rawValue: String(id.split(separator: ".").first ?? "convert")) ?? .convert
        let screen = NSScreen.main?.frame ?? .zero
        show(urls: urls, wheel: wheel, at: NSPoint(x: screen.midX, y: screen.midY))
        guard let index = model.slots.firstIndex(where: { $0.id == id }) else { NSLog("debugRun: no slot \(id)"); return }
        model.hovered = index
        _ = commit(urls: urls)
    }
    #endif
}
