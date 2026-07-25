import Foundation

enum SleepLockState {
    // Darwin notifications carry the action as the notification name —
    // two names because Darwin payloads are not supported.
    static let didEnable  = "com.jibeex.sleeplock.didEnable"
    static let didDisable = "com.jibeex.sleeplock.didDisable"

    private static let defaultsKey = "isSleepDisabled"
    // App Group suite so the widget extension and main app share the same store,
    // making the startup hint in AppDelegate reliable across processes.
    // nonisolated(unsafe): UserDefaults is documented as thread-safe.
    nonisolated(unsafe) private static let defaults = UserDefaults(suiteName: "group.com.jibeex.sleeplock") ?? .standard

    static var isSleepDisabled: Bool {
        get { defaults.bool(forKey: defaultsKey) }
        set { defaults.set(newValue, forKey: defaultsKey) }
    }
}
