#!/bin/bash
# Reads config.sh and runs fetch.py. The widget calls this.
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$DIR/config.sh" ]; then
  echo "config.sh is missing — copy config.example.sh and edit it:" >&2
  echo "  cp config.example.sh config.sh && chmod 600 config.sh" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$DIR/config.sh"
exec /usr/bin/python3 "$DIR/fetch.py"
