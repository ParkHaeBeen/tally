#!/usr/bin/env python3
"""Example plug-in source: Linear issues assigned to you, grouped by state.

Copy it, set LINEAR_API_KEY in your environment (or in config.sh), then add
this file to MW_EXTRA_SOURCES. Tally runs it and draws whatever it prints.

The contract is small: print one section as JSON on stdout.
See ../SOURCES.md for the full shape.
"""
import json
import os
import sys
import urllib.request

API = "https://api.linear.app/graphql"
KEY = os.environ.get("LINEAR_API_KEY", "").strip()

QUERY = """
query {
  viewer {
    assignedIssues(first: 50, filter: { state: { type: { neq: "completed" } } }) {
      nodes {
        identifier
        title
        url
        updatedAt
        state { name type }
      }
    }
  }
}
"""

# Linear state types → colour names Tally understands
COLORS = {
    "started": "blue",
    "unstarted": "plain",
    "backlog": "dim",
    "triage": "amber",
    "completed": "green",
}

# Show groups in this order; anything else follows, alphabetically
ORDER = ["In Progress", "In Review", "Todo", "Backlog"]


def main():
    if not KEY:
        print("LINEAR_API_KEY is not set", file=sys.stderr)
        return 1

    req = urllib.request.Request(
        API,
        data=json.dumps({"query": QUERY}).encode(),
        headers={"Authorization": KEY, "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)

    nodes = (payload.get("data", {}).get("viewer", {})
             .get("assignedIssues", {}).get("nodes", []))

    buckets = {}
    for n in nodes:
        state = (n.get("state") or {})
        name = state.get("name") or "?"
        b = buckets.setdefault(name, {"type": state.get("type") or "", "rows": []})
        b["rows"].append({
            "id": n.get("identifier") or "",
            "title": (n.get("title") or "").strip(),
            "url": n.get("url") or "",
            "sort": n.get("updatedAt") or "",
        })

    groups = []
    for name in ORDER + sorted(k for k in buckets if k not in ORDER):
        b = buckets.get(name)
        if not b:
            continue
        b["rows"].sort(key=lambda r: r.get("sort") or "", reverse=True)
        groups.append({
            "title": name,
            "color": COLORS.get(b["type"], "plain"),
            "items": b["rows"],
        })

    json.dump({"key": "linear", "title": "Linear", "hue": "blue", "groups": groups},
              sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
