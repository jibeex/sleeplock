import SwiftUI

@main
struct SleepLockApp: App {
    // AppDelegate manages the IOPMAssertion and login-item registration.
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — this runs as an invisible background agent.
        // LSUIElement = YES in Info.plist keeps it out of the Dock.
        Settings { EmptyView() }
    }
}
