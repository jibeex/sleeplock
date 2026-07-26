# SleepLock — Architecture & Workflow

## System Components

```
┌─────────────────────────────────────────────────────────────────┐
│  User Space (sandboxed)                                         │
│                                                                 │
│  ┌─────────────────────┐     ┌───────────────────────────────┐  │
│  │ SleepLockControl    │     │ SleepLock.app                 │  │
│  │ .appex              │     │ (LSUIElement — no Dock icon)  │  │
│  │                     │     │                               │  │
│  │ ControlWidget       │     │ AppDelegate                   │  │
│  │ ToggleSleepLock     │     │  • startup sync               │  │
│  │ Intent              │     │  • 30s drift correction       │  │
│  │                     │     │  • login item registration    │  │
│  └────────┬────────────┘     └──────────────┬────────────────┘  │
│           │                                 │                   │
│           │  App Group UserDefaults         │                   │
│           │  group.com.jibeex.sleeplock     │                   │
│           └─────────────────────────────────┘                   │
│                       shared state                              │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  Root / System Space                                            │
│                                                                 │
│  /Library/Application Support/com.jibeex.sleeplock/state       │
│         ("0" = sleep allowed  |  "1" = sleep blocked)          │
│                     │                                           │
│                     │ WatchPaths                                │
│                     ▼                                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ LaunchDaemon  com.jibeex.sleeplock                       │   │
│  │                     │                                    │   │
│  │                     ▼                                    │   │
│  │ /Library/PrivilegedHelperTools/com.jibeex.sleeplock-     │   │
│  │ helper (bash)  →  pmset -a disablesleep 0 | 1           │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Toggle Flow (user taps widget)

```
User taps toggle in Control Center
         │
         ▼
SleepLockControl.appex
  ControlWidgetToggle { isOn in … }
  .tint(.blue)
         │
         ▼
ToggleSleepLockIntent.perform()
  ├─► UserDefaults[isSleepDisabled] = value     (App Group — widget reads this)
  ├─► DistributedNotificationCenter.post(        (cross-process IPC)
  │       didEnable | didDisable)
  └─► ControlCenter.shared.reloadControls()     (refresh widget UI)
         │
         ▼ (notification received)
SleepLock.app — AppDelegate
  setDisableSleep(true | false)
  └─► write "1" | "0" → state file
         │
         ▼ (WatchPaths trigger — immediate)
LaunchDaemon  com.jibeex.sleeplock
  └─► helper script
        └─► pmset -a disablesleep 1 | 0   (root — works on battery + lid closed)
```

---

## Startup & Recovery Flow

```
SleepLock.app launches (login item via SMAppService)
         │
         ▼
applicationDidFinishLaunching
  │
  ├─ 1. STARTUP SYNC (crash/kill recovery)
  │       read UserDefaults[isSleepDisabled]
  │       write authoritative value → state file
  │       (ensures state file matches intent after unclean exit)
  │
  ├─ 2. NOTIFICATION OBSERVERS
  │       DistributedNotificationCenter
  │         .didEnable  → setDisableSleep(true)
  │         .didDisable → setDisableSleep(false)
  │
  ├─ 3. DRIFT CORRECTION TIMER  (every 30s)
  │       compare UserDefaults ↔ state file
  │       if mismatch → re-write state file
  │       (guards against external pmset changes or partial failures)
  │
  └─ 4. LOGIN ITEM REGISTRATION
          if SMAppService.mainApp.status == .notRegistered
            → register()   (skip if .enabled or .requiresApproval)
```

---

## Termination Flow

```
applicationWillTerminate
  ├─► syncTimer.invalidate()
  └─► setDisableSleep(false)
        └─► write "0" → state file
              └─► WatchPaths → pmset -a disablesleep 0
```

---

## IPC Summary

| Channel | Direction | Purpose |
|---|---|---|
| App Group UserDefaults | Widget ↔ App | Persistent toggle state (survives restarts) |
| DistributedNotificationCenter | Widget → App | Real-time toggle event |
| State file (`/Library/…/state`) | App → Daemon | Root-privilege relay |
| WatchPaths (launchd) | Daemon ← state file | Triggers helper on any write |
| `pmset -a disablesleep` | Daemon → kernel | Actual sleep prevention (works on battery + lid close) |

---

## Build & Release Workflow

```
Developer edits code
         │
         ▼
bash build-release.sh <VERSION>
  ├─ xcodebuild archive  (Xcode dev cert, automatic signing)
  ├─ codesign --force -s "-"  (strip dev cert → ad-hoc)
  │     SleepLockControl.appex  (entitlements: sandbox + app-group only)
  │     SleepLock.app           (entitlements: app-group only)
  └─ pkgbuild → SleepLock-<VERSION>.pkg
         │
         ▼
git tag v<VERSION> && git push origin v<VERSION>
         │
         ▼
gh release create v<VERSION> SleepLock-<VERSION>.pkg
         │
         ▼
User installs:
  sudo installer -pkg SleepLock-<VERSION>.pkg -target /
  open /Applications/SleepLock.app
  → System Settings → Privacy & Security → Open Anyway  (Gatekeeper, first launch only)
```

---

## Why Ad-hoc Signing?

Standard dev-cert builds embed `com.apple.application-identifier` and
`com.apple.developer.team-identifier` entitlements that are tied to the
signing identity. On other machines, launchd rejects the daemon spawn with
**POSIX 163 / RBSRequestErrorDomain Code=5** because `TeamIdentifier=not set`
(ad-hoc) doesn't match those entitlements.

Fix: strip the dev cert, re-sign with `"-"` (ad-hoc) using explicit minimal
entitlement files that contain **only** the app-group identifier — no
team-specific keys.

---

## Why `pmset` and not `IOPMAssertion`?

| | `IOPMAssertion` | `pmset -a disablesleep 1` |
|---|---|---|
| Requires root | No | Yes (via daemon) |
| Prevents lid-close sleep on battery | ✗ | ✓ |
| Survives app termination | No | Yes (persistent) |

`IOPMAssertion` only works reliably on AC power. `pmset` is the only way to
keep the Mac awake with the lid closed on battery, which is the core use case.
