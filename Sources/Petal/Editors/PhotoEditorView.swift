import SwiftUI

struct PhotoEditorView: View {
    @State var model: PhotoEditorModel
    var close: () -> Void

    private let settings = AppSettings.shared
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                stage
                Divider()
                Inspector(model: model)
                    .frame(width: 292)
            }
            Divider()
            footer
        }
        .tint(Color.petalAccent)
        .background(.background)
        .alert("Couldn't save", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: Stage

    private var stage: some View {
        VStack(spacing: 0) {
            Picker("Tool", selection: $model.tab) {
                ForEach(PhotoEditorModel.Tab.allCases) { tab in Label(tab.rawValue, systemImage: tab.symbol).tag(tab) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 320)
            .padding(.top, 14).padding(.bottom, 8)

            GeometryReader { proxy in
                ZStack {
                    PreviewImage(model: model, available: proxy.size)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 12) {
            Button("Reset") { model.resetGeometry(); model.resetAdjustments(); model.backgroundEnabled = false }
                .disabled(!model.hasEdits)
            Spacer()
            let size = model.outputSize
            Text("\(Int(size.width)) × \(Int(size.height)) px").font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            Button("Copy") { model.copyToClipboard() }
            Button("Cancel", action: close).keyboardShortcut(.cancelAction)
            Button {
                save()
            } label: { Text("Save a Copy") }
                .buttonStyle(PetalButtonStyle()).keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func save() {
        do {
            let url = try model.save(policy: settings.outputPolicy, quality: settings.imageQuality)
            RecentStore.shared.add([url], title: "Edit")
            close()
            let screen = NSScreen.main?.visibleFrame ?? .zero
            ResultHUD.shared.show(outputs: [url], message: "Saved \(url.lastPathComponent)", near: NSPoint(x: screen.midX, y: screen.midY + 160))
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Preview and crop overlay

private struct PreviewImage: View {
    var model: PhotoEditorModel
    var available: CGSize

    var body: some View {
        let image = model.renderPreview()
        let size = image?.size ?? CGSize(width: 4, height: 3)
        let scale = min(available.width / size.width, available.height / size.height, 1.0 > 0 ? .infinity : 1)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: fitted.width, height: fitted.height)
                    .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
            }
            if model.tab == .crop {
                CropOverlay(model: model, size: fitted).frame(width: fitted.width, height: fitted.height)
            }
        }
        .frame(width: available.width, height: available.height)
        .animation(.snappy(duration: 0.2), value: model.quarterTurns)
    }
}

private struct CropOverlay: View {
    @Bindable var model: PhotoEditorModel
    var size: CGSize

    @State private var start: (crop: CGRect, handle: CropGeometry.Handle)?

    private var viewCrop: CGRect {
        CGRect(x: model.crop.minX * size.width, y: model.crop.minY * size.height, width: model.crop.width * size.width, height: model.crop.height * size.height)
    }

    var body: some View {
        let c = viewCrop
        ZStack {
            // Dim everything outside the crop.
            Path { p in p.addRect(CGRect(origin: .zero, size: size)); p.addRect(c) }
                .fill(Color.black.opacity(0.52), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
            // Rule-of-thirds grid and frame.
            Path { p in
                for i in 1...2 {
                    let x = c.minX + c.width * CGFloat(i) / 3, y = c.minY + c.height * CGFloat(i) / 3
                    p.move(to: CGPoint(x: x, y: c.minY)); p.addLine(to: CGPoint(x: x, y: c.maxY))
                    p.move(to: CGPoint(x: c.minX, y: y)); p.addLine(to: CGPoint(x: c.maxX, y: y))
                }
            }
            .stroke(.white.opacity(0.35), lineWidth: 0.75).allowsHitTesting(false)
            Rectangle().path(in: c).stroke(.white, lineWidth: 1.5).allowsHitTesting(false)
            ForEach(Array(handles(c).enumerated()), id: \.offset) { _, point in
                Circle().fill(.white).frame(width: 12, height: 12).shadow(color: .black.opacity(0.4), radius: 2).position(point).allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil {
                        guard let handle = CropGeometry.hit(value.startLocation, crop: viewCrop) else { return }
                        start = (model.crop, handle)
                    }
                    guard let start else { return }
                    let dx = Double(value.translation.width / size.width), dy = Double(value.translation.height / size.height)
                    let ratio = model.aspect.ratio(original: model.rotatedRatio).map { Double($0 / model.rotatedRatio) }
                    model.crop = CropGeometry.dragged(start.crop, handle: start.handle, dx: dx, dy: dy, ratio: ratio)
                }
                .onEnded { _ in start = nil }
        )
        .onContinuousHover { phase in
            if case .active(let location) = phase, let handle = CropGeometry.hit(location, crop: viewCrop) { cursor(for: handle).set() } else { NSCursor.arrow.set() }
        }
    }

    private func handles(_ c: CGRect) -> [CGPoint] {
        [CGPoint(x: c.minX, y: c.minY), CGPoint(x: c.midX, y: c.minY), CGPoint(x: c.maxX, y: c.minY), CGPoint(x: c.maxX, y: c.midY),
         CGPoint(x: c.maxX, y: c.maxY), CGPoint(x: c.midX, y: c.maxY), CGPoint(x: c.minX, y: c.maxY), CGPoint(x: c.minX, y: c.midY)]
    }

    private func cursor(for handle: CropGeometry.Handle) -> NSCursor {
        switch handle {
        case .move: .openHand
        case .top, .bottom: .resizeUpDown
        case .left, .right: .resizeLeftRight
        default: .crosshair
        }
    }
}

// MARK: - Inspector

private struct Inspector: View {
    @Bindable var model: PhotoEditorModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                switch model.tab {
                case .crop: crop
                case .adjust: adjust
                case .background: background
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.regularMaterial)
    }

    private func header(_ title: String) -> some View { Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary).textCase(.uppercase) }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: @escaping (Double) -> String, neutral: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 12.5))
                Spacer()
                Text(format(value.wrappedValue)).font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
                Button { value.wrappedValue = neutral } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).opacity(abs(value.wrappedValue - neutral) > 0.0005 ? 1 : 0.25)
            }
            Slider(value: value, in: range)
        }
    }

    // MARK: Crop

    private var crop: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                header("Shape")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(PhotoEditorModel.Aspect.allCases) { aspect in
                        Button { model.applyAspect(aspect) } label: {
                            Text(aspect.label).font(.system(size: 12, weight: .medium)).frame(maxWidth: .infinity).padding(.vertical, 6)
                                .background(model.aspect == aspect ? Color.petalAccent : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .foregroundStyle(model.aspect == aspect ? Color.white : Color.primary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                header("Rotate & flip")
                HStack(spacing: 8) {
                    iconButton("rotate.left", "Rotate left") { model.rotate(by: -1) }
                    iconButton("rotate.right", "Rotate right") { model.rotate(by: 1) }
                    iconButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "Flip horizontally", active: model.flipH) { model.flipH.toggle() }
                    iconButton("arrow.up.and.down.righttriangle.up.righttriangle.down", "Flip vertically", active: model.flipV) { model.flipV.toggle(); }
                }
            }
            slider("Straighten", value: $model.straighten, range: -15...15, format: { String(format: "%+.1f°", $0) }, neutral: 0)
        }
        .onChange(of: model.straighten) { _, _ in
            // Straightening changes the picture's size; keep a locked ratio valid.
            if model.aspect != .free { model.applyAspect(model.aspect) }
        }
        .onChange(of: model.flipH) { _, _ in if model.aspect != .free { model.applyAspect(model.aspect) } }
        .onChange(of: model.flipV) { _, _ in if model.aspect != .free { model.applyAspect(model.aspect) } }
    }

    private func iconButton(_ symbol: String, _ help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15)).frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(active ? Color.petalAccent : Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain).help(help)
    }

    // MARK: Adjust

    private var adjust: some View {
        VStack(alignment: .leading, spacing: 16) {
            slider("Exposure", value: $model.exposure, range: -2...2, format: { String(format: "%+.1f", $0) }, neutral: 0)
            slider("Contrast", value: $model.contrast, range: 0.6...1.6, format: { String(format: "%.0f%%", $0 * 100) }, neutral: 1)
            slider("Saturation", value: $model.saturation, range: 0...2, format: { String(format: "%.0f%%", $0 * 100) }, neutral: 1)
            slider("Warmth", value: $model.warmth, range: -1...1, format: { String(format: "%+.1f", $0) }, neutral: 0)
            Button("Reset adjustments") { model.resetAdjustments() }
                .disabled(model.exposure == 0 && model.contrast == 1 && model.saturation == 1 && model.warmth == 0)
        }
    }

    // MARK: Background

    private var background: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("Add a background", isOn: $model.backgroundEnabled).toggleStyle(.switch)
            Group {
                VStack(alignment: .leading, spacing: 6) {
                    header("Canvas")
                    Picker("Canvas", selection: $model.canvas) {
                        ForEach([PhotoEditorModel.Aspect.original, .square, .fourThree, .threeTwo, .sixteenNine, .threeFour, .nineSixteen]) { Text($0 == .original ? "Fit the picture" : $0.label).tag($0) }
                    }.labelsHidden()
                }
                slider("Padding", value: $model.padding, range: 0...0.4, format: { String(format: "%.0f%%", $0 * 100 / 0.4) }, neutral: 0.08)
                VStack(alignment: .leading, spacing: 8) {
                    header("Fill")
                    Picker("Fill", selection: $model.fill) { ForEach(PhotoEditorModel.Fill.allCases) { Text($0.rawValue).tag($0) } }
                        .pickerStyle(.segmented).labelsHidden()
                    if model.fill != .blur {
                        HStack {
                            ColorPicker("Colour", selection: $model.color1, supportsOpacity: false)
                            if model.fill == .gradient { ColorPicker("to", selection: $model.color2, supportsOpacity: false) }
                        }
                    }
                }
                slider("Rounded corners", value: $model.cornerRadius, range: 0...0.3, format: { String(format: "%.0f%%", $0 * 100 / 0.3) }, neutral: 0.05)
                Toggle("Shadow", isOn: $model.shadow)
            }
            .disabled(!model.backgroundEnabled).opacity(model.backgroundEnabled ? 1 : 0.4)
        }
    }
}
