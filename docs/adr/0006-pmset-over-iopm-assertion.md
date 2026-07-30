# ADR-0006: Use pmset Instead of IOPMAssertion

**Status:** Accepted  
**Date:** 2026-07-30

## Context

Preventing macOS from sleeping can be done via two mechanisms:

- **`IOPMAssertion`** — user-space API, no root required, tied to the calling
  process's lifetime.
- **`pmset -a disablesleep 1`** — system-wide persistent setting, requires root,
  survives process termination.

The core use case for SleepLock is preventing sleep with the **lid closed on
battery** (e.g. running a long job on a MacBook with the screen closed). This is
the scenario `IOPMAssertion` cannot handle.

## Decision

Use `pmset -a disablesleep 1/0` via a privileged bash helper run by a root
`LaunchDaemon`.

## Rationale

| | `IOPMAssertion` | `pmset -a disablesleep` |
|---|---|---|
| Requires root | No | Yes (via daemon) |
| Prevents lid-close sleep on battery | ✗ | ✅ |
| Survives app termination | No | Yes (persistent) |

`IOPMAssertion` only works reliably on AC power. On battery with the lid closed,
macOS ignores it and sleeps anyway. `pmset` is persistent and system-wide —
the only reliable option for the core use case.

## Consequences

- Requires a root `LaunchDaemon` (`com.jibeex.sleeplock`) and a privileged helper
  script at `/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper`.
- The `pmset` setting is persistent across app restarts and crashes. This is
  intentional — it means the sleep lock survives a crash and is restored when
  the app relaunches. It is also why `applicationWillTerminate` must not write
  `"0"` to the state file (see ADR-0005).
- The `LaunchDaemon` resets `pmset` whenever the state file changes (`WatchPaths`),
  providing immediate recovery after any failure mode.
