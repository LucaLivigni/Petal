import AppKit
import SwiftUI
import Observation
import ServiceManagement

enum TriggerKey: String, CaseIterable, Identifiable {
    case shift, command, control, option

    var id: String { rawValue }
    var flag: NSEvent.ModifierFlags {
        switch self {
        case .shift: .shift
        case .command: .command
        case .control: .control
        case .option: .option
        }
    }
    var symbol: String {
        switch self {
        case .shift: "⇧"
        case .command: "⌘"
        case .control: "⌃"
        case .option: "⌥"
        }
    }
    var name: String { rawValue.capitalized }
}

/// The handful of accent colours Petal offers. Chosen to look good on glass in light and dark.
enum AccentChoice: String, CaseIterable, Identifiable {
    case tangerine, coral, rose, violet, indigo, azure, teal, green, graphite

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
    var color: Color {
        switch self {
        case .tangerine: Color(red: 1.00, green: 0.54, blue: 0.12)
        case .coral:     Color(red: 1.00, green: 0.35, blue: 0.31)
        case .rose:      Color(red: 0.98, green: 0.31, blue: 0.55)
        case .violet:    Color(red: 0.56, green: 0.36, blue: 0.97)
        case .indigo:    Color(red: 0.36, green: 0.42, blue: 1.00)
        case .azure:     Color(red: 0.16, green: 0.61, blue: 1.00)
        case .teal:      Color(red: 0.10, green: 0.71, blue: 0.66)
        case .green:     Color(red: 0.20, green: 0.74, blue: 0.43)
        case .graphite:  Color(red: 0.50, green: 0.54, blue: 0.62)
        }
    }
}

/// How big the wheel is drawn. M is the original size.
enum WheelSize: String, CaseIterable, Identifiable {
    case small, medium

    var id: String { rawValue }
    var label: String { self == .small ? "S" : "M" }
    var caption: String { self == .small ? "Compact" : "Standard" }
    var scale: CGFloat { self == .small ? 0.76 : 1 }
}

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var convertKey: TriggerKey { didSet { defaults.set(convertKey.rawValue, forKey: "convertKey") } }
    var toolsKey: TriggerKey { didSet { defaults.set(toolsKey.rawValue, forKey: "toolsKey") } }
    var actionsKey: TriggerKey { didSet { defaults.set(actionsKey.rawValue, forKey: "actionsKey") } }
    var imageQuality: Double { didSet { defaults.set(imageQuality, forKey: "imageQuality") } }
    var saveToFolder: Bool { didSet { defaults.set(saveToFolder, forKey: "saveToFolder") } }
    var folderPath: String { didSet { defaults.set(folderPath, forKey: "folderPath") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var sounds: Bool { didSet { defaults.set(sounds, forKey: "sounds") } }
    var revealAfter: Bool { didSet { defaults.set(revealAfter, forKey: "revealAfter") } }
    var terminalBundleID: String { didSet { defaults.set(terminalBundleID, forKey: "terminalBundleID") } }
    var paused: Bool { didSet { defaults.set(paused, forKey: "paused") } }
    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    var accent: AccentChoice { didSet { defaults.set(accent.rawValue, forKey: "accent") } }
    var wheelSize: WheelSize { didSet { defaults.set(wheelSize.rawValue, forKey: "wheelSize") } }
    var showFileDetails: Bool { didSet { defaults.set(showFileDetails, forKey: "showFileDetails") } }

    init() {
        func key(_ name: String, _ fallback: TriggerKey) -> TriggerKey {
            UserDefaults.standard.string(forKey: name).flatMap(TriggerKey.init(rawValue:)) ?? fallback
        }
        convertKey = key("convertKey", .shift)
        toolsKey = key("toolsKey", .command)
        actionsKey = key("actionsKey", .control)
        imageQuality = defaults.object(forKey: "imageQuality") as? Double ?? 0.85
        saveToFolder = defaults.bool(forKey: "saveToFolder")
        folderPath = defaults.string(forKey: "folderPath") ?? ""
        haptics = defaults.object(forKey: "haptics") as? Bool ?? true
        sounds = defaults.object(forKey: "sounds") as? Bool ?? true
        revealAfter = defaults.bool(forKey: "revealAfter")
        terminalBundleID = defaults.string(forKey: "terminalBundleID") ?? "com.apple.Terminal"
        paused = defaults.bool(forKey: "paused")
        hasOnboarded = defaults.bool(forKey: "hasOnboarded")
        accent = defaults.string(forKey: "accent").flatMap(AccentChoice.init(rawValue:)) ?? .tangerine
        wheelSize = defaults.string(forKey: "wheelSize").flatMap(WheelSize.init(rawValue:)) ?? .medium
        showFileDetails = defaults.object(forKey: "showFileDetails") as? Bool ?? true
    }

    func key(for wheel: PetalAction.Wheel) -> TriggerKey {
        switch wheel {
        case .convert: convertKey
        case .tools: toolsKey
        case .actions: actionsKey
        }
    }

    func setKey(_ key: TriggerKey, for wheel: PetalAction.Wheel) {
        // Keys must stay unique: swap with whichever wheel already owns it.
        let previous = self.key(for: wheel)
        if let other = PetalAction.Wheel.allCases.first(where: { $0 != wheel && self.key(for: $0) == key }) {
            apply(previous, to: other)
        }
        apply(key, to: wheel)
    }

    private func apply(_ key: TriggerKey, to wheel: PetalAction.Wheel) {
        switch wheel {
        case .convert: convertKey = key
        case .tools: toolsKey = key
        case .actions: actionsKey = key
        }
    }

    func wheel(for flags: NSEvent.ModifierFlags) -> PetalAction.Wheel? {
        let relevant = flags.intersection([.shift, .command, .control, .option])
        return PetalAction.Wheel.allCases.first { relevant == self.key(for: $0).flag }
    }

    var outputPolicy: OutputPolicy {
        guard saveToFolder, !folderPath.isEmpty else { return OutputPolicy(folder: nil) }
        return OutputPolicy(folder: URL(fileURLWithPath: folderPath, isDirectory: true))
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() } catch {
                NSLog("Launch at login failed: \(error.localizedDescription)")
            }
        }
    }
}

@MainActor
@Observable
final class RecentStore {
    static let shared = RecentStore()

    struct Item: Identifiable, Hashable {
        let id = UUID()
        let url: URL
        let title: String
    }

    private(set) var items: [Item] = []

    func add(_ urls: [URL], title: String) {
        for url in urls.reversed() {
            items.removeAll { $0.url == url }
            items.insert(Item(url: url, title: title), at: 0)
        }
        items = Array(items.prefix(8))
    }
}
