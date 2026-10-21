import SwiftUI

extension View {
    /// Liquid Glass where available, a blurred material otherwise. The shape is filled clear first so the
    /// glass has something to wrap; content should be layered above it, never inside it.
    @ViewBuilder
    func petalGlass<S: Shape>(in shape: S, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.14), lineWidth: 0.8))
                .overlay(tint.map { shape.fill($0.opacity(0.45)) })
        }
    }
}

extension Color {
    /// The accent chosen in Settings. Reading it inside a view body makes the view follow changes.
    static var petalAccent: Color { AppSettings.shared.accent.color }
}

/// A glass container on macOS 26, a plain group before that.
private struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Wheel

struct WheelView: View {
    var model: WheelModel
    var showsDetails = true

    private typealias G = WheelGeometry
    private var canvas: CGSize { showsDetails ? G.canvas : G.compactCanvas }
    /// +1: card below the ring, −1: card above.
    private var side: CGFloat { model.cardOnTop ? -1 : 1 }
    private let cardHeight: CGFloat = 96
    private var hasCard: Bool { showsDetails && AppSettings.shared.showFileDetails }
    private var k: CGFloat { AppSettings.shared.wheelSize.scale }

    var body: some View {
        ZStack {
            ZStack {
                backdrop
                segments
                    .id("\(model.wheel.rawValue)-\(model.page)")
                    .transition(.scale(scale: 0.94).combined(with: .opacity))
                centre
            }
            .scaleEffect(k)
            switcher
                .offset(y: hasCard ? -side * (G.disc * k + 30) : G.disc * k + 28)
                .opacity(model.phase == .choosing ? 1 : 0)
            if hasCard {
                InfoCard(model: model)
                    .frame(width: 330, height: cardHeight)
                    .offset(y: side * (G.disc * k + 14 + cardHeight / 2))
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .environment(\.controlActiveState, .key)
        .scaleEffect(model.isVisible ? 1 : 0.92)
        .blur(radius: model.isVisible ? 0 : 10)
        .opacity(model.isVisible ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: model.isVisible)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: model.wheel)
        .animation(.spring(response: 0.4, dampingFraction: 0.88), value: model.page)
        .animation(.snappy(duration: 0.25), value: model.phase)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: k)
    }

    /// A soft, invisible-edged shade that keeps labels legible over busy windows.
    private var backdrop: some View {
        Circle()
            .fill(RadialGradient(colors: [.black.opacity(0.34), .black.opacity(0.22), .clear],
                                 center: .center, startRadius: G.hole, endRadius: G.disc + 36))
            .frame(width: (G.disc + 40) * 2, height: (G.disc + 40) * 2)
            .allowsHitTesting(false)
    }

    // MARK: Segments

