#!/bin/bash
# build-release.sh — build a SleepLock installer (.pkg)
#
# The app is built with the development cert, then re-signed with an ad-hoc
# identity ("-") before packaging.  The postinstall script deliberately sets
# a quarantine attribute on the installed app so macOS shows "Open Anyway" in
# System Settings → Privacy & Security on first launch.  Users click it once
# and the app is permanently whitelisted on that machine.
#
# Usage:  bash build-release.sh [VERSION]
#         bash build-release.sh 1.0.0

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SCHEME="SleepLock"
BUNDLE_ID="com.jibeex.sleeplock"
TEAM_ID="AQ37XP4866"
VERSION="${1:-1.0.0}"

# ── Paths ──────────────────────────────────────────────────────────────────────
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/SleepLock.xcarchive"
APP="$ARCHIVE/Products/Applications/SleepLock.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
FINAL_PKG="build/SleepLock-$VERSION.pkg"

# ── Helpers ────────────────────────────────────────────────────────────────────
log() { echo "▶ $*"; }
die() { echo "✗ $*" >&2; exit 1; }

# ── Clean ──────────────────────────────────────────────────────────────────────
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$(dirname "$FINAL_PKG")"

# ── Archive ────────────────────────────────────────────────────────────────────
log "Archiving $SCHEME $VERSION..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE" \
  -destination "generic/platform=macOS" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

[[ -d "$APP" ]] || die "Archive failed — $APP not found."

# ── Package root ───────────────────────────────────────────────────────────────
log "Building package root..."
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/Library/LaunchDaemons"
mkdir -p "$PKG_ROOT/Library/LaunchAgents"
mkdir -p "$PKG_ROOT/Library/PrivilegedHelperTools"
cp -R "$APP" "$PKG_ROOT/Applications/"

# ── Re-sign with ad-hoc identity ───────────────────────────────────────────────
# The app is built with a development certificate that is only trusted on the
# developer's own machine.  Gatekeeper rejects it on every other machine with
# "cannot be opened", even when spctl --add runs in the postinstall.
#
# Fix: re-sign with the ad-hoc identity ("-").  We use explicit entitlement
# files that keep only what is functionally needed and strip the team-specific
# keys (com.apple.application-identifier, com.apple.developer.team-identifier).
# macOS 26 enforces that those keys match the signing identity; leaving them
# in the ad-hoc binary (TeamIdentifier=not set) causes launchd to reject the
# spawn with POSIX 163 "Launchd job spawn failed".
log "Re-signing with ad-hoc identity (strips dev cert and team entitlements)..."
STAGED_APP="$PKG_ROOT/Applications/SleepLock.app"

# Remove the provisioning profile — it is tied to the dev cert and invalid
# under ad-hoc signing.  Without it the OS will not try to validate the cert.
rm -f "$STAGED_APP/Contents/embedded.provisionprofile"
find "$STAGED_APP" -name "*.appex" -exec rm -f '{}/Contents/embedded.provisionprofile' \;

# Bundle the uninstall script inside the app — idiomatic macOS, co-located with the bundle.
# Must be done before re-signing so the file is covered by the ad-hoc signature.
mkdir -p "$STAGED_APP/Contents/Resources"
cp uninstall.sh "$STAGED_APP/Contents/Resources/uninstall.sh"
chmod 755 "$STAGED_APP/Contents/Resources/uninstall.sh"

# Minimal entitlements for the main app (not sandboxed — only needs App Group).
cat > "$BUILD_DIR/app.entitlements.plist" << 'ENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.application-groups</key>
    <array><string>group.com.jibeex.sleeplock</string></array>
</dict></plist>
ENT_EOF

# Minimal entitlements for the widget extension (sandboxed + App Group).
cat > "$BUILD_DIR/appex.entitlements.plist" << 'ENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.application-groups</key>
    <array><string>group.com.jibeex.sleeplock</string></array>
</dict></plist>
ENT_EOF

# Sign nested code (extensions, frameworks) first, then the top-level bundle.
find "$STAGED_APP" -name "*.appex" | while IFS= read -r ext; do
    codesign --force --sign - \
        --entitlements "$BUILD_DIR/appex.entitlements.plist" \
        --timestamp=none \
        "$ext"
done
codesign --force --sign - \
    --entitlements "$BUILD_DIR/app.entitlements.plist" \
    --timestamp=none \
    "$STAGED_APP"

# Verify the ad-hoc signature is self-consistent.
codesign -v "$STAGED_APP" || die "Ad-hoc re-signing failed."

