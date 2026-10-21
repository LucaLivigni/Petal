import AppKit
import SwiftUI

/// A glass panel that hosts SwiftUI content without ever taking focus.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    convenience init(size: NSSize) {
        self.init(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
    }
}

/// After a job finishes, a small card offers the result: drag it out, or reveal it.
@MainActor
final class ResultHUD {
    static let shared = ResultHUD()

    private var panel: HUDPanel?
    private var hideTask: Task<Void, Never>?

    func show(outputs: [URL], message: String, near point: NSPoint) {
        dismiss(animated: false)
        let view = ResultCard(outputs: outputs, message: message, onClose: { [weak self] in self?.dismiss() },
                              onHover: { [weak self] inside in inside ? self?.hideTask?.cancel() : self?.scheduleHide() })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = HUDPanel(size: NSSize(width: size.width + 40, height: size.height + 40))
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: point.x - panel.frame.width / 2, y: point.y - panel.frame.height / 2 - 150)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - panel.frame.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 1
        }
        self.panel = panel
        scheduleHide()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(7))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss(animated: Bool = true) {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        if animated {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { panel.orderOut(nil) } })
        } else {
            panel.orderOut(nil)
        }
    }
}

private struct ResultCard: View {
    var outputs: [URL]
    var message: String
    var onClose: () -> Void
    var onHover: (Bool) -> Void

    @State private var hovering = false

    /// The operation's own message when it has one (e.g. savings), otherwise what was produced.
    private var detail: String {
        guard message.hasPrefix("Saved ") else { return message }
        if outputs.count > 1 { return outputs.map(\.pathExtension).filter { !$0.isEmpty }.first.map { "\($0.uppercased()) files" } ?? "Done" }
        let url = outputs[0]
        let isFolder = FileKind.detect(url) == .folder
        return isFolder ? "Folder" : "\(url.pathExtension.uppercased()) · \(ByteFormat.string(ByteFormat.size(of: url)))"
    }

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
                .onDrag { NSItemProvider(contentsOf: outputs[0]) ?? NSItemProvider() }
                .help("Drag the result anywhere")
            VStack(alignment: .leading, spacing: 2) {
                Text(outputs.count == 1 ? outputs[0].lastPathComponent : "\(outputs.count) files")
                    .font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: 200, alignment: .leading)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting(outputs)
                onClose()
            } label: {
                Text("Show").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Color.petalAccent.gradient, in: Capsule())
            }
            .buttonStyle(.plain)
            Button(action: onClose) { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).opacity(hovering ? 1 : 0.4)
        }
        .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 10)
        .petalGlass(in: Capsule())
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
        .padding(20)
        .onHover { inside in hovering = inside; onHover(inside) }
    }

    private var thumbnail: some View {
        let kind = FileKind.detect(outputs[0])
        return Image(nsImage: WheelModel.thumbnail(for: outputs[0], kind: kind))
            .resizable().scaledToFit().frame(width: 38, height: 38)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
