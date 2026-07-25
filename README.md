# SleepLock — Control Center Toggle

A native macOS 26 app that adds a proper highlighted toggle to Control Center
using `ControlWidgetToggle` (WidgetKit). No hacks.

**Requires:** macOS 26+ · Xcode 26+

---

## Project structure

```
SleepLock/
├── Shared/
│   └── SleepLockState.swift          ← add to BOTH targets
├── SleepLock/                         ← main app target
│   ├── SleepLockApp.swift
│   ├── AppDelegate.swift
│   └── SleepLock.entitlements
└── SleepLockControl/                  ← widget extension target
    ├── SleepLockControl.swift
    ├── SleepLockIntent.swift
    └── SleepLockControl.entitlements
```

---

## Xcode setup (step by step)

### 1. Create the project

1. Open Xcode → **File › New › Project**
2. Choose **macOS › App** → Next
3. Set:
   - Product Name: `SleepLock`
   - Bundle Identifier: `com.jibeex.sleeplock`
   - Language: **Swift**
   - Interface: **SwiftUI**
   - Uncheck "Include Tests"
4. Save into the `SleepLock/` folder you already have

### 2. Add the WidgetKit extension target

1. **File › New › Target**
2. Choose **macOS › Widget Extension** → Next
3. Set:
   - Product Name: `SleepLockControl`
   - Bundle Identifier: `com.jibeex.sleeplock.control`
   - Uncheck "Include Configuration Intent"
4. Click **Finish** — say **Activate** when prompted

### 3. Replace the generated source files

Delete all generated `.swift` files in both targets, then add the files from
this folder:

| File | Target(s) |
|---|---|
| `Shared/SleepLockState.swift` | SleepLock **and** SleepLockControl |
| `SleepLock/SleepLockApp.swift` | SleepLock |
| `SleepLock/AppDelegate.swift` | SleepLock |
| `SleepLockControl/SleepLockControl.swift` | SleepLockControl |
| `SleepLockControl/SleepLockIntent.swift` | SleepLockControl |

To add a file to a target: drag it into the Xcode navigator →
check the correct target(s) in the "Add to targets" sheet.

### 4. Set entitlements files

For **SleepLock** target:
- Target › Signing & Capabilities → set "Code Signing Entitlements" to
  `SleepLock/SleepLock.entitlements`

For **SleepLockControl** target:
- Target › Signing & Capabilities → set "Code Signing Entitlements" to
  `SleepLockControl/SleepLockControl.entitlements`

### 5. Enable App Groups (both targets)

For each target:
1. Signing & Capabilities → **+ Capability → App Groups**
2. Add group: `group.com.jibeex.sleeplock`

Xcode will auto-provision this if you're signed in with your Apple ID.

### 6. Set deployment target

Both targets → General → Minimum Deployments → **macOS 26.0**

### 7. Make the main app a background agent (no Dock icon)

Select the **SleepLock** target → Info tab → add key:
- `Application is agent (UIElement)` = **YES**

### 8. Build & Run

1. Select the **SleepLock** scheme → Run (`⌘R`)
2. The app starts with no visible window — it runs silently in the background

### 9. Add to Control Center

1. Open **System Settings › Control Center**
2. Scroll down to **Widgets** or search for "Sleep Lock"
3. Click **+** to add it to Control Center

---

## How it works

- **Widget extension** reads/writes `SleepLockState` (App Group UserDefaults)
  and posts a Darwin notification on toggle
- **Main app** (always running, auto-launched at login) receives the notification
  and acquires/releases an `IOPMAssertion` — no `sudo` needed
- The toggle in Control Center highlights when sleep is disabled
