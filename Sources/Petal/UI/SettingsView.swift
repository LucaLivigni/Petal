import SwiftUI
import AppKit

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, wheels, output, formats, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: "General"
        case .appearance: "Appearance"
        case .wheels: "Wheels"
        case .output: "Output"
        case .formats: "Formats"
        case .about: "About"
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "paintpalette"
        case .wheels: "circle.hexagongrid"
        case .output: "square.and.arrow.down"
        case .formats: "square.stack.3d.up"
        case .about: "info.circle"
        }
    }
    var tint: Color {
        switch self {
        case .general: .gray
        case .appearance: .purple
        case .wheels: .indigo
        case .output: .blue
        case .formats: .petalAccent
        case .about: .pink
        }
    }
}

struct SettingsView: View {
    @State private var page: SettingsPage? = Self.startPage

    private static var startPage: SettingsPage {
        #if DEBUG
        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--page=") }),
           let page = SettingsPage(rawValue: String(arg.dropFirst(7))) { return page }
        #endif
        return .general
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPage.allCases, selection: $page) { item in
                Label {
                    Text(item.title)
                } icon: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(item.tint.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch page ?? .general {
                case .general: GeneralPage()
                case .appearance: AppearancePage()
                case .wheels: WheelsPage()
                case .output: OutputPage()
                case .formats: FormatsPage()
                case .about: AboutPage()
                }
            }
            .navigationTitle((page ?? .general).title)
        }
    }
}

// MARK: General

