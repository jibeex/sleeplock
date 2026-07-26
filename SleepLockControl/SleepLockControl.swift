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
                // Explicit palette rendering: filled circle in blue, lock cutout in white.
                // This matches the system-control pattern (Bluetooth, AirDrop) where the
                // icon is a solid-color circle with a white symbol inside.
                // Avoids .tint() on the toggle, which blends the tint into the circle and
                // icon simultaneously and produces a washed-out light-blue on the white pill.
                Label(
                    isOn ? "Block Sleep" : "Allow Sleep",
                    systemImage: isOn ? Constant.symbolLocked : Constant.symbolUnlocked
                )
                .symbolRenderingMode(.palette)
                .foregroundStyle(.blue, .white)
            }
        }
        .displayName("Sleep Lock")
        .description("Prevent your Mac from sleeping.")
    }
}