    private var segments: some View {
        let slots = model.slots
        return ZStack {
            GlassGroup(spacing: 1) {
                ZStack {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                        SegmentGlass(model: model, slot: slot, index: index, count: slots.count)
                    }
                }
            }
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                SegmentLabel(model: model, slot: slot, index: index, count: slots.count)
            }
        }
        .rotationEffect(.degrees(model.isVisible ? 0 : -16))
    }

    // MARK: Centre

    private var centre: some View {
        ZStack {
            Circle().fill(.clear).petalGlass(in: Circle())
            Group {
                switch model.phase {
                case .choosing:
                    if let slot = model.hoveredSlot { hoverLabel(slot) } else { fileChip }
                case .running(let title, let progress):
                    VStack(spacing: 8) {
                        ProgressRing(progress: progress).scaleEffect(0.8)
                        Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                case .success:
                    Image(systemName: "checkmark").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 54, height: 54)
                        .background(Color.green.gradient, in: Circle())
                        .symbolEffect(.bounce, value: model.phase)
                case .failure:
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 26)).foregroundStyle(.orange)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .id(centreKey)
        }
        .frame(width: G.hole * 2, height: G.hole * 2)
        .animation(.snappy(duration: 0.18), value: centreKey)
    }

    private var centreKey: String {
        switch model.phase {
        case .choosing: model.hoveredSlot?.id ?? "file"
        case .running: "running"
        case .success: "success"
        case .failure: "failure"
        }
    }

    private func hoverLabel(_ slot: WheelModel.Slot) -> some View {
        let title: String, symbol: String?
        switch slot {
        case .op(let op):
            title = op.title
            if case .symbol(let name) = op.glyph { symbol = name } else { symbol = nil }
        case .more:
            (title, symbol) = ("More", "ellipsis")
        }
        return VStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 22, weight: .light)).foregroundStyle(Color.petalAccent)
            }
            Text(title)
                .font(.system(size: symbol == nil ? 24 : 12, weight: symbol == nil ? .semibold : .medium))
                .tracking(symbol == nil ? -0.4 : 0)
                .minimumScaleFactor(0.55).lineLimit(1)
        }
        .padding(.horizontal, 10)
    }

    private var fileChip: some View {
        VStack(spacing: 4) {
            if let icon = model.icon {
                Image(nsImage: icon).resizable().scaledToFit().frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .shadow(color: .black.opacity(0.28), radius: 6, y: 3)
            }
            if let line = centreLine {
                Text(line).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
    }

    /// Size for one file, count for several, so the wheel itself tells you what you're holding.
    private var centreLine: String? {
        if model.urls.count > 1 { return "\(model.urls.count) items" }
        return model.facts.details.first
    }

    // MARK: Wheel switcher

    private var switcher: some View {
        HStack(spacing: 2) {
            ForEach(PetalAction.Wheel.allCases) { wheel in
                let active = wheel == model.wheel
                HStack(spacing: 6) {
                    Image(systemName: wheel.symbol).font(.system(size: 11, weight: .semibold))
                    if active { Text(wheel.title).font(.system(size: 12, weight: .semibold)) }
                    Text(model.keys[wheel]?.symbol ?? "").font(.system(size: 11, weight: .medium)).opacity(active ? 0.8 : 0.5)
                }
                .foregroundStyle(active ? Color.white : Color.primary.opacity(0.75))
                .padding(.horizontal, active ? 13 : 11)
                .frame(height: 28)
                .background { if active { Capsule().fill(Color.petalAccent) } }
            }
        }
        .padding(3)
        .background(Capsule().fill(.clear).petalGlass(in: Capsule()))
        .animation(.snappy(duration: 0.25), value: model.wheel)
    }
}

private extension WheelModel {
    func isHovered(_ index: Int) -> Bool { hovered == index && phase == .choosing }
    func isActive(_ slot: Slot) -> Bool {
        if case .op(let op) = slot { return activeID == op.id }
        return false
    }
    func isDimmed(_ slot: Slot) -> Bool { phase != .choosing && !isActive(slot) }
}

// MARK: - Segments

/// A ring segment with parallel sides, so the gap between neighbours is the same width everywhere.
nonisolated struct SegmentShape: Shape {
    var index: Int
    var count: Int
    var inner: CGFloat
    var outer: CGFloat
    var gap: CGFloat
    var corner: CGFloat

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        // Build an inset outline, then round it by stroking with a round join: the result keeps the exact gap.
        let r0 = inner + corner, r1 = outer - corner
        var path = Path()
        if count == 1 {
            path.addArc(center: c, radius: r1, startAngle: .zero, endAngle: .degrees(360), clockwise: false)
            path.addArc(center: c, radius: r0, startAngle: .degrees(360), endAngle: .zero, clockwise: true)
        } else {
            let step = 360.0 / Double(count)
            let start = Angle.degrees(-90 + (Double(index) - 0.5) * step)
            let end = Angle.degrees(-90 + (Double(index) + 0.5) * step)
            let h = gap / 2 + corner
            func lift(_ r: CGFloat) -> Angle { .radians(asin(Double(h / r))) }
            path.addArc(center: c, radius: r1, startAngle: start + lift(r1), endAngle: end - lift(r1), clockwise: false)
            path.addArc(center: c, radius: r0, startAngle: end - lift(r0), endAngle: start + lift(r0), clockwise: true)
            path.closeSubpath()
        }
        return path.union(path.strokedPath(StrokeStyle(lineWidth: corner * 2, lineJoin: .round)))
    }
}

private struct SegmentGlass: View {
    var model: WheelModel
    var slot: WheelModel.Slot
    var index: Int
    var count: Int

    private typealias G = WheelGeometry

