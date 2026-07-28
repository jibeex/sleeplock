import Foundation

enum SleepLockState {
    // App Group suite so the widget extension and main app share the same store,
    // making the startup hint in AppDelegate reliable across processes.
    // nonisolated(unsafe): UserDefaults is documented as thread-safe.
    nonisolated(unsafe) private static let defaults: UserDefaults = {
        guard let suite = UserDefaults(suiteName: Constant.appGroupSuite) else {
            preconditionFailure("App Group '\(Constant.appGroupSuite)' is not provisioned — check entitlements.")
        }
        return suite
    }()

    static var isSleepDisabled: Bool {
        get { defaults.bool(forKey: Constant.defaultsKeyIsSleepDisabled) }
        set { defaults.set(newValue, forKey: Constant.defaultsKeyIsSleepDisabled) }
    }

    /// Forces UserDefaults to commit pending writes to disk immediately.
    /// Needed in short-lived extension processes where async writes might be
    /// lost if the process exits before the write completes.
    static func synchronize() {
        defaults.synchronize()
    }
}
