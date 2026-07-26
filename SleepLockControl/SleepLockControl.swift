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
                // .circle.fill symbols provide the white-icon-in-circle appearance
                // that matches system toggles (Bluetooth, AirDrop, etc.).
                Label(
                    isOn ? "Block Sleep" : "Allow Sleep",
                    systemImage: isOn ? Constant.symbolLocked : Constant.symbolUnlocked
                )
            }
            .tint(.blue)
        }
        .displayName("Sleep Lock")
        .description("Prevent your Mac from sleeping.")
    }
}
