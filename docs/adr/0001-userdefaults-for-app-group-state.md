# ADR-0001: Use UserDefaults(suiteName:) for App Group State Sharing

**Status:** Accepted  
**Date:** 2026-07-30

## Context

The widget extension (`SleepLockControl.appex`) needs to read the toggle state
written by the main app. The widget is sandboxed and cannot access `/Library/…`
paths directly.

An earlier version wrote state to a plain file via
`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`. This called
the macOS TCC daemon on every invocation. The TCC daemon has no caching layer for
`containerURL` — it treats each call as a new access request and shows the
`"SleepLock.app" would like to access data from other apps` dialog on every widget
toggle, even after the user clicks "Allow". There is no workaround for this.

## Decision

Use `UserDefaults(suiteName: "group.com.jibeex.sleeplock")` backed by `cfprefsd`.

## Rationale

`cfprefsd` is the only App Group IPC mechanism on macOS where the TCC grant
persists across calls and can be pre-registered at launch (see ADR-0003).
Once the first successful IPC handshake completes, `cfprefsd` caches the
permission for the process lifetime. Subsequent reads and writes do not
re-trigger the TCC dialog.

`containerURL` bypasses `cfprefsd` entirely and contacts the TCC daemon directly
every time — there is no way to pre-warm or cache this permission path.

## Consequences

- Requires a real Apple Team ID in the binary — `cfprefsd` validates App Group
  membership against the signing identity. See ADR-0004.
- `appGroupDefaults` must be a cached singleton, not a computed property.
  See ADR-0002.
- The main app must pre-warm the shared store at launch. See ADR-0003.
- **Do not restore the plain-file approach** — the TCC dialog returns immediately
  with no fix available.
