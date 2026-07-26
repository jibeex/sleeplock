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
                // Plain symbols — framework owns background shape/radius.
                // .tint() on the toggle (not .foregroundStyle on the label) is the
                // documented API per WWDC 2024: tints the symbol when the toggle is ON.
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
