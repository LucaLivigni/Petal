import Foundation

/// Everything an operation needs to run. Values only, so it can cross isolation boundaries.
nonisolated struct JobContext: Sendable {
    var inputs: [URL]
    var policy: OutputPolicy
    var imageQuality: Double
    var terminalBundleID: String
    var progress: @Sendable (Double) -> Void

    func reportStep(_ index: Int, of total: Int, fraction: Double = 0) {
        guard total > 0 else { return }
        progress((Double(index) + fraction) / Double(total))
    }
}

nonisolated struct JobOutcome: Sendable {
    var outputs: [URL] = []
    var message: String?
    /// Text the runner should place on the clipboard (e.g. recognised text).
    var clipboardText: String?
}

nonisolated struct PetalError: LocalizedError, Sendable {
    let text: String
    init(_ text: String) { self.text = text }
    var errorDescription: String? { text }
}

/// One wedge on a wheel.
nonisolated struct PetalAction: Identifiable, Sendable {
    enum Wheel: String, Sendable, CaseIterable, Identifiable {
        case convert, tools, actions
        var id: String { rawValue }
        var title: String {
            switch self {
            case .convert: "Convert"
            case .tools: "Tools"
            case .actions: "Actions"
            }
        }
        var symbol: String {
            switch self {
            case .convert: "arrow.triangle.2.circlepath"
            case .tools: "wand.and.sparkles"
            case .actions: "bolt.fill"
            }
        }
    }

    /// How the wedge is drawn: a format name in rounded type, or an SF Symbol.
    enum Glyph: Sendable, Equatable {
        case format(String)
        case symbol(String)
    }

    let id: String
    let title: String
    let subtitle: String?
    let glyph: Glyph
    /// For conversions: the extension of the file this produces, so the UI can preview its name.
    let outputExtension: String?
    let perform: @concurrent @Sendable (JobContext) async throws -> JobOutcome

    init(id: String, title: String, subtitle: String? = nil, glyph: Glyph, outputExtension: String? = nil,
         perform: @escaping @concurrent @Sendable (JobContext) async throws -> JobOutcome) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.glyph = glyph
        self.outputExtension = outputExtension
        self.perform = perform
    }
}
