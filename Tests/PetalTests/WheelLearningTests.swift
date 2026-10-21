import Testing
import Foundation
@testable import Petal

@Suite("Wheel learning and layout")
struct WheelLearningTests {
    private let ids = ["png", "jpg", "heic", "webp", "tiff"]

    @Test func defaultOrderWhenNothingLearned() {
        #expect(WheelArranger.visibleOrder(ids: ids, layout: WheelLayout(), scores: [:], learns: true) == ids)
    }

    @Test func usedFormatsMoveToTheFront() {
        let order = WheelArranger.visibleOrder(ids: ids, layout: WheelLayout(), scores: ["webp": 5, "tiff": 2], learns: true)
        #expect(order == ["webp", "tiff", "png", "jpg", "heic"])
    }

    @Test func aSingleStrayUseDoesNotReorder() {
        let order = WheelArranger.visibleOrder(ids: ids, layout: WheelLayout(), scores: ["webp": 0.4], learns: true)
        #expect(order == ids)
    }

    @Test func learningCanBeSwitchedOff() {
        let order = WheelArranger.visibleOrder(ids: ids, layout: WheelLayout(), scores: ["webp": 9], learns: false)
        #expect(order == ids)
    }

    @Test func pinnedComeFirstInTheirOwnOrderAndBeatLearning() {
        var layout = WheelLayout()
        layout.pinned = ["tiff", "heic"]
        let order = WheelArranger.visibleOrder(ids: ids, layout: layout, scores: ["webp": 50], learns: true)
        #expect(order == ["tiff", "heic", "webp", "png", "jpg"])
    }

    @Test func hiddenAreRemovedButStillEditable() {
        var layout = WheelLayout()
        layout.hidden = ["jpg"]
        #expect(!WheelArranger.visibleOrder(ids: ids, layout: layout, scores: [:], learns: true).contains("jpg"))
        #expect(WheelArranger.effectiveOrder(ids: ids, layout: layout, scores: [:], learns: true).contains("jpg"))
    }

    @Test func manualOrderBeatsLearnedOrder() {
        var layout = WheelLayout()
        layout.order = ["jpg", "png"]
        let order = WheelArranger.visibleOrder(ids: ids, layout: layout, scores: ["tiff": 9], learns: true)
        #expect(Array(order.prefix(2)) == ["jpg", "png"])
        #expect(order[2] == "tiff")          // items not in the manual list still follow what you use
    }

    @Test func unknownIdsInSavedLayoutsAreIgnored() {
        var layout = WheelLayout()
        layout.pinned = ["gone", "png"]
        layout.order = ["also-gone"]
        #expect(WheelArranger.visibleOrder(ids: ids, layout: layout, scores: [:], learns: true) == ids)
    }

    @Test func usageFadesWithAHalfLifeOfThirtyDays() {
        let now = Date()
        let entry = UsageScore(value: 8, last: now.addingTimeInterval(-30 * 86_400))
        #expect(abs(entry.current(at: now) - 4) < 0.001)
        let bumped = entry.bumped(at: now)
        #expect(abs(bumped.value - 5) < 0.001)
        #expect(bumped.last == now)
    }

    @MainActor
    private func freshPreferences() -> WheelPreferences {
        let suite = "petal-tests-\(UUID().uuidString)"
        return WheelPreferences(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test @MainActor func recordingReordersTheRealCatalogAndPersists() {
        let suite = "petal-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let prefs = WheelPreferences(defaults: defaults)
        let url = URL(fileURLWithPath: "/tmp/photo.jpg")
        let ops = Catalog.operations(for: [url], wheel: .convert)
        #expect(prefs.arrange(ops, kind: .image, wheel: .convert).map(\.id) == ops.map(\.id))

        for _ in 0..<3 { prefs.record(kind: .image, wheel: .convert, id: "convert.tiff") }
        let arranged = prefs.arrange(ops, kind: .image, wheel: .convert).map(\.id)
        #expect(arranged.first == "convert.tiff")
        #expect(Set(arranged) == Set(ops.map(\.id)))

        // A different file kind is not affected.
        let audio = Catalog.operations(for: [URL(fileURLWithPath: "/tmp/a.mp3")], wheel: .convert)
        #expect(prefs.arrange(audio, kind: .audio, wheel: .convert).map(\.id) == audio.map(\.id))

        // And it survives a relaunch.
        let reloaded = WheelPreferences(defaults: defaults)
        #expect(reloaded.arrange(ops, kind: .image, wheel: .convert).first?.id == "convert.tiff")
    }

    @Test @MainActor func pinHideMoveAndReset() {
        let prefs = freshPreferences()
        let ops = Catalog.operations(for: [URL(fileURLWithPath: "/tmp/photo.jpg")], wheel: .convert)
        prefs.togglePin("convert.bmp", kind: .image, wheel: .convert)
        prefs.toggleHidden("convert.png", kind: .image, wheel: .convert)
        var arranged = prefs.arrange(ops, kind: .image, wheel: .convert).map(\.id)
        #expect(arranged.first == "convert.bmp")
        #expect(!arranged.contains("convert.png"))

        // Pinning something hidden brings it back, hiding something pinned unpins it.
        prefs.togglePin("convert.png", kind: .image, wheel: .convert)
        #expect(prefs.isPinned("convert.png", kind: .image, wheel: .convert) && !prefs.isHidden("convert.png", kind: .image, wheel: .convert))
        prefs.toggleHidden("convert.bmp", kind: .image, wheel: .convert)
        #expect(!prefs.isPinned("convert.bmp", kind: .image, wheel: .convert))

        prefs.reset(kind: .image, wheel: .convert)
        arranged = prefs.arrange(ops, kind: .image, wheel: .convert).map(\.id)
        #expect(arranged == ops.map(\.id))
    }

    @Test @MainActor func foldersShareTheOtherFilesLayoutAndActionsAreGlobal() {
        let prefs = freshPreferences()
        prefs.togglePin("convert.tar", kind: .other, wheel: .convert)
        #expect(prefs.isPinned("convert.tar", kind: .folder, wheel: .convert))
        prefs.toggleHidden("actions.terminal", kind: .image, wheel: .actions)
        #expect(prefs.isHidden("actions.terminal", kind: .video, wheel: .actions))
    }
}
