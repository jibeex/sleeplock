#!/bin/bash
# build-release.sh — build a SleepLock installer (.pkg)
#
# The package is unsigned. macOS will show a Gatekeeper warning on first open.
# Users dismiss it via System Settings → Privacy & Security → "Open Anyway".
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
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$TEAM_ID"

[[ -d "$APP" ]] || die "Archive failed — $APP not found."

# ── Package root ───────────────────────────────────────────────────────────────
log "Building package root..."
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/Library/LaunchDaemons"
mkdir -p "$PKG_ROOT/Library/PrivilegedHelperTools"

cp -R "$APP" "$PKG_ROOT/Applications/"

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

# ── Postinstall script ─────────────────────────────────────────────────────────
mkdir -p "$PKG_SCRIPTS"
cat > "$PKG_SCRIPTS/postinstall" << 'POST_EOF'
#!/bin/bash
set -euo pipefail
STATE_DIR="/Library/Application Support/com.jibeex.sleeplock"
STATE_FILE="$STATE_DIR/state"
HELPER="/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper"
PLIST="/Library/LaunchDaemons/com.jibeex.sleeplock.plist"

# Remove quarantine so macOS doesn't block the app on first launch.
# The installer runs as root, so this clears it for all users.
xattr -rd com.apple.quarantine /Applications/SleepLock.app 2>/dev/null || true

# Fix ownership (pkgbuild captures files as the building user; installer runs as root)
chown root:wheel "$HELPER" && chmod 755 "$HELPER"
chown root:wheel "$PLIST"  && chmod 644 "$PLIST"

# State directory — admin-group writable (app runs as admin user)
mkdir -p "$STATE_DIR"
chown root:admin "$STATE_DIR" && chmod 770 "$STATE_DIR"
[[ -f "$STATE_FILE" ]] || echo "0" > "$STATE_FILE"
chown root:admin "$STATE_FILE" && chmod 660 "$STATE_FILE"

# Load (or reload) the daemon
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"
exit 0
POST_EOF
chmod +x "$PKG_SCRIPTS/postinstall"

# ── Build .pkg (unsigned) ──────────────────────────────────────────────────────
log "Building package..."
pkgbuild \
  --root             "$PKG_ROOT" \
  --scripts          "$PKG_SCRIPTS" \
  --identifier       "$BUNDLE_ID" \
  --version          "$VERSION" \
  --install-location "/" \
  "$FINAL_PKG"

# ── Done ───────────────────────────────────────────────────────────────────────
log "✓  $FINAL_PKG"
log ""
log "   macOS will block on first open — users:"
log "   System Settings → Privacy & Security → Open Anyway"
log ""
log "   Upload to: https://github.com/jibeex/sleeplock/releases/new"
