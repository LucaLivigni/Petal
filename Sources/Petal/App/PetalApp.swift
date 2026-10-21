import SwiftUI

@main
struct PetalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        // Petal lives in the menu bar; its windows are managed by the delegate.
        Settings { EmptyView() }
    }
}
