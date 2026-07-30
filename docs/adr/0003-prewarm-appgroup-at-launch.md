# ADR-0003: Pre-warm App Group Access at Main App Launch

**Status:** Accepted  
**Date:** 2026-07-30

## Context

macOS TCC grants the app-group access permission to the process that **first**
requests it in a session. Without intervention, the widget extension
(`SleepLockControl.appex`) is always the first requester — it touches the App
Group `UserDefaults` on every toggle. macOS fires the
`"SleepLock.app" would like to access data from other apps` dialog each time,
even after the user clicks "Allow". This is not a bug that can be fixed by
caching alone; it is a property of how TCC grants first-request permissions.

## Decision

The main app performs a dummy read of `appGroupDefaults` in
`applicationDidFinishLaunching`, before any widget interaction can occur:

```swift
// Pre-warm: register TCC permission once at app launch.
// ⚠️  DO NOT REMOVE — see docs/adr/0003-prewarm-appgroup-at-launch.md
_ = Constant.appGroupDefaults.bool(forKey: Constant.stateKey)
```

## Rationale

By reading `appGroupDefaults` at launch, the main app registers the TCC
permission under its own identity. `cfprefsd` then recognises both the main app
and the widget as belonging to the same App Group and shares the cached grant
between them for the session lifetime. The dialog appears at most once (on a
clean install or after a TCC reset) and never again.

This only works when:
1. `appGroupDefaults` is a cached `let` singleton (ADR-0002) — a new instance at
   pre-warm time would not share its grant with the instance used at toggle time.
2. The binary has a real Team ID (ADR-0004) — `cfprefsd` must be backed by a
   real shared store; ad-hoc signing detaches it entirely.

## Consequences

- The dummy read line looks like a dead no-op. **It must not be removed or
  "cleaned up"** — removing it immediately restores the TCC dialog on every toggle.
- Sequencing matters: the pre-warm must happen before the first widget toggle,
  which is guaranteed by placing it at the top of `applicationDidFinishLaunching`.
