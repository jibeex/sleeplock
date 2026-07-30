# ADR-0005: Two Stores — State File for LaunchDaemon, UserDefaults for Widget

**Status:** Accepted  
**Date:** 2026-07-30

## Context

Three parties need to read or write the sleep-lock state:

1. **Main app** — non-sandboxed, user-space. Sole writer of desired state.
2. **Widget extension** — sandboxed (`com.apple.security.app-sandbox`). Must
   read state to display the correct toggle position.
3. **LaunchDaemon** (`com.jibeex.sleeplock`) — runs as root. Must be notified
   of state changes to run `pmset` via `WatchPaths`.

No single storage mechanism satisfies all three:

| Requirement | `/Library/…/state` | App Group UserDefaults |
|---|---|---|
| Writable by non-sandboxed main app | ✅ | ✅ |
| Readable by sandboxed widget | ✗ sandbox blocks `/Library/` | ✅ via entitlement + cfprefsd |
| WatchPaths-watchable by root daemon | ✅ absolute, user-agnostic path | ✗ lives under `~/Library/` |

## Decision

Maintain two stores simultaneously:

- **State file** at `/Library/Application Support/com.jibeex.sleeplock/state` —
  the LaunchDaemon's `WatchPaths` trigger.
- **App Group UserDefaults** (`group.com.jibeex.sleeplock`) — the widget's
  display-state source.

The main app (sole non-sandboxed, non-root writer) keeps both in sync on every
`setDisableSleep()` call.

## Rationale

**The state file cannot move to the App Group container:** the LaunchDaemon runs
as root before any user session. Its `WatchPaths` entry must be an absolute,
user-agnostic path. `~/Library/Group Containers/` is user-specific and breaks
multi-user support.

**The widget cannot read the state file directly:** `/Library/…` is outside the
sandbox's allowed read paths. `try? String(contentsOfFile:)` silently returns
`nil`, causing `currentValue()` to always return `false`.

## Consequences

- The main app is the single source of write truth — it always writes both stores
  on every state change.
- On startup, the state file is the authoritative source for boot state (it
  survives crashes and restarts; UserDefaults may be empty on fresh install).
  `setDisableSleep()` is called at launch with the state-file value, which
  re-syncs both stores.
- `applicationWillTerminate` is a no-op — desired state is encoded in the stores,
  not in app presence. Writing `"0"` on exit would permanently clear the sleep
  lock when launchd restarts after a crash.
