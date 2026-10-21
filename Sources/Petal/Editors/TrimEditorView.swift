import AVKit
import SwiftUI

struct TrimEditorView: View {
    var model: TrimModel
    var close: () -> Void

    private let settings = AppSettings.shared
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            stage
            Divider()
            controls
            Divider()
            footer
        }
        .tint(Color.petalAccent)
        .background(.background)
        .task { await model.load() }
        .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: Preview

    private var stage: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            if model.isVideo {
                PlayerSurface(player: model.player)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
                    .padding(20)
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "waveform").font(.system(size: 54, weight: .ultraLight)).foregroundStyle(Color.petalAccent)
                    Text(model.url.lastPathComponent).font(.system(size: 15, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    Text("Total \(TrimModel.clock(model.duration))").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if !model.isLoaded { ProgressView().controlSize(.large) }
        }
        .frame(minHeight: model.isVideo ? 320 : 150, maxHeight: .infinity)
    }

    // MARK: Timeline and buttons

    private var controls: some View {
        VStack(spacing: 14) {
            Timeline(model: model).frame(height: 66)
            HStack(spacing: 14) {
                Button { model.togglePlay() } label: {
                    Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
                }
                .keyboardShortcut(.space, modifiers: []).help("Play the selection (Space)")
                Button("Set start here") { model.setStart(model.playhead) }.keyboardShortcut("i", modifiers: []).help("I")
                Button("Set end here") { model.setEnd(model.playhead) }.keyboardShortcut("o", modifiers: []).help("O")
                Spacer()
                readout("Start", model.start)
                readout("End", model.end)
                readout("Length", model.selectionLength, emphasised: true)
            }
            if model.isVideo {
                Toggle(isOn: Bindable(model).fast) {
                    Text("Fast cut (no re-encoding)").font(.system(size: 12))
                }
                .toggleStyle(.checkbox).frame(maxWidth: .infinity, alignment: .leading)
                .help("Instant, but the cut snaps to the nearest keyframe.")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private func readout(_ title: String, _ value: Double, emphasised: Bool = false) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase)
            Text(TrimModel.clock(value)).font(.system(size: 14, weight: emphasised ? .semibold : .regular)).monospacedDigit()
                .foregroundStyle(emphasised ? Color.petalAccent : Color.primary)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let progress = model.exportProgress {
                ProgressView(value: progress).frame(width: 180)
                Text("Saving…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
            Button("Save a Copy") { save() }
                .buttonStyle(PetalButtonStyle()).keyboardShortcut(.defaultAction)
                .disabled(!model.isLoaded || !model.isTrimmed || model.exportProgress != nil)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func save() {
        Task {
            do {
                let url = try await model.export(policy: settings.outputPolicy)
                RecentStore.shared.add([url], title: "Trim")
                close()
                let screen = NSScreen.main?.visibleFrame ?? .zero
                ResultHUD.shared.show(outputs: [url], message: "Saved \(url.lastPathComponent)", near: NSPoint(x: screen.midX, y: screen.midY + 160))
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}

private struct PlayerSurface: NSViewRepresentable {
    var player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) {}
}

// MARK: - Timeline

private struct Timeline: View {
    var model: TrimModel

    @State private var dragging: Drag?
    private enum Drag { case start, end, playhead }
    private let handle: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width, height = proxy.size.height
            let usable = max(1, width - handle * 2)
            let x = { (t: Double) -> CGFloat in handle + CGFloat(t / max(model.duration, 0.001)) * usable }
            ZStack(alignment: .leading) {
                strip(width: usable, height: height).frame(width: usable, height: height).offset(x: handle)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous)).offset(x: 0)
                    .frame(width: width, alignment: .leading)

                // Dim what will be cut away.
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, x(model.start) - handle), height: height).offset(x: handle)
                Rectangle().fill(.black.opacity(0.55)).frame(width: max(0, width - handle - x(model.end)), height: height).offset(x: x(model.end))

                // Selection frame and handles
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.petalAccent, lineWidth: 3)
                    .frame(width: max(2, x(model.end) - x(model.start) + handle * 2), height: height)
                    .offset(x: x(model.start) - handle)
                handleView(left: true).offset(x: x(model.start) - handle)
                handleView(left: false).offset(x: x(model.end))

                // Playhead
                Capsule().fill(.white).frame(width: 3, height: height + 8).shadow(color: .black.opacity(0.5), radius: 2)
                    .offset(x: x(model.playhead) - 1.5, y: 0)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let t = { (px: CGFloat) -> Double in Double((px - handle) / usable) * model.duration }
                        if dragging == nil {
                            let sx = value.startLocation.x
                            if abs(sx - x(model.start)) < handle + 4 && abs(sx - x(model.start)) <= abs(sx - x(model.end)) { dragging = .start }
                            else if abs(sx - x(model.end)) < handle + 4 { dragging = .end }
                            else { dragging = .playhead }
                        }
                        switch dragging {
                        case .start: model.setStart(t(value.location.x))
                        case .end: model.setEnd(t(value.location.x))
                        default: model.seek(to: min(max(model.start, t(value.location.x)), model.end))
                        }
                    }
                    .onEnded { _ in dragging = nil }
            )
        }
    }

    @ViewBuilder
    private func strip(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            Rectangle().fill(Color.primary.opacity(0.08))
            if !model.thumbnails.isEmpty {
                HStack(spacing: 0) {
                    ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                        Image(decorative: image, scale: 1).resizable().scaledToFill()
                            .frame(width: width / CGFloat(model.thumbnails.count), height: height).clipped()
                    }
                }
            } else if !model.waveform.isEmpty {
                HStack(alignment: .center, spacing: 1) {
                    ForEach(Array(model.waveform.enumerated()), id: \.offset) { _, level in
                        Capsule().fill(Color.petalAccent.opacity(0.85)).frame(height: max(3, CGFloat(level) * (height - 14)))
                    }
                }
                .padding(.horizontal, 3)
            }
        }
    }

    private func handleView(left: Bool) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: left ? 6 : 0, bottomLeadingRadius: left ? 6 : 0, bottomTrailingRadius: left ? 0 : 6, topTrailingRadius: left ? 0 : 6)
            .fill(Color.petalAccent)
            .frame(width: handle, height: 66)
            .overlay(Capsule().fill(.white.opacity(0.9)).frame(width: 3, height: 22))
    }
}
