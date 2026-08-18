#!/bin/bash
# Stop Tally and remove it from login items. Leaves your files alone.
set -u
LABEL="com.tally.agent"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
rm -f "$PLIST"
pkill -f "/Tally.app/Contents/MacOS/tally" 2>/dev/null || true
echo "Tally stopped and removed from login items."
echo "Your settings and notes are untouched. Delete the folder to remove everything."
