# SleepLock — Control Center Toggle

Keep your Mac awake with a single tap. SleepLock adds a toggle to Control
Center — tap it to prevent your Mac from sleeping (lid close, idle timeout,
display off). Tap again to let it sleep normally.

Useful when you're running a long download, a build, a presentation, or anything
else that shouldn't be interrupted by sleep.

- 🌙 **Moon icon** — sleep is allowed (default)
- 🔒 **Lock icon** — sleep is blocked

Built with `ControlWidgetToggle` (WidgetKit, macOS 26). No hacks, no `sudo`,
no menubar clutter. Runs silently at login.

**Requires:** macOS 26+

---

## Install

1. Download `SleepLock-*.pkg` from the [latest release](https://github.com/jibeex/sleeplock/releases/latest)
2. Double-click the package to run the installer
   - If macOS blocks the **installer itself**: open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** for the package, then re-run it
3. Complete the installer (requires your password to install the background daemon)
4. Open **SleepLock** from `/Applications` — macOS will block it on first launch
5. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway** for SleepLock, then open it again
6. Open **System Settings → Control Center** → find **Sleep Lock** → click **+**

> SleepLock is not notarized (no paid Apple Developer account). The two "Open Anyway" prompts are a one-time step per machine — macOS permanently whitelists the app after you approve it.

---

## Build from source

**Requires:** Xcode 26+

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
