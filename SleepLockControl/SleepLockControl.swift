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
            kind: Constant.controlKind,
            provider: SleepLockValueProvider()
        ) { isDisabled in
            // Pass an instance with the next value already set.
            ControlWidgetToggle(
                "Sleep Lock",
                isOn: isDisabled,
                action: ToggleSleepLockIntent(value: !isDisabled)
            ) { isOn in
                // Plain symbols — framework owns the background shape/radius (matches
                // system controls). Icon color: blue on white pill (ON), white on dark (OFF).
                Label(
                    isOn ? "Block Sleep" : "Allow Sleep",
                    systemImage: isOn ? Constant.symbolLocked : Constant.symbolUnlocked
                )
                .foregroundStyle(isOn ? Color.blue : Color.white)
            }
        }
        .displayName("Sleep Lock")
        .description("Prevent your Mac from sleeping.")
    }
}