private struct GeneralPage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: settings.paused ? "pause.circle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 26)).foregroundStyle(settings.paused ? .orange : .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.paused ? "Petal is paused" : "Petal is ready").font(.headline)
                        Text("Start dragging a file, then tap \(settings.convertKey.symbol) to open the wheel. No special permissions needed.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }

            Section("Wheels") {
                ForEach(PetalAction.Wheel.allCases) { wheel in
                    Picker(selection: Binding(get: { settings.key(for: wheel) }, set: { settings.setKey($0, for: wheel) })) {
                        ForEach(TriggerKey.allCases) { key in Text("\(key.symbol)  \(key.name)").tag(key) }
                    } label: {
                        Label(wheel.title, systemImage: wheel.symbol)
                    }
                }
                Text("Start dragging a file, then tap the key. The wheel stays open until you drop or let go.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Feedback") {
                Toggle("Haptic feedback", isOn: $settings.haptics)
                Toggle("Sounds", isOn: $settings.sounds)
            }

            Section("App") {
                Toggle("Open at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.launchAtLogin = $0 }))
                Toggle("Pause Petal", isOn: $settings.paused)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Appearance

private struct AppearancePage: View {
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        Form {
            Section("Accent colour") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 14) {
                    ForEach(AccentChoice.allCases) { choice in
                        Swatch(choice: choice, selected: settings.accent == choice) {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { settings.accent = choice }
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Wheel size") {
                Picker("Size", selection: $settings.wheelSize) {
                    ForEach(WheelSize.allCases) { size in Text("\(size.label)  \(size.caption)").tag(size) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            Section("Preview") {
                HStack {
                    Spacer()
                    DemoWheelView(showsDetails: false, cyclesWheels: false, scale: 0.68)
                    Spacer()
                }
            }

            Section("Wheel") {
                Toggle("Show file details", isOn: $settings.showFileDetails)
                Text("Size, dimensions, pages or duration of what you're dragging, and the name the result will get.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct Swatch: View {
    var choice: AccentChoice
    var selected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                ZStack {
                    Circle().fill(choice.color.gradient).frame(width: 34, height: 34)
                        .shadow(color: choice.color.opacity(selected ? 0.5 : 0), radius: 8, y: 3)
                    if selected {
                        Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                    }
                    Circle().strokeBorder(choice.color, lineWidth: 2.5).frame(width: 44, height: 44)
                        .opacity(selected ? 1 : 0).scaleEffect(selected ? 1 : 0.8)
                }
                .frame(width: 46, height: 46)
                Text(choice.name).font(.system(size: 11, weight: selected ? .semibold : .regular)).foregroundStyle(selected ? .primary : .secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(choice.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Output

private struct OutputPage: View {
    @Bindable private var settings = AppSettings.shared

    private let terminals: [(String, String)] = [
        ("Terminal", "com.apple.Terminal"), ("iTerm", "com.googlecode.iterm2"), ("Ghostty", "com.mitchellh.ghostty"),
        ("Warp", "dev.warp.Warp-Stable"), ("Kitty", "net.kovidgoyal.kitty"),
    ]

    var body: some View {
        Form {
            Section("Where results go") {
                Picker("Save results", selection: $settings.saveToFolder) {
                    Text("Next to the original").tag(false)
                    Text("In a folder").tag(true)
                }
                .pickerStyle(.radioGroup)
                if settings.saveToFolder {
                    LabeledContent("Folder") {
                        HStack {
                            Text(settings.folderPath.isEmpty ? "Not chosen" : (settings.folderPath as NSString).abbreviatingWithTildeInPath)
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            Button("Choose…") { chooseFolder() }
                        }
                    }
                }
                Text("Petal never overwrites. A name that already exists gets a number.").font(.callout).foregroundStyle(.secondary)
            }

            Section("Quality") {
                LabeledContent("Images & PDF pages") {
                    HStack {
                        Slider(value: $settings.imageQuality, in: 0.4...1, step: 0.05).frame(width: 180)
                        Text("\(Int(settings.imageQuality * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                    }
                }
            }

            Section("After converting") {
                Toggle("Show the result in Finder", isOn: $settings.revealAfter)
                Picker("Terminal action opens", selection: $settings.terminalBundleID) {
                    ForEach(terminals, id: \.1) { name, id in
                        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil || id == settings.terminalBundleID {
                            Text(name).tag(id)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url { settings.folderPath = url.path }
    }
}

// MARK: Formats

private struct FormatsPage: View {
    private let groups: [(String, String, [String])] = [
        ("Images", "photo", ["JPG", "PNG", "HEIC", "TIFF", "AVIF", "BMP", "GIF", "PDF", "JP2", "ICO", "ICNS", "TGA", "PSD", "WebP*", "RAW in", "SVG in"]),
        ("Video", "film", ["MP4", "MOV", "GIF", "M4A", "WAV", "WebM*", "MKV*", "AVI*", "WMV*", "MP3*"]),
        ("Audio", "waveform", ["M4A", "WAV", "FLAC", "AIFF", "CAF", "MP3*", "OGG*", "Opus*", "WMA*"]),
        ("PDF", "doc.richtext", ["DOCX", "PAGES†", "PPTX", "XLSX", "EPUB", "MD", "TXT", "JPG", "PNG", "TIFF"]),
        ("Documents", "doc.text", ["PDF", "DOCX", "PAGES†", "MD", "EPUB", "HTML", "RTF", "ODT", "TXT"]),
        ("Slides", "play.rectangle", ["PDF†", "JPG†", "PNG†", "PPT in", "PPTX in", "KEY in"]),
        ("Spreadsheets", "tablecells", ["XLSX", "ODS", "CSV", "TSV", "JSON", "PDF", "HTML", "XLS in†"]),
        ("Subtitles", "captions.bubble", ["SRT", "VTT", "TXT"]),
        ("Archives", "shippingbox", ["ZIP", "TAR", "TAR.GZ", "GZIP", "7Z in", "RAR in"]),
    ]

    private struct Engine: Identifiable {
        var id: String { name }
        var name: String
        var detail: String
        var active: Bool
        var path: String?
    }

    private var engines: [Engine] {
        let ffmpeg = FFmpeg.capabilities
        return [
            Engine(name: "ffmpeg", detail: "MP3, WebM, MKV, AVI, WMV, OGG, Opus, WMA", active: ffmpeg.isAvailable, path: ffmpeg.url.map { Self.bundled($0) }),
            Engine(name: "cwebp", detail: "WebP images", active: ExternalTool.cwebp != nil, path: ExternalTool.cwebp.map { Self.bundled($0) }),
            Engine(name: "Keynote", detail: "PPT / PPTX / KEY slides to PDF, JPG and PNG (†)", active: IWorkBridge.isInstalled(.keynote), path: nil),
            Engine(name: "Pages", detail: "Pages documents in and out (†)", active: IWorkBridge.isInstalled(.pages), path: nil),
            Engine(name: "Numbers", detail: "Old XLS and Numbers spreadsheets (†)", active: IWorkBridge.isInstalled(.numbers), path: nil),
        ]
    }

    private static func bundled(_ url: URL) -> String {
        url.path.contains(".app/Contents/Resources/Engines/") ? "Included in Petal" : url.path
    }

    var body: some View {
        Form {
            Section("What the wheels can do") {
                ForEach(groups, id: \.0) { name, symbol, formats in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: symbol).frame(width: 22).foregroundStyle(Color.petalAccent)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(name).font(.headline)
                            ChipFlow(items: formats)
                        }
                    }
                    .padding(.vertical, 3)
                }
                Text("* uses the encoders included in Petal    † uses a free Apple app, shown below")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("Engines") {
                LabeledContent {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } label: {
                    VStack(alignment: .leading) {
                        Text("Built in")
                        Text("ImageIO, AVFoundation, PDFKit, Vision, TextKit. No other software needed.").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Button("Show open-source licenses") {
                    if let folder = Bundle.main.url(forResource: "licenses", withExtension: nil, subdirectory: "Engines") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                }
                ForEach(engines) { engine in
                    LabeledContent {
                        Image(systemName: engine.active ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(engine.active ? .green : .secondary)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(engine.name + (engine.active ? "" : " · not installed"))
                            Text(engine.path ?? engine.detail).font(.callout).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(2)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ChipFlow: View {
    var items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 58, maximum: 140), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item).font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

// MARK: About

private struct AboutPage: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            Text("Petal").font(.system(size: 30, weight: .bold, design: .rounded))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Text("Drag a file. Tap a key. Drop it on what you need.")
                .font(.title3).multilineTextAlignment(.center).padding(.top, 4)
            Label("Everything happens on your Mac. Your files are never uploaded.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}
