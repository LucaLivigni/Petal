import AppKit
import SwiftUI

/// "Float" action: keeps files on screen above every window, ready to drag into any app.
@MainActor
final class FloatingShelf {
    static let shared = FloatingShelf()

    private var panels: [UUID: HUDPanel] = [:]
    private var cascade = 0

    func add(_ urls: [URL]) {
        let id = UUID()
        let view = ShelfCard(urls: urls, close: { [weak self] in self?.remove(id) })
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let panel = HUDPanel(size: NSSize(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = host
        let visible = NSScreen.main?.visibleFrame ?? .zero
        panel.setFrameOrigin(NSPoint(x: visible.maxX - panel.frame.width - 24 - CGFloat(cascade % 4) * 24,
                                     y: visible.maxY - panel.frame.height - 24 - CGFloat(cascade % 4) * 24))
        cascade += 1
        panel.orderFrontRegardless()
        panels[id] = panel
    }

    private func remove(_ id: UUID) {
        panels[id]?.orderOut(nil)
        panels[id] = nil
    }
}

private struct ShelfCard: View {
    var urls: [URL]
    var close: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    ForEach(Array(urls.prefix(3).enumerated().reversed()), id: \.offset) { i, url in
                        Image(nsImage: WheelModel.thumbnail(for: url, kind: FileKind.detect(url)))
                            .resizable().scaledToFit().frame(width: 84, height: 84)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                            .rotationEffect(.degrees(Double(i) * 4 - (urls.count > 1 ? 4 : 0)))
                            .offset(x: CGFloat(i) * 4, y: CGFloat(i) * -3)
                    }
                }
                .frame(width: 100, height: 100)
                .onDrag { NSItemProvider(contentsOf: urls[0]) ?? NSItemProvider() }

                Button(action: close) {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.55))
                }
                .buttonStyle(.plain).opacity(hovering ? 1 : 0).offset(x: 6, y: -6)
            }
            Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items")
                .font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.middle).frame(maxWidth: 110)
        }
        .padding(14)
        .petalGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 16, y: 8)
        .padding(20)
        .onHover { hovering = $0 }
        .animation(.snappy(duration: 0.2), value: hovering)
    }
}