# Helper script — reads state file and calls pmset as root
cat > "$PKG_ROOT/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper" << 'HELPER_EOF'
#!/bin/bash
STATE_FILE="/Library/Application Support/com.jibeex.sleeplock/state"
[[ -f "$STATE_FILE" ]] || exit 0
state=$(tr -d '[:space:]' < "$STATE_FILE")
case "$state" in
  1) pmset -a disablesleep 1 ;;
  0) pmset -a disablesleep 0 ;;
esac
HELPER_EOF
chmod 755 "$PKG_ROOT/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper"

# LaunchDaemon plist — triggered by WatchPaths whenever state file changes
cat > "$PKG_ROOT/Library/LaunchDaemons/com.jibeex.sleeplock.plist" << 'PLIST_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key>
  <string>com.jibeex.sleeplock</string>
  <key>ProgramArguments</key>
  <array><string>/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper</string></array>
  <key>WatchPaths</key>
  <array><string>/Library/Application Support/com.jibeex.sleeplock/state</string></array>
  <key>RunAtLoad</key><true/>
</dict></plist>
PLIST_EOF
chmod 644 "$PKG_ROOT/Library/LaunchDaemons/com.jibeex.sleeplock.plist"


# LaunchAgent plist — keeps the app alive across sleep/wake and crashes.
# KeepAlive/SuccessfulExit=false: launchd restarts on crash/kill but not on
# clean exit, so graceful shutdowns (applicationWillTerminate) are respected.
#
# ProgramArguments wraps /bin/sh -c so launchd always has a binary to run even
# when the app is moved to Trash or permanently deleted.  On each startup the
# wrapper branches:
#   App present → exec the real binary (normal path, zero overhead)
#   App missing → silent bootout from launchd domain (no root needed) +
#                 osascript dialog prompting the user to rm the root-owned
#                 plist with admin privileges.  Re-prompts on the next login
#                 if the user cancels or lacks admin access.
cat > "$PKG_ROOT/Library/LaunchAgents/com.jibeex.sleeplock.app.plist" << 'AGENT_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.jibeex.sleeplock.app</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/sh</string>
    <string>-c</string>
    <string>APP=/Applications/SleepLock.app
PLIST=/Library/LaunchAgents/com.jibeex.sleeplock.app.plist
if [ ! -d "$APP" ]; then
  launchctl bootout gui/$(id -u) "$PLIST" 2>/dev/null || true
  sleep 3
  osascript \
    -e 'display dialog "SleepLock was removed from Applications. Remove its launch agent? (requires admin password)" with title "SleepLock Cleanup" buttons {"Cancel", "Remove"} default button "Remove" with icon caution' \
    -e 'if button returned of result is "Remove" then' \
    -e 'do shell script "rm -f /Library/LaunchAgents/com.jibeex.sleeplock.app.plist" with administrator privileges' \
    -e 'end if' \
    2>/dev/null || true
  exit 0
fi
exec "$APP/Contents/MacOS/SleepLock"</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict>
    <!-- Restart on crash/OS-kill; do NOT restart on clean applicationWillTerminate -->
    <key>SuccessfulExit</key><false/>
  </dict>
  <key>ProcessType</key><string>Background</string>
</dict></plist>
AGENT_EOF
chmod 644 "$PKG_ROOT/Library/LaunchAgents/com.jibeex.sleeplock.app.plist"

# ── Preinstall script ──────────────────────────────────────────────────────────
# Detect upgrades before the pkg overwrites /Applications/SleepLock.app so the
# postinstall can skip adding quarantine.  Quarantine is only needed on a fresh
# install (to surface the "Open Anyway" prompt); re-adding it on every upgrade
# creates a new App Translocation mount that forces WidgetKit to reload the
# extension from a stale cached path, requiring a logout to clean up.
mkdir -p "$PKG_SCRIPTS"
cat > "$PKG_SCRIPTS/preinstall" << 'PRE_EOF'
#!/bin/bash
[[ -d /Applications/SleepLock.app ]] && touch /tmp/.sleeplock-upgrade || true
exit 0
PRE_EOF
chmod +x "$PKG_SCRIPTS/preinstall"

# ── Postinstall script ─────────────────────────────────────────────────────────
mkdir -p "$PKG_SCRIPTS"
cat > "$PKG_SCRIPTS/postinstall" << 'POST_EOF'
#!/bin/bash
set -euo pipefail
STATE_DIR="/Library/Application Support/com.jibeex.sleeplock"
STATE_FILE="$STATE_DIR/state"
HELPER="/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper"
PLIST="/Library/LaunchDaemons/com.jibeex.sleeplock.plist"

