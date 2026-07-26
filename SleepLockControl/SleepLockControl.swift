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
                // Adaptive palette: on dark pill (off state) → white circle + blue icon,
                // matching AirDrop/Bluetooth. On white pill (on state) → blue circle +
                // white icon, so the circle stays visible against the light background.
                Label(
                    isOn ? "Block Sleep" : "Allow Sleep",
                    systemImage: isOn ? Constant.symbolLocked : Constant.symbolUnlocked
                )
                .symbolRenderingMode(.palette)
                .foregroundStyle(
                    isOn ? Color.blue  : Color.white,   // circle fill
                    isOn ? Color.white : Color.blue     // icon inside
                )
            }
        }
        .displayName("Sleep Lock")
        .description("Prevent your Mac from sleeping.")
    }
}
