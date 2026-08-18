#!/bin/bash
# Start Tally now and at every login.
set -eu
DIR="$(cd "$(dirname "$0")" && pwd)"
APP="$DIR/Tally.app"
LABEL="com.tally.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"

[ -d "$APP" ] || { echo "Tally.app is missing — run ./build.sh first" >&2; exit 1; }
[ -f "$DIR/config.sh" ] || { echo "config.sh is missing — cp config.example.sh config.sh" >&2; exit 1; }

mkdir -p "$(dirname "$PLIST")"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>$APP/Contents/MacOS/tally</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string></dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key>
  <dict><key>SuccessfulExit</key><false/></dict>
  <key>ProcessType</key><string>Interactive</string>
  <key>LimitLoadToSessionType</key><string>Aqua</string>
</dict>
</plist>
PLIST_EOF

# A GUI app needs the Aqua session, so bootstrap into the user's gui domain.
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
sleep 2

if pgrep -f "$APP/Contents/MacOS/tally" >/dev/null; then
  echo "Tally is running. Click the menu-bar item to open it."
else
  echo "Tally did not start. Try: $APP/Contents/MacOS/tally" >&2
  exit 1
fi