# ── Upgrade cleanup: remove artifacts left by older versions ──────────────────
# v1.0.13 installed the uninstall script at /usr/local/bin/sleeplock-uninstall.
# v1.0.14+ bundles it inside the app at Contents/Resources/uninstall.sh instead.
rm -f /usr/local/bin/sleeplock-uninstall

# macOS 15+ runs Gatekeeper on every app launch regardless of quarantine.
# Ad-hoc signed apps are blocked with "cannot be opened" and — critically —
# the "Open Anyway" button only appears in Privacy & Security when the app
# HAS a quarantine attribute.  The pkg installer does not set quarantine on
# the files it lays down, so we add it on fresh installs only.
#
# On upgrades we skip it: re-adding quarantine each time creates a new App
# Translocation mount that forces WidgetKit to load the extension from a
# stale cached path (the previous version), requiring a logout to clean up.
# The preinstall script drops /tmp/.sleeplock-upgrade when the app already
# exists at install time.
if [[ ! -f /tmp/.sleeplock-upgrade ]]; then
    QTIME=$(printf '%x' "$(date +%s)")
    xattr -w com.apple.quarantine "0083;${QTIME};SleepLock Installer;" \
        /Applications/SleepLock.app 2>/dev/null || true
fi
rm -f /tmp/.sleeplock-upgrade

# Fix ownership (pkgbuild captures files as the building user; installer runs as root)
chown root:wheel "$HELPER" && chmod 755 "$HELPER"
chown root:wheel "$PLIST"  && chmod 644 "$PLIST"

# State directory — world-writable so any logged-in user's SleepLock instance
# can control sleep state.  The security tradeoff is minor: any local process
# can flip a text toggle; the actual pmset call requires the root LaunchDaemon.
mkdir -p "$STATE_DIR"
chown root:wheel "$STATE_DIR" && chmod 777 "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo "0" > "$STATE_FILE"
chown root:wheel "$STATE_FILE" && chmod 666 "$STATE_FILE"

# Load (or reload) the LaunchDaemon (system-wide, root)
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

# ── Upgrade path: flush stale Control widget extension ────────────────────────
# On upgrade, the old SleepLockControl.appex may still be running from an App
# Translocation path created by the previous version.  Kill it and re-register
# so WidgetKit picks up the new binary in the current session — no logout needed.
killall SleepLockControl 2>/dev/null || true
pluginkit -a /Applications/SleepLock.app/Contents/PlugIns/SleepLockControl.appex \
    2>/dev/null || true
killall ControlCenter 2>/dev/null || true

# Bootstrap the LaunchAgent for the currently logged-in console user.
# The installer runs as root; we must explicitly target the user's session.
AGENT_PLIST="/Library/LaunchAgents/com.jibeex.sleeplock.app.plist"
CONSOLE_USER=$(stat -f "%Su" /dev/console 2>/dev/null || echo "")
if [[ -n "$CONSOLE_USER" && "$CONSOLE_USER" != "root" ]]; then
    CONSOLE_UID=$(id -u "$CONSOLE_USER" 2>/dev/null || echo "")
    if [[ -n "$CONSOLE_UID" ]]; then
        launchctl bootout  gui/"$CONSOLE_UID" "$AGENT_PLIST" 2>/dev/null || true
        launchctl bootstrap gui/"$CONSOLE_UID" "$AGENT_PLIST"
    fi
fi
exit 0
POST_EOF
chmod +x "$PKG_SCRIPTS/postinstall"

# ── Build .pkg (unsigned) ──────────────────────────────────────────────────────
log "Building package..."

# Generate a component plist so we can mark the bundle as non-relocatable.
# Without this, pkgbuild's relocation logic will install the app wherever an
# existing copy of com.jibeex.sleeplock is found (e.g. ~/Applications/) instead
# of the canonical /Applications/ path, which then breaks the postinstall script.
COMPONENTS_PLIST="$BUILD_DIR/components.plist"
pkgbuild --analyze --root "$PKG_ROOT" "$COMPONENTS_PLIST"
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENTS_PLIST"

pkgbuild \
  --root             "$PKG_ROOT" \
  --scripts          "$PKG_SCRIPTS" \
  --identifier       "$BUNDLE_ID" \
  --version          "$VERSION" \
  --install-location "/" \
  --component-plist  "$COMPONENTS_PLIST" \
  "$FINAL_PKG"

# ── Done ───────────────────────────────────────────────────────────────────────
log "✓  $FINAL_PKG"
log ""
log "   macOS will block on first open — users:"
log "   System Settings → Privacy & Security → Open Anyway"
log ""
log "   Upload to: https://github.com/jibeex/sleeplock/releases/new"
