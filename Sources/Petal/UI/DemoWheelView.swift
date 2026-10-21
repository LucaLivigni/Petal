import SwiftUI

/// A self-playing wheel for onboarding and settings previews. It reacts to the accent colour live.
struct DemoWheelView: View {
    var showsDetails = false
    var cyclesWheels = true
    var scale: CGFloat = 1

    @State private var model = WheelModel()
    @State private var timer: Timer?

    private var canvas: CGSize { showsDetails ? WheelGeometry.canvas : WheelGeometry.compactCanvas }

    var body: some View {
        WheelView(model: model, showsDetails: showsDetails)
            .scaleEffect(scale)
            .frame(width: canvas.width * scale, height: canvas.height * scale)
            .onAppear(perform: start)
            .onDisappear { timer?.invalidate() }
    }

    private func start() {
        model.loadDemo()
        model.isVisible = true
        var tick = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [model, cyclesWheels] _ in
            MainActor.assumeIsolated {
                tick += 1
                if cyclesWheels, tick % 9 == 0 {
                    let all = PetalAction.Wheel.allCases
                    model.loadDemo(wheel: all[(all.firstIndex(of: model.wheel)! + 1) % all.count])
                }
                model.hovered = tick % max(1, model.slots.count)
            }
        }
    }
}
