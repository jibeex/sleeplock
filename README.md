# SleepLock — Control Center Toggle

Keep your Mac awake with a single tap. SleepLock adds a toggle to Control
Center — tap it to prevent your Mac from sleeping (lid close, idle timeout,
display off). Tap again to let it sleep normally.

Useful when you're running a long download, a build, a presentation, or anything
else that shouldn't be interrupted by sleep.

- 🌙 **Moon icon** — sleep is allowed (default)
- 🔒 **Lock icon** — sleep is blocked

Built with `ControlWidgetToggle` (WidgetKit, macOS 26). No menubar clutter.
Runs silently at login.

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

> SleepLock is signed with an Apple Development certificate (free Apple ID), not a
> paid Developer ID. The two "Open Anyway" prompts are a one-time step per machine —
> macOS permanently whitelists the app after you approve it.

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
under your own Team ID. If building under a different account, update
`DEVELOPMENT_TEAM` in `project.yml` and regenerate the project with
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

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
│   └── Constant.swift                 ← shared constants (App Group ID, UserDefaults key, symbols)
├── SleepLock/                         ← main app (background agent, no Dock icon)
│   ├── AppDelegate.swift
│   └── SleepLock.entitlements
├── SleepLockControl/                  ← WidgetKit Control Center extension
│   ├── SleepLockControl.swift
│   ├── SleepLockIntent.swift
│   └── SleepLockControl.entitlements
├── docs/adr/                          ← Architecture Decision Records
├── ARCHITECTURE.md                    ← system overview, flows, IPC table
├── project.yml                        ← XcodeGen project definition
└── build-release.sh                   ← builds the .pkg installer
```

---

## How it works

```
User taps toggle (Control Center)
        │
        ▼
SleepLockControl.appex
  writes new state → App Group UserDefaults
  posts DistributedNotification (didEnable / didDisable)
        │
        ▼
SleepLock.app  (LaunchAgent — always running, no Dock icon)
  writes "1" or "0" → /Library/Application Support/com.jibeex.sleeplock/state
  re-syncs App Group UserDefaults → widget reads correct state
  reloads Control Center widget
        │
        ▼ (WatchPaths trigger — immediate)
LaunchDaemon  com.jibeex.sleeplock  (runs as root)
  reads state file → pmset -a disablesleep 1 | 0
```

- **`pmset -a disablesleep`** is the only reliable way to prevent sleep with the
  lid closed on battery. `IOPMAssertion` (the user-space alternative) does not
  work in that scenario.
- **Two stores** (state file + App Group UserDefaults) exist because no single
  store satisfies all three parties: the root LaunchDaemon needs a
  `WatchPaths`-watchable absolute path; the sandboxed widget can only read App
  Group UserDefaults via `cfprefsd`.
- **Apple Development signing** is required — not just preferred. Ad-hoc signing
  sets `TeamIdentifier = not set`, causing `cfprefsd` to give each process its
  own isolated store, breaking App Group sharing entirely.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for full flow diagrams and
[`docs/adr/`](docs/adr/) for the rationale behind each key design decision.
