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
│  │ Intent              │     │  • login item registration    │  │
│  │                     │     │                               │  │
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
│  /Library/Application Support/com.jibeex.sleeplock/state        │
│         ("0" = sleep allowed  |  "1" = sleep blocked)           │
│                     │                                           │
│                     │ WatchPaths                                │
│                     ▼                                           │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ LaunchDaemon  com.jibeex.sleeplock                       │   │
│  │                     │                                    │   │
│  │                     ▼                                    │   │
│  │ /Library/PrivilegedHelperTools/com.jibeex.sleeplock-     │   │
│  │ helper (bash)  →  pmset -a disablesleep 0 | 1            │   │
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
  └─► DistributedNotificationCenter.post(        (cross-process IPC)
          didEnable | didDisable)
         │
         ▼ (notification received)
SleepLock.app — AppDelegate
  setDisableSleep(true | false)
  ├─► write "1" | "0" → state file              (launchd WatchPaths trigger)
  ├─► UserDefaults["sleepDisabled"] = value      (App Group — widget reads this)
  └─► ControlCenter.shared.reloadControls()     (refresh widget UI)
         │
         ▼ (WatchPaths trigger — immediate)
LaunchDaemon  com.jibeex.sleeplock
  └─► helper script
        └─► pmset -a disablesleep 1 | 0   (root — works on battery + lid closed)
```

---

## Startup & Recovery Flow

```
SleepLock.app launches (kept alive by LaunchAgent — KeepAlive/SuccessfulExit=false)
         │
         ▼
applicationDidFinishLaunching
  │
  ├─ 1. STARTUP SYNC (crash/kill recovery)
  │       read state file  ← more reliable than UserDefaults
  │       setDisableSleep(bootState) → writes BOTH state file + UserDefaults
  │       (state file survives restarts; UserDefaults may be empty after
  │        fresh install or App Group container issues)
  │
  ├─ 2. NOTIFICATION OBSERVERS
  │       DistributedNotificationCenter
  │         .didEnable  → setDisableSleep(true)
  │         .didDisable → setDisableSleep(false)
  │
  └─ 3. LIFECYCLE NOTE
          Launch-at-login and crash recovery are handled by
          /Library/LaunchAgents/com.jibeex.sleeplock.app.plist
          (KeepAlive/SuccessfulExit=false — launchd restarts on crash/kill,
           not on clean exit, so the app can still quit normally)
```

---

## Termination Flow

```
applicationWillTerminate
  (no-op — state file and UserDefaults encode desired state, not app presence.
   Writing "0" on every exit would permanently lose sleep lock when launchd
   does not restart on clean exit — KeepAlive/SuccessfulExit=false.)
```

---

## IPC Summary

| Channel | Direction | Purpose | ADR |
|---|---|---|---|
| App Group UserDefaults (`group.com.jibeex.sleeplock`) | App ↔ Widget | Widget display state | [ADR-0001](docs/adr/0001-userdefaults-for-app-group-state.md) |
| DistributedNotificationCenter | Widget → App | Real-time toggle event | — |
| State file (`/Library/…/state`) | App → Daemon | launchd WatchPaths trigger | [ADR-0005](docs/adr/0005-two-stores-state-file-and-userdefaults.md) |
| WatchPaths (launchd) | Daemon ← state file | Triggers helper on any write | [ADR-0005](docs/adr/0005-two-stores-state-file-and-userdefaults.md) |
| `pmset -a disablesleep` | Daemon → kernel | Actual sleep prevention (works on battery + lid close) | [ADR-0006](docs/adr/0006-pmset-over-iopm-assertion.md) |

---

## App Group UserDefaults — Design Constraints

Four implementation rules are non-negotiable. Reverting any one reintroduces
the `"SleepLock.app" would like to access data from other apps` TCC dialog on
every widget toggle. Full rationale in the ADRs below.

| Rule | What | ADR |
|---|---|---|
| Real Team ID required | Binary must have `TeamIdentifier = AQ37XP4866`. Do not re-sign ad-hoc. | [ADR-0004](docs/adr/0004-apple-development-cert-not-ad-hoc.md) |
| Cached `let` singleton | `appGroupDefaults` must be `static let`, not `static var`. | [ADR-0002](docs/adr/0002-cached-singleton-for-appgroupdefaults.md) |
| Pre-warm at launch | Dummy read in `applicationDidFinishLaunching` registers the TCC grant first. | [ADR-0003](docs/adr/0003-prewarm-appgroup-at-launch.md) |
| No plain App Group file | `containerURL` hits TCC on every call; no caching layer exists. | [ADR-0001](docs/adr/0001-userdefaults-for-app-group-state.md) |

---

## Why Two Stores? (State File + App Group UserDefaults)

See [ADR-0005](docs/adr/0005-two-stores-state-file-and-userdefaults.md).

No single store satisfies all three parties:

| Requirement | `/Library/…/state` (launchd trigger) | App Group UserDefaults (widget) |
|---|---|---|
| Writable by non-sandboxed main app | ✅ | ✅ |
| Readable by sandboxed widget extension | ✗ — sandbox blocks `/Library/` | ✅ via app-group entitlement + cfprefsd |
| Watchable by root LaunchDaemon (WatchPaths) | ✅ absolute system-wide path | ✗ — path is user-specific (`~/Library/…`) |

---

## Build & Release Workflow

```
Developer edits code
         │
         ▼
