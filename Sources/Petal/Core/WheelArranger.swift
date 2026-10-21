import Foundation

/// How one wheel is arranged by the user. Everything is keyed by operation id.
nonisolated struct WheelLayout: Codable, Equatable, Sendable {
    /// Always shown first, in this order.
    var pinned: [String] = []
    /// Never shown on the wheel.
    var hidden: [String] = []
    /// A manual order for the rest. Items missing here follow in learned / default order.
    var order: [String] = []

    var isDefault: Bool { pinned.isEmpty && hidden.isEmpty && order.isEmpty }
}

/// A use count that fades: it halves every 30 days, so what you did last year doesn't outrank this week.
nonisolated struct UsageScore: Codable, Equatable, Sendable {
    var value: Double
    var last: Date

    static let halfLifeDays = 30.0
    /// Below this, a format hasn't earned a place yet and keeps its default position.
    static let threshold = 0.75

    func current(at now: Date) -> Double {
        let days = max(0, now.timeIntervalSince(last)) / 86_400
        return value * pow(0.5, days / Self.halfLifeDays)
    }

    func bumped(at now: Date) -> UsageScore { UsageScore(value: current(at: now) + 1, last: now) }
}

nonisolated enum WheelArranger {
    /// All ids in display order (pinned, then manual, then learned, then default), hidden ones included.
    static func effectiveOrder(ids: [String], layout: WheelLayout, scores: [String: Double], learns: Bool) -> [String] {
        let known = Set(ids)
        let pinned = layout.pinned.filter(known.contains)
        let pinnedSet = Set(pinned)
        let manual = Dictionary(layout.order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let defaultIndex = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        let rest = ids.filter { !pinnedSet.contains($0) }.sorted { a, b in
            let ma = manual[a] ?? Int.max, mb = manual[b] ?? Int.max
            if ma != mb { return ma < mb }
            if learns {
                let sa = max(0, scores[a] ?? 0), sb = max(0, scores[b] ?? 0)
                let ea = sa >= UsageScore.threshold ? sa : 0, eb = sb >= UsageScore.threshold ? sb : 0
                if ea != eb { return ea > eb }
            }
            return (defaultIndex[a] ?? 0) < (defaultIndex[b] ?? 0)
        }
        return pinned + rest
    }

    /// What the wheel shows: the effective order without hidden items.
    static func visibleOrder(ids: [String], layout: WheelLayout, scores: [String: Double], learns: Bool) -> [String] {
        let hidden = Set(layout.hidden)
        return effectiveOrder(ids: ids, layout: layout, scores: scores, learns: learns).filter { !hidden.contains($0) }
    }
}
