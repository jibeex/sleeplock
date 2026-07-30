import Foundation

enum Constant {
    static let controlKind                = "com.jibeex.sleeplock.control"
    // System-wide path — accessible to the non-sandboxed main app. Used as the
    // launchd WatchPaths trigger; writing here fires the privileged helper that
    // runs `pmset -a disablesleep`. NOT readable by the sandboxed widget extension.
    static let stateFilePath              = "/Library/Application Support/com.jibeex.sleeplock/state"
    // App Group suite name — used for both appGroupDefaults (widget IPC)
    // and the App Group entitlement declared in both targets' entitlements files.
    static let appGroupSuite = "group.com.jibeex.sleeplock"

    // App Group UserDefaults — shared between the main app and the Control widget.
    // Must be a `let` singleton: a new UserDefaults instance on every access re-triggers
    // the TCC permission dialog even after the user has granted access.
    // See docs/adr/0001-userdefaults-for-app-group-state.md
    //     docs/adr/0002-cached-singleton-for-appgroupdefaults.md
    // nonisolated(unsafe): UserDefaults is not Sendable; safe because all writes come
    // from the main actor (AppDelegate) or are serialised by cfprefsd internally.
    nonisolated(unsafe) static let appGroupDefaults: UserDefaults = UserDefaults(suiteName: appGroupSuite)!

    // Key for the sleep-disabled state in App Group UserDefaults.
    static let stateKey = "sleepDisabled"
    static let symbolLocked               = "lock.fill"
    static let symbolUnlocked             = "moon.zzz.fill"
    static let notificationDidEnable      = "com.jibeex.sleeplock.didEnable"
    static let notificationDidDisable     = "com.jibeex.sleeplock.didDisable"
}
