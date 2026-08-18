#!/bin/bash
# Turn the output of any command into a section.
#
# This is the escape hatch: if a thing has a CLI, or you can produce lines with
# a shell one-liner, it can live in Tally without writing any real code.
#
# Configure it from config.sh — no need to edit this file:
#
#   export CMD_KEY="branches"
#   export CMD_TITLE="Stale branches"
#   export CMD_HUE="amber"                       # teal | blue | amber | grey
#   export CMD_LINE='git -C ~/src/api for-each-ref --sort=committerdate \
#                      --format="%(refname:short)" refs/heads | head -5'
#   export MW_EXTRA_SOURCES="sources/command.example.sh"
#
# Each output line becomes one row. Want ids and links too? Print tab-separated
# fields instead:  id <TAB> title <TAB> url
#
# More ideas that need nothing but a CLI you already have:
#   kubectl get pods --field-selector=status.phase!=Running -o name
#   gh run list --limit 5 --json name,conclusion --template '...'
#   brew outdated
#   docker ps --format '{{.Names}}\t{{.Status}}'
#   tail -5 ~/notes/todo.txt
set -u

export CMD_KEY="${CMD_KEY:-command}"
export CMD_TITLE="${CMD_TITLE:-Command}"
export CMD_HUE="${CMD_HUE:-grey}"
LIMIT="${CMD_LIMIT:-20}"
LINE="${CMD_LINE:-ls -1 \"$HOME\"}"

read -r -d '' TO_JSON <<'PY'
import json, os, sys

items = []
for n, line in enumerate(sys.stdin.read().splitlines(), 1):
    line = line.rstrip()
    if not line:
        continue
    parts = line.split("\t")
    if len(parts) >= 2:                      # id <TAB> title [<TAB> url]
        items.append({"id": parts[0].strip(),
                      "title": parts[1].strip(),
                      "url": parts[2].strip() if len(parts) > 2 else ""})
    else:                                    # a plain line
        items.append({"id": str(n), "title": line, "url": ""})

json.dump({"key": os.environ.get("CMD_KEY", "command"),
           "title": os.environ.get("CMD_TITLE", "Command"),
           "hue": os.environ.get("CMD_HUE", "grey"),
           "items": items}, sys.stdout, ensure_ascii=False)
PY

eval "$LINE" 2>/dev/null | head -n "$LIMIT" | /usr/bin/python3 -c "$TO_JSON"
