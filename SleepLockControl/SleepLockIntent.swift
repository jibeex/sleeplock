import AppIntents
import WidgetKit

let sleepLockControlKind = "com.jibeex.sleeplock.control"

struct ToggleSleepLockIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Toggle Sleep Lock"

    @Parameter(title: "Sleep Disabled")
    var value: Bool

    init() { value = false }
    init(value: Bool) { self.value = value }

    func perform() async throws -> some IntentResult {
        // Persist locally so currentValue() doesn't bounce back.
        SleepLockState.isSleepDisabled = value

        // Notify the main app. DistributedNotificationCenter matches the observer
        // in AppDelegate — user-scoped, no unsafe pointer boilerplate.
        let name = value ? SleepLockState.didEnable : SleepLockState.didDisable
        DistributedNotificationCenter.default().post(name: .init(name), object: nil)

        ControlCenter.shared.reloadControls(ofKind: sleepLockControlKind)
        return .result()
    }
}