    var body: some View {
        let hovered = model.isHovered(index)
        let highlighted = hovered || model.isActive(slot)
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(count)
        // On hover a segment slides outwards along its own axis; it never grows into its neighbours.
        let nudge: CGFloat = hovered ? 8 : 0
        let shape = SegmentShape(index: index, count: count, inner: G.ringInner, outer: G.ringOuter, gap: G.gap, corner: 12)

        shape.fill(.clear)
            .petalGlass(in: shape)
            .overlay(shape.fill(LinearGradient(colors: [Color.petalAccent.opacity(0.95), Color.petalAccent.opacity(0.78)],
                                               startPoint: .top, endPoint: .bottom)).opacity(highlighted ? 1 : 0))
            .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(highlighted ? 0.55 : 0.28), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .offset(x: cos(angle) * nudge, y: sin(angle) * nudge)
            .opacity(model.isVisible ? (model.isDimmed(slot) ? 0.3 : 1) : 0)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: hovered)
            .animation(.easeOut(duration: 0.16), value: highlighted)
            .animation(.spring(response: 0.45, dampingFraction: 0.85).delay(Double(index) * 0.02), value: model.isVisible)
            .animation(.easeOut(duration: 0.2), value: model.isDimmed(slot))
    }
}

private struct SegmentLabel: View {
    var model: WheelModel
    var slot: WheelModel.Slot
    var index: Int
    var count: Int

    private typealias G = WheelGeometry

    var body: some View {
        let hovered = model.isHovered(index)
        let highlighted = hovered || model.isActive(slot)
        let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / Double(count)
        let radius = (G.ringInner + G.ringOuter) / 2 + (hovered ? 8 : 0)

        label(highlighted: highlighted)
            .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            .opacity(model.isVisible ? (model.isDimmed(slot) ? 0.3 : 1) : 0)
            .allowsHitTesting(false)
            .animation(.spring(response: 0.26, dampingFraction: 0.8), value: hovered)
            .animation(.easeOut(duration: 0.2), value: model.isDimmed(slot))
    }

    @ViewBuilder
    private func label(highlighted: Bool) -> some View {
        let tint: Color = highlighted ? .white : .primary
        switch slot {
        case .op(let op):
            switch op.glyph {
            case .format(let name):
                Text(name).font(.system(size: name.count > 4 ? 15 : 19, weight: .semibold)).tracking(-0.2)
                    .minimumScaleFactor(0.6).lineLimit(1).foregroundStyle(tint).frame(width: 84)
            case .symbol(let symbol):
                VStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 24, weight: .regular))
                    Text(op.title).font(.system(size: 11, weight: .medium)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8).frame(width: 78)
                }
                .foregroundStyle(tint)
            }
        case .more:
            Image(systemName: "ellipsis").font(.system(size: 22, weight: .semibold)).foregroundStyle(tint)
        }
    }
}

// MARK: - Information card

struct InfoCard: View {
    var model: WheelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 11) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().scaledToFit().frame(width: 38, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.facts.title).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    Text(model.facts.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            status.frame(height: 28, alignment: .topLeading)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.clear)
            .petalGlass(in: RoundedRectangle(cornerRadius: 26, style: .continuous)))
        .opacity(model.isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.2), value: model.isVisible)
    }

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .choosing:
            if case .op(let op) = model.hoveredSlot {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(op.glyph.isFormat ? "Convert to \(op.title)" : op.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.petalAccent)
                        if let subtitle = op.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    if let hint = model.outputHint(for: op) {
                        Text("Saves as \(hint)").font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                }
            } else if case .more = model.hoveredSlot {
                Text("Keep hovering for more").font(.system(size: 11.5)).foregroundStyle(.secondary)
            } else {
                Text("Drop on an option").font(.system(size: 11.5)).foregroundStyle(.secondary)
            }
        case .running(let title, let progress):
            VStack(alignment: .leading, spacing: 6) {
                Text(title + "…").font(.system(size: 12, weight: .semibold))
                ProgressView(value: progress).progressViewStyle(.linear).tint(Color.petalAccent)
            }
        case .success(let message):
            Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(.green).lineLimit(2)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.system(size: 11.5)).foregroundStyle(.orange).lineLimit(2)
        }
    }
}

private extension PetalAction.Glyph {
    var isFormat: Bool { if case .format = self { true } else { false } }
}

// MARK: - Shared bits

struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.12), lineWidth: 5)
            Circle().trim(from: 0, to: max(0.03, progress))
                .stroke(Color.petalAccent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(progress * 100))")
                .font(.system(size: 17, weight: .semibold)).monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 66, height: 66)
        .animation(.easeOut(duration: 0.2), value: progress)
    }
}

/// Accent capsule button that keeps its colour when the window isn't key.
struct PetalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .padding(.horizontal, 18).padding(.vertical, 8)
            .background(Color.petalAccent, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}
