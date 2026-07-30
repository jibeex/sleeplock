# ADR-0002: appGroupDefaults Must Be a Cached let Singleton

**Status:** Accepted  
**Date:** 2026-07-30

## Context

`Constant.appGroupDefaults` provides access to the shared App Group
`UserDefaults` store. If declared as a computed property (`static var`), a new
`UserDefaults` instance is created on every access. Each new instance is a fresh
IPC request to `cfprefsd`, which re-triggers the TCC permission check. The
`"SleepLock.app" would like to access data from other apps` dialog reappears on
every toggle even after the user has already granted permission.

## Decision

Declare `appGroupDefaults` as a `static let` singleton:

```swift
// ✅ Correct
nonisolated(unsafe) static let appGroupDefaults: UserDefaults =
    UserDefaults(suiteName: appGroupSuite)!

// ❌ Wrong — new UserDefaults instance on every access → repeated TCC prompts
static var appGroupDefaults: UserDefaults {
    UserDefaults(suiteName: appGroupSuite)!
}
```

## Rationale

A `let` singleton is instantiated once. `cfprefsd` caches the TCC permission
grant for that instance for the process lifetime. All subsequent accesses reuse
the same instance and the same cached grant.

`nonisolated(unsafe)` is required because `UserDefaults` is not `Sendable`.
This is safe: all writes originate from the main actor (`AppDelegate`) or are
serialised internally by `cfprefsd`.

## Consequences

- Changing this back to a computed property immediately restores the repeated
  TCC dialog bug — no other change required to trigger it.
- The pre-warm at launch (ADR-0003) depends on this: a computed property would
  create a new instance at pre-warm time and a different instance at toggle time,
  so the cached grant would not be shared.
