# ADR-0004: Sign with Apple Development Certificate, Not Ad-hoc

**Status:** Accepted  
**Date:** 2026-07-30

## Context

The original `build-release.sh` archived with signing fully disabled
(`CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`) then
re-signed with the ad-hoc identity (`codesign -s "-"`). The rationale was to
avoid distributing a development-certificate binary that might be rejected on
other machines.

Ad-hoc signing sets `TeamIdentifier = not set`. `cfprefsd` validates App Group
membership against the Team ID. With no Team ID, `cfprefsd` logs:

```
Using kCFPreferencesAnyUser with a container is only allowed for
System Containers, detaching from cfprefsd
```

Each process gets its own isolated in-memory defaults store. The widget always
reads `false`. The pre-warm fix (ADR-0003) has no effect because there is no
shared backing store to register against.

A paid Apple Developer Program and a Developer ID Application certificate are
not available.

## Decision

Archive using Xcode Automatic signing with the Apple Development certificate
(Team ID `AQ37XP4866`). Do not strip or re-sign after archiving.

## Rationale

`cfprefsd` does not check *trust level* — it only checks whether a non-empty
`TeamIdentifier` is present. The Apple Development certificate embeds
`TeamIdentifier = AQ37XP4866`, which is sufficient.

| | Ad-hoc (`-s "-"`) | Apple Development | Developer ID |
|---|---|---|---|
| `TeamIdentifier` | `not set` | `AQ37XP4866` | `AQ37XP4866` |
| cfprefsd / App Groups | ❌ detaches | ✅ works | ✅ works |
| Gatekeeper on other Macs | Hard block | "Open Anyway" — once | No prompt (notarized) |
| Requires paid membership | No | No (free Apple ID) | Yes ($99/yr) |

On other machines, Gatekeeper shows "Open Anyway" on first launch — a one-time,
acceptable interaction for a utility that already requires `sudo` installation.

## Consequences

- `build-release.sh` must **not** pass `CODE_SIGN_IDENTITY=""` or re-sign with
  `codesign -s "-"`. Both actions strip the Team ID and break App Group sharing.
- If a Developer ID Application certificate becomes available in the future,
  notarization (`xcrun notarytool submit` + `xcrun stapler staple`) can be added
  to eliminate the "Open Anyway" prompt without any other changes to the codebase.
