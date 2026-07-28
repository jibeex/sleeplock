import AppIntents
import WidgetKit

struct ToggleSleepLockIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Sleep Lock"

    @Parameter(title: "Sleep Disabled")
    var value: Bool

    init() { value = false }
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        // Persist locally so currentValue() doesn't bounce back.
        SleepLockState.isSleepDisabled = value
        // Force the write to disk before this short-lived extension process exits.
        // UserDefaults writes are async; without this the plist may never be committed
        // if the process terminates quickly, causing the main app's drift-correction
        // timer to read false and reset the state file to "0".
        SleepLockState.synchronize()

        // Notify the main app. DistributedNotificationCenter matches the observer
        // in AppDelegate — user-scoped, no unsafe pointer boilerplate.
        let name = value ? Constant.notificationDidEnable : Constant.notificationDidDisable
        DistributedNotificationCenter.default().post(name: .init(name), object: nil)

        ControlCenter.shared.reloadControls(ofKind: Constant.controlKind)
        return .result()
    }
}
