#!/bin/bash
# uninstall.sh — remove SleepLock and all its components
#
# Usage:  sudo bash uninstall.sh
#         (re-runs itself with sudo if not already root)

set -euo pipefail

log()   { echo "▶ $*"; }
done_() { echo "✓ $*"; }

if [[ "$EUID" -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo bash "$0" "$@"
fi

# ── Kill running app processes ───────────────────────────────────────────────
# Must happen before removing files — otherwise macOS returns -47 (file busy)
# on the next open attempt and the installer may fail to overwrite locked files.
# Use -9 (SIGKILL) — SIGTERM is ignored by sandboxed widget processes.
# Also kill by bundle path pattern to catch App Translocation copies.
pkill -9 -x SleepLock      2>/dev/null || true
pkill -9 -x SleepLockContro 2>/dev/null || true
pkill -9 -f "SleepLock.app" 2>/dev/null || true
sleep 1   # give processes a moment to exit before we remove their files

# ── Stop and remove the LaunchDaemon ──────────────────────────────────────────
PLIST="/Library/LaunchDaemons/com.jibeex.sleeplock.plist"
if [[ -f "$PLIST" ]]; then
    log "Unloading LaunchDaemon..."
    launchctl bootout system "$PLIST" 2>/dev/null || true
    rm -f "$PLIST"
    done_ "LaunchDaemon removed"
else
    echo "  (LaunchDaemon not installed — skipping)"
fi

# ── Remove the helper tool ────────────────────────────────────────────────────
HELPER="/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper"
if [[ -f "$HELPER" ]]; then
    rm -f "$HELPER"
    done_ "Helper removed"
fi

# ── Remove the app ────────────────────────────────────────────────────────────
for app in "/Applications/SleepLock.app" "$HOME/Applications/SleepLock.app"; do
    if [[ -d "$app" ]]; then
        log "Removing $app ..."
        rm -rf "$app"
        done_ "$app removed"
    fi
done

# ── Remove the state directory ────────────────────────────────────────────────
STATE_DIR="/Library/Application Support/com.jibeex.sleeplock"
if [[ -d "$STATE_DIR" ]]; then
    rm -rf "$STATE_DIR"
    done_ "State directory removed"
fi

# ── Forget the pkg receipt (if any) ──────────────────────────────────────────
pkgutil --forget com.jibeex.sleeplock 2>/dev/null && done_ "PKG receipt forgotten" || true

# ── Re-enable sleep (in case SleepLock left it disabled) ─────────────────────
pmset -a disablesleep 0 2>/dev/null && done_ "Sleep re-enabled" || true

echo ""
echo "SleepLock has been uninstalled."
