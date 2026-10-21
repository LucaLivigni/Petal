import Foundation
import Observation

/// Remembers what you use and how you've arranged each wheel. Stored on this Mac only.
@MainActor
@Observable
final class WheelPreferences {
    static let shared = WheelPreferences()

    /// Wheels are arranged per file kind; folders share the arrangement of "other files", actions are the same for everything.
    nonisolated static func layoutKey(kind: FileKind, wheel: PetalAction.Wheel) -> String {
        if wheel == .actions { return "any|actions" }
        let normalized: FileKind = kind == .folder ? .other : kind
        return "\(normalized.rawValue)|\(wheel.rawValue)"
    }

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var layouts: [String: WheelLayout]
    private(set) var usage: [String: UsageScore]
    var learns: Bool { didSet { defaults.set(learns, forKey: "wheel.learns") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layouts = Self.load([String: WheelLayout].self, from: defaults, key: "wheel.layouts") ?? [:]
        usage = Self.load([String: UsageScore].self, from: defaults, key: "wheel.usage") ?? [:]
        learns = defaults.object(forKey: "wheel.learns") as? Bool ?? true
    }

    private static func load<T: Decodable>(_ type: T.Type, from defaults: UserDefaults, key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(layouts), forKey: "wheel.layouts")
        defaults.set(try? JSONEncoder().encode(usage), forKey: "wheel.usage")
    }

    // MARK: Learning

    func record(kind: FileKind, wheel: PetalAction.Wheel, id: String, now: Date = .now) {
        let key = Self.layoutKey(kind: kind, wheel: wheel) + "|" + id
        usage[key] = (usage[key] ?? UsageScore(value: 0, last: now)).bumped(at: now)
        save()
    }

    func scores(kind: FileKind, wheel: PetalAction.Wheel, now: Date = .now) -> [String: Double] {
        let prefix = Self.layoutKey(kind: kind, wheel: wheel) + "|"
        var result: [String: Double] = [:]
        for (key, value) in usage where key.hasPrefix(prefix) { result[String(key.dropFirst(prefix.count))] = value.current(at: now) }
        return result
    }

    func resetLearning() {
        usage = [:]
        save()
    }

    // MARK: Arranging

    func layout(kind: FileKind, wheel: PetalAction.Wheel) -> WheelLayout {
        layouts[Self.layoutKey(kind: kind, wheel: wheel)] ?? WheelLayout()
    }

    /// What the wheel should show for these operations.
    func arrange(_ ops: [PetalAction], kind: FileKind, wheel: PetalAction.Wheel, now: Date = .now) -> [PetalAction] {
        let order = WheelArranger.visibleOrder(ids: ops.map(\.id), layout: layout(kind: kind, wheel: wheel),
                                               scores: scores(kind: kind, wheel: wheel, now: now), learns: learns)
        let byID = Dictionary(ops.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return order.compactMap { byID[$0] }
    }

    /// For the settings editor: every id, hidden ones included.
    func editingOrder(ids: [String], kind: FileKind, wheel: PetalAction.Wheel, now: Date = .now) -> [String] {
        WheelArranger.effectiveOrder(ids: ids, layout: layout(kind: kind, wheel: wheel),
                                     scores: scores(kind: kind, wheel: wheel, now: now), learns: learns)
    }

    // MARK: Editing

    private func update(_ kind: FileKind, _ wheel: PetalAction.Wheel, _ change: (inout WheelLayout) -> Void) {
        let key = Self.layoutKey(kind: kind, wheel: wheel)
        var layout = layouts[key] ?? WheelLayout()
        change(&layout)
        layouts[key] = layout.isDefault ? nil : layout
        save()
    }

    func isPinned(_ id: String, kind: FileKind, wheel: PetalAction.Wheel) -> Bool { layout(kind: kind, wheel: wheel).pinned.contains(id) }
    func isHidden(_ id: String, kind: FileKind, wheel: PetalAction.Wheel) -> Bool { layout(kind: kind, wheel: wheel).hidden.contains(id) }

    func togglePin(_ id: String, kind: FileKind, wheel: PetalAction.Wheel) {
        update(kind, wheel) { l in
            if let i = l.pinned.firstIndex(of: id) { l.pinned.remove(at: i) } else { l.pinned.append(id); l.hidden.removeAll { $0 == id } }
        }
    }

    func toggleHidden(_ id: String, kind: FileKind, wheel: PetalAction.Wheel) {
        update(kind, wheel) { l in
            if let i = l.hidden.firstIndex(of: id) { l.hidden.remove(at: i) } else { l.hidden.append(id); l.pinned.removeAll { $0 == id } }
        }
    }

    /// Persists a new order for the pinned items.
    func setPinnedOrder(_ ids: [String], kind: FileKind, wheel: PetalAction.Wheel) {
        update(kind, wheel) { $0.pinned = ids }
    }

    /// Persists a manual order for everything that isn't pinned.
    func setManualOrder(_ ids: [String], kind: FileKind, wheel: PetalAction.Wheel) {
        update(kind, wheel) { $0.order = ids }
    }

    func reset(kind: FileKind, wheel: PetalAction.Wheel) {
        layouts[Self.layoutKey(kind: kind, wheel: wheel)] = nil
        save()
    }
}