bash build-release.sh <VERSION>
  ├─ xcodebuild archive  (signed with Team ID AQ37XP4866, Automatic signing)
  │     ⚠️  Do NOT pass CODE_SIGN_IDENTITY="" or CODE_SIGNING_ALLOWED=NO
  │     ⚠️  Do NOT re-sign with codesign -s "-" after archiving
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

Signing rationale: [ADR-0004](docs/adr/0004-apple-development-cert-not-ad-hoc.md).

---

## Signing Requirements

See [ADR-0004](docs/adr/0004-apple-development-cert-not-ad-hoc.md) for the full
certificate comparison and rationale.

**TL;DR:** Archive with Xcode Automatic signing (Apple Development certificate,
Team ID `AQ37XP4866`). Never strip or re-sign after archiving.

### Configuration at a glance

| Setting | Required value | Where |
|---|---|---|
| Team ID | `AQ37XP4866` | `project.yml` → global `DEVELOPMENT_TEAM` |
| Signing style | `Automatic` | `project.yml` → global `CODE_SIGN_STYLE` |
| Main app bundle ID | `com.jibeex.sleeplock` | `project.yml` → `SleepLock` target |
| Widget bundle ID | `com.jibeex.sleeplock.control` | `project.yml` → `SleepLockControl` target |
| Main app entitlements | App Group only (no sandbox) | `SleepLock/SleepLock.entitlements` |
| Widget entitlements | Sandbox **+** App Group | `SleepLockControl/SleepLockControl.entitlements` |
| Shared App Group ID | `group.com.jibeex.sleeplock` | Both entitlements files |

### Entitlements files (canonical content)

**`SleepLock/SleepLock.entitlements`** — main app is *not* sandboxed:

```xml
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.jibeex.sleeplock</string>
</array>
```

**`SleepLockControl/SleepLockControl.entitlements`** — widget must be sandboxed *and* declare the App Group:

```xml
<key>com.apple.security.app-sandbox</key>
<true/>
<key>com.apple.security.application-groups</key>
<array>
    <string>group.com.jibeex.sleeplock</string>
</array>
```

### Apple Developer Portal prerequisites

Registered under Team `AQ37XP4866` at [developer.apple.com](https://developer.apple.com):

1. **App Group** `group.com.jibeex.sleeplock` — under *Identifiers → App Groups*
2. **App ID** `com.jibeex.sleeplock` — App Groups capability enabled, linked to the group
3. **App ID** `com.jibeex.sleeplock.control` — App Groups capability enabled, linked to the group

### Archive command

```bash
xcodebuild archive \
  -scheme SleepLock \
  -archivePath build/SleepLock.xcarchive \
  -destination "generic/platform=macOS"
  # No CODE_SIGN_IDENTITY, CODE_SIGNING_REQUIRED, or CODE_SIGNING_ALLOWED overrides.
```

---

## Why `pmset` and not `IOPMAssertion`?

See [ADR-0006](docs/adr/0006-pmset-over-iopm-assertion.md).

| | `IOPMAssertion` | `pmset -a disablesleep 1` |
|---|---|---|
| Requires root | No | Yes (via daemon) |
| Prevents lid-close sleep on battery | ✗ | ✅ |
| Survives app termination | No | Yes (persistent) |

`IOPMAssertion` does not work on battery with the lid closed — the core use case.
`pmset` is the only reliable option.
