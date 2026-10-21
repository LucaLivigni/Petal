import SwiftUI

/// Settings → Wheels: pin favourites, hide what you never use, and drag the rest into the order you like.
struct WheelsPage: View {
    @Bindable private var prefs = WheelPreferences.shared
    @State private var kind: FileKind = .image
    @State private var wheel: PetalAction.Wheel = .convert

    private static let kinds: [(FileKind, String)] = [
        (.image, "Images"), (.video, "Video"), (.audio, "Audio"), (.pdf, "PDF"), (.document, "Documents"), (.slides, "Slides"),
        (.spreadsheet, "Spreadsheets"), (.subtitle, "Subtitles"), (.archive, "Archives"), (.other, "Folders & other files"),
    ]

    /// Sample selections that together reveal every operation a kind can offer.
    private static func samples(_ kind: FileKind) -> [[String]] {
        switch kind {
        case .image: [["a.jpg"], ["a.png"], ["a.heic"], ["a.jpg", "b.jpg"]]
        case .video: [["a.mp4"], ["a.mkv"]]
        case .audio: [["a.mp3"], ["a.wav"], ["a.ogg"]]
        case .pdf: [["a.pdf"], ["a.pdf", "b.pdf"]]
        case .document: [["a.docx"], ["a.md"]]
        case .slides: [["a.pptx"]]
        case .spreadsheet: [["a.xlsx"], ["a.csv"]]
        case .subtitle: [["a.srt"]]
        case .archive: [["a.zip"], ["a.tar"]]
        default: [["a.bin"]]
        }
    }

    private var operations: [PetalAction] {
        var seen = Set<String>()
        var result: [PetalAction] = []
        for names in Self.samples(wheel == .actions ? .other : kind) {
            let urls = names.map { URL(fileURLWithPath: "/tmp/\($0)") }
            for op in Catalog.operations(for: urls, wheel: wheel) where seen.insert(op.id).inserted { result.append(op) }
        }
        return result
    }

    private var effectiveKind: FileKind { wheel == .actions ? .other : kind }

    var body: some View {
        let ops = operations
        let ids = ops.map(\.id)
        let byID = Dictionary(ops.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let layout = prefs.layout(kind: effectiveKind, wheel: wheel)
        let pinned = layout.pinned.filter(byID.keys.contains)
        let rest = prefs.editingOrder(ids: ids, kind: effectiveKind, wheel: wheel).filter { !pinned.contains($0) }

        VStack(spacing: 0) {
            controls
            List {
                Section {
                    if pinned.isEmpty {
                        Text("Star a format to keep it at the top of the wheel.").font(.callout).foregroundStyle(.secondary)
                    }
                    ForEach(pinned, id: \.self) { id in row(byID[id]!) }
                        .onMove { from, to in
                            var order = pinned
                            order.move(fromOffsets: from, toOffset: to)
                            prefs.setPinnedOrder(order, kind: effectiveKind, wheel: wheel)
                        }
                } header: { Text("Always first") }

                Section {
                    ForEach(rest, id: \.self) { id in row(byID[id]!) }
                        .onMove { from, to in
                            var order = rest
                            order.move(fromOffsets: from, toOffset: to)
                            prefs.setManualOrder(order, kind: effectiveKind, wheel: wheel)
                        }
                } header: {
                    Text(prefs.learns ? "Then, most used first" : "Then, in this order")
                } footer: {
                    Text("Drag to rearrange. Hidden items stay available here but never appear on the wheel.").font(.callout)
                }
            }
            footer
        }
    }

    // MARK: Pieces

    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $prefs.learns) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Learn from what I use")
                    Text("Formats you use often move to the front of the wheel.").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Picker("Wheel", selection: $wheel) {
                    ForEach(PetalAction.Wheel.allCases) { w in Text(w.title).tag(w) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 260)
                Spacer()
                if wheel != .actions {
                    Picker("File type", selection: $kind) {
                        ForEach(Self.kinds, id: \.0) { Text($0.1).tag($0.0) }
                    }
                    .labelsHidden().frame(maxWidth: 200)
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            Button("Reset this wheel") { prefs.reset(kind: effectiveKind, wheel: wheel) }
            Spacer()
            Button("Forget what I've used", role: .destructive) { prefs.resetLearning() }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
    }

    private func row(_ op: PetalAction) -> some View {
        let pinned = prefs.isPinned(op.id, kind: effectiveKind, wheel: wheel)
        let hidden = prefs.isHidden(op.id, kind: effectiveKind, wheel: wheel)
        return HStack(spacing: 12) {
            glyph(op)
            VStack(alignment: .leading, spacing: 1) {
                Text(op.title).font(.system(size: 13, weight: .medium))
                if let subtitle = op.subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
            Button { prefs.toggleHidden(op.id, kind: effectiveKind, wheel: wheel) } label: {
                Image(systemName: hidden ? "eye.slash" : "eye").frame(width: 22)
            }
            .buttonStyle(.plain).foregroundStyle(hidden ? Color.secondary : Color.primary.opacity(0.55))
            .help(hidden ? "Show on the wheel" : "Hide from the wheel")
            Button { prefs.togglePin(op.id, kind: effectiveKind, wheel: wheel) } label: {
                Image(systemName: pinned ? "star.fill" : "star").frame(width: 22)
            }
            .buttonStyle(.plain).foregroundStyle(pinned ? Color.petalAccent : Color.primary.opacity(0.55))
            .help(pinned ? "Unpin" : "Always show first")
        }
        .opacity(hidden ? 0.45 : 1)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func glyph(_ op: PetalAction) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.08))
            switch op.glyph {
            case .format(let name): Text(name).font(.system(size: name.count > 4 ? 9 : 11, weight: .semibold)).minimumScaleFactor(0.6).padding(2)
            case .symbol(let symbol): Image(systemName: symbol).font(.system(size: 14))
            }
        }
        .frame(width: 34, height: 28)
    }
}
