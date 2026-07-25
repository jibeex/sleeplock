import WidgetKit
import SwiftUI

@main
struct SleepLockBundle: WidgetBundle {
    var body: some Widget {
        SleepLockControl()
    }
}

// StaticControlConfiguration + ControlValueProvider — no configuration intent needed.
struct SleepLockValueProvider: ControlValueProvider {
    var previewValue: Bool { false }

    func currentValue() async throws -> Bool {
        SleepLockState.isSleepDisabled
    }
}

struct SleepLockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: sleepLockControlKind,
            provider: SleepLockValueProvider()
        ) { isDisabled in
            // Pass an instance with the next value already set.
            ControlWidgetToggle(
                "Sleep Lock",
                isOn: isDisabled,
                action: ToggleSleepLockIntent(value: !isDisabled)
            ) { isOn in
                // ControlWidget only renders systemImage — no custom SwiftUI views.
                // moon.zzz.fill (moon + ZZZ) clearly signals sleep when allowed;
                // lock.fill clearly signals blocked when active.
                // The transition between the two states tells the full story.
                Label(
                    isOn ? "Block Sleep" : "Allow Sleep",
                    systemImage: isOn ? "lock.fill" : "moon.zzz.fill"
                )
            }
        }
        .displayName("Sleep Lock")
        .description("Prevent your Mac from sleeping.")
    }
}
