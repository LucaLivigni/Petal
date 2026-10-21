import SwiftUI

struct OnboardingView: View {
    var finish: () -> Void

    @State private var step = OnboardingView.startStep

    private static var startStep: Int {
        #if DEBUG
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--step=") }), let n = Int(arg.dropFirst(7)) { return n }
        #endif
        return 0
    }
    private var settings = AppSettings.shared

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch step {
                case 0: welcome.transition(slide)
                case 1: PracticePage().transition(slide)
                default: ready.transition(slide)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: step)

            footer
        }
        .background { background }
        .onChange(of: step) { _, new in PracticeCoordinator.shared.isActive = (new == 1) }
        .onDisappear { PracticeCoordinator.shared.isActive = false }
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity))
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(colors: [Color.petalAccent.opacity(0.22), .clear], center: .init(x: 0.5, y: 0.18), startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 6) {
            DemoWheelView(showsDetails: false, scale: 0.9)
                .padding(.top, 14)
            Text("Meet Petal").font(.system(size: 34, weight: .bold, design: .rounded))
            Text("Convert, shrink and share files without opening an app.\nJust drag a file and tap a key.")
                .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private var ready: some View {
        VStack(spacing: 22) {
            Text("Three wheels, one gesture").font(.system(size: 30, weight: .bold, design: .rounded)).padding(.top, 40)
            VStack(spacing: 12) {
                ForEach(PetalAction.Wheel.allCases) { wheel in
                    HStack(spacing: 14) {
                        Text(settings.key(for: wheel).symbol).font(.system(size: 22, weight: .semibold, design: .rounded))
                            .frame(width: 52, height: 52)
                            .background(Color.petalAccent.gradient.opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(.white)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(wheel.title).font(.headline)
                            Text(blurb(wheel)).font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .petalGlass(in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .padding(.horizontal, 44)
            Text("Petal lives in the menu bar and needs no special permissions. Start dragging a file, tap the key, then drop on a wedge. The result lands next to the original.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 56)
            Spacer()
        }
    }

    private func blurb(_ wheel: PetalAction.Wheel) -> String {
        switch wheel {
        case .convert: "Turn it into another format"
        case .tools: "Compress, resize, cut out, merge and more"
        case .actions: "AirDrop, copy, move, open in Terminal"
        }
    }

    // MARK: Footer

    private var continueTitle: String {
        switch step {
        case 0: "Try It"
        case 1: { if case .done = PracticeCoordinator.shared.step { "Continue" } else { "Skip" } }()
        default: "Start Using Petal"
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 7) {
                ForEach(0..<3) { i in
                    Capsule().fill(i == step ? Color.petalAccent : Color.secondary.opacity(0.3))
                        .frame(width: i == step ? 22 : 7, height: 7)
                }
            }
            .animation(.snappy, value: step)
            Spacer()
            if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 8) }
            Button {
                if step < 2 { step += 1 } else { finish() }
            } label: {
                Text(continueTitle).font(.headline)
            }
            .buttonStyle(PetalButtonStyle())
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 32).padding(.vertical, 22)
    }
}


// MARK: - Practice

/// The "try it" page: a real picture to drag out of the window, with hints that follow what you do.
private struct PracticePage: View {
    private let practice = PracticeCoordinator.shared
    private let settings = AppSettings.shared
    @State private var bob = false

    private var key: String { settings.convertKey.symbol }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text("Now you try").font(.system(size: 30, weight: .bold, design: .rounded))
                Text("Drag this picture out of the window, tap \(key), and drop it on a format.")
                    .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            }
            .padding(.top, 36)

            stage
                .frame(height: 270)
                .padding(.horizontal, 44)

            progress

            if let hint = practice.hint {
                Text(hint).font(.callout).foregroundStyle(.orange).multilineTextAlignment(.center).padding(.horizontal, 56)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: practice.step)
        .animation(.easeOut(duration: 0.2), value: practice.hint)
        .onAppear { practice.isActive = true; withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { bob = true } }
    }

    // MARK: Stage

    @ViewBuilder
    private var stage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(.clear)
                .petalGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            switch practice.step {
            case .idle:
                VStack(spacing: 14) {
                    if let url = practice.sample {
                        DraggableFile(url: url, image: WheelModel.thumbnail(for: url, kind: .image))
                            .frame(width: 210, height: 150)
                    }
                    Label("Drag me out of this window", systemImage: "hand.draw")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                        .offset(y: bob ? -2 : 2)
                }
            case .dragging:
                VStack(spacing: 16) {
                    keyCap(key)
                    Text("Tap \(settings.convertKey.name) now").font(.system(size: 20, weight: .semibold))
                    Text("Keep holding the picture with the mouse.").font(.callout).foregroundStyle(.secondary)
                }
            case .wheelOpen:
                VStack(spacing: 12) {
                    Image(systemName: "arrow.down.to.line.compact").font(.system(size: 34, weight: .light)).foregroundStyle(Color.petalAccent)
                        .offset(y: bob ? 4 : -4)
                    Text("Drop it on a format").font(.system(size: 20, weight: .semibold))
                    Text("The result is saved next to the original.").font(.callout).foregroundStyle(.secondary)
                }
            case .done(let output, let title):
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.green).symbolEffect(.bounce, value: output)
                    Text("That's it").font(.system(size: 22, weight: .bold, design: .rounded))
                    Text("\(title) → \(output.lastPathComponent)").font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    HStack(spacing: 10) {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([output]) }
                            .buttonStyle(PetalButtonStyle())
                        Button("Try again") { practice.newSample() }
                            .buttonStyle(.plain).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private func keyCap(_ symbol: String) -> some View {
        Text(symbol)
            .font(.system(size: 44, weight: .medium)).foregroundStyle(.white)
            .frame(width: 92, height: 92)
            .background(Color.petalAccent, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.petalAccent.opacity(0.5), radius: bob ? 22 : 8)
            .scaleEffect(bob ? 1.05 : 0.97)
    }

    // MARK: Progress

    private var progress: some View {
        let state = stepIndex
        return HStack(spacing: 10) {
            ForEach(Array(["Drag", "Tap \(key)", "Drop"].enumerated()), id: \.offset) { i, title in
                HStack(spacing: 6) {
                    ZStack {
                        Circle().fill(i < state ? Color.green : (i == state ? Color.petalAccent : Color.secondary.opacity(0.25)))
                        if i < state { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white) }
                        else { Text("\(i + 1)").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) }
                    }
                    .frame(width: 18, height: 18)
                    Text(title).font(.system(size: 12, weight: i == state ? .semibold : .regular)).foregroundStyle(i <= state ? .primary : .secondary)
                }
                if i < 2 { Rectangle().fill(.secondary.opacity(0.25)).frame(width: 22, height: 1) }
            }
        }
    }

    /// 0 = waiting for the drag, 1 = waiting for the key, 2 = waiting for the drop, 3 = finished.
    private var stepIndex: Int {
        switch practice.step {
        case .idle: 0
        case .dragging: 1
        case .wheelOpen: 2
        case .done: 3
        }
    }
}
