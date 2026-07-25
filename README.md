# SleepLock — Control Center Toggle

A native macOS 26 app that adds a highlighted toggle to Control Center using
`ControlWidgetToggle` (WidgetKit). No hacks, no `sudo`.

**Requires:** macOS 26+ · Xcode 26+

---

## Build & run

```sh
git clone https://github.com/jibeex/sleeplock.git
open SleepLock.xcodeproj
```

1. Sign in with your Apple ID in **Xcode › Settings › Accounts**
2. Select the **SleepLock** scheme → **Run** (`⌘R`)

Xcode will auto-provision signing and the App Group (`group.com.jibeex.sleeplock`)
under your own Team ID. If building under a different account, update the bundle
identifier prefix in both target settings.

---

## Add to Control Center

1. Open **System Settings › Control Center**
2. Scroll down to **Widgets**, find **Sleep Lock**
3. Click **+** to add it

---

## Project structure

```
SleepLock/
├── Shared/
│   └── SleepLockState.swift          ← shared between both targets
├── SleepLock/                         ← main app (background agent)
│   ├── SleepLockApp.swift
│   ├── AppDelegate.swift
│   └── SleepLock.entitlements
└── SleepLockControl/                  ← WidgetKit extension
    ├── SleepLockControl.swift
    ├── SleepLockIntent.swift
    └── SleepLockControl.entitlements
```

---

## How it works

- The **widget extension** reads and writes a shared `Bool` via App Group
  `UserDefaults`, then posts a `DistributedNotification` on toggle
- The **main app** runs silently at login (no Dock icon), listens for that
  notification, and calls `pmset` to enable or disable sleep
- The Control Center toggle highlights when sleep is disabled
