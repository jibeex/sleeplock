#!/bin/bash
# SleepLock privileged helper installer
# Run once with: sudo bash install.sh
set -euo pipefail

HELPER="/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper"
PLIST="/Library/LaunchDaemons/com.jibeex.sleeplock.plist"
STATE_DIR="/Library/Application Support/com.jibeex.sleeplock"
STATE_FILE="$STATE_DIR/state"

if [[ $EUID -ne 0 ]]; then
  echo "Re-running with sudo..."
  exec sudo bash "$0" "$@"
fi

echo "Installing SleepLock privileged helper..."

# State directory — admin-group writable (app runs as admin user)
mkdir -p "$STATE_DIR"
chown root:admin "$STATE_DIR"
chmod 770 "$STATE_DIR"   # rwxrwx---: root+admin can enter; others cannot

# Preserve existing state across reinstalls; default to 0 on first install
[[ -f "$STATE_FILE" ]] || echo "0" > "$STATE_FILE"
chown root:admin "$STATE_FILE"
chmod 660 "$STATE_FILE"  # rw-rw----: root+admin can read/write; others cannot

# Helper script — reads the state file and calls pmset
cat > "$HELPER" << 'EOF'
#!/bin/bash
STATE_FILE="/Library/Application Support/com.jibeex.sleeplock/state"
[[ -f "$STATE_FILE" ]] || exit 0
state=$(tr -d '[:space:]' < "$STATE_FILE")
case "$state" in
  1) pmset -a disablesleep 1 ;;
  0) pmset -a disablesleep 0 ;;
esac
EOF
chmod 755 "$HELPER"
chown root:wheel "$HELPER"

# LaunchDaemon plist — triggered by WatchPaths whenever state file changes
cat > "$PLIST" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.jibeex.sleeplock</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Library/PrivilegedHelperTools/com.jibeex.sleeplock-helper</string>
  </array>
  <key>WatchPaths</key>
  <array>
    <string>/Library/Application Support/com.jibeex.sleeplock/state</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF
chmod 644 "$PLIST"
chown root:wheel "$PLIST"

# Load (or reload) the daemon
launchctl bootout system "$PLIST" 2>/dev/null || true
launchctl bootstrap system "$PLIST"

echo "Done. Test with:"
echo "  echo 1 > '$STATE_FILE'  # should set SleepDisabled=1"
echo "  pmset -g | grep SleepDisabled"
echo "  echo 0 > '$STATE_FILE'  # restore"
