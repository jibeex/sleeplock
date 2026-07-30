import AppIntents
import os.log

struct ToggleSleepLockIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Sleep Lock"

    @Parameter(title: "Sleep Disabled")
    var value: Bool

    init() { value = false }
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        os_log(.default, "🔵 perform() START: value=%{public}@", String(value))

        // Write to app group UserDefaults
        Constant.appGroupDefaults.set(value, forKey: Constant.stateKey)
        Constant.appGroupDefaults.synchronize()

        let verified = Constant.appGroupDefaults.bool(forKey: Constant.stateKey)
        os_log(.default, "🟢 perform() SUCCESS: wrote=%{public}@ verified=%{public}@",
               String(value), String(verified))

        // Notify the main app via DistributedNotificationCenter.
        // The main app writes the state file (launchd WatchPaths trigger) and
        // re-syncs UserDefaults, keeping both stores in agreement.
        let name = value ? Constant.notificationDidEnable : Constant.notificationDidDisable
        DistributedNotificationCenter.default().post(name: .init(name), object: nil)

        return .result()
    }
}
