#!/bin/bash
# build-release.sh — build a notarized SleepLock installer (.pkg)
#
# Prerequisites (first run only):
#   1. Developer ID Application cert  → already in Keychain
#   2. Developer ID Installer cert    → developer.apple.com/account/resources/certificates
#   3. Store notarytool credentials once:
#        xcrun notarytool store-credentials "sleeplock-notary" \
#          --apple-id YOUR_APPLE_ID \
#          --team-id AQ37XP4866 \
#          --password YOUR_APP_SPECIFIC_PASSWORD
#      (app-specific password: appleid.apple.com → Sign-In and Security)
#
# Usage:  bash build-release.sh [VERSION]
#         bash build-release.sh 1.0.0

set -euo pipefail

# ── Configuration ──────────────────────────────────────────────────────────────
SCHEME="SleepLock"
BUNDLE_ID="com.jibeex.sleeplock"
TEAM_ID="AQ37XP4866"
NOTARY_PROFILE="sleeplock-notary"
VERSION="${1:-1.0.0}"

# ── Paths ──────────────────────────────────────────────────────────────────────
BUILD_DIR="build/release"
ARCHIVE="$BUILD_DIR/SleepLock.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/SleepLock.app"
PKG_ROOT="$BUILD_DIR/pkg-root"
PKG_SCRIPTS="$BUILD_DIR/pkg-scripts"
FINAL_PKG="build/SleepLock-$VERSION.pkg"

# ── Helpers ────────────────────────────────────────────────────────────────────
log() { echo "▶ $*"; }
die() { echo "✗ $*" >&2; exit 1; }

# ── Preflight: signing identities ──────────────────────────────────────────────
log "Checking signing identities..."

APP_SIGN=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | grep "$TEAM_ID" \
  | head -1 | awk '{print $2}')
[[ -n "$APP_SIGN" ]] \
  || die "No 'Developer ID Application' cert for team $TEAM_ID in Keychain."

INSTALLER_SIGN=$(security find-identity -v \
  | grep "Developer ID Installer" | grep "$TEAM_ID" \
  | head -1 | awk '{print $2}')
[[ -n "$INSTALLER_SIGN" ]] \
  || die "No 'Developer ID Installer' cert found.\nDownload from: developer.apple.com/account/resources/certificates"

log "App sign:       $APP_SIGN"
log "Installer sign: $INSTALLER_SIGN"

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

# ── Export (Developer ID) ──────────────────────────────────────────────────────
log "Exporting with Developer ID..."
cat > "$BUILD_DIR/ExportOptions.plist" << EOXML
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key>         <string>developer-id</string>
  <key>teamID</key>         <string>$TEAM_ID</string>
  <key>signingStyle</key>   <string>automatic</string>
  <key>stripSwiftSymbols</key><true/>
</dict></plist>
EOXML

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

[[ -d "$APP" ]] || die "Export failed — $APP not found."

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

# Fix ownership (pkgbuild installs as the building user; installer runs as root)
chown root:wheel "$HELPER"  && chmod 755 "$HELPER"
chown root:wheel "$PLIST"   && chmod 644 "$PLIST"

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

# ── Build signed .pkg ──────────────────────────────────────────────────────────
log "Building signed package..."
pkgbuild \
  --root        "$PKG_ROOT" \
  --scripts     "$PKG_SCRIPTS" \
  --identifier  "$BUNDLE_ID" \
  --version     "$VERSION" \
  --install-location "/" \
  --sign        "$INSTALLER_SIGN" \
  "$FINAL_PKG"

# ── Notarize ───────────────────────────────────────────────────────────────────
log "Submitting for notarization (~1 min)..."
xcrun notarytool submit "$FINAL_PKG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

# ── Staple ─────────────────────────────────────────────────────────────────────
log "Stapling notarization ticket..."
xcrun stapler staple "$FINAL_PKG"

# ── Done ───────────────────────────────────────────────────────────────────────
log "✓  $FINAL_PKG"
log "   Upload to: https://github.com/jibeex/sleeplock/releases/new"
