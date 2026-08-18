#!/usr/bin/env python3
"""Example plug-in source: Notion database rows assigned to you, grouped by status.

Set these in config.sh, then add this file to MW_EXTRA_SOURCES:

    export NOTION_TOKEN="ntn_…"            # notion.so/my-integrations
    export NOTION_DATABASE="…"             # the database id from its URL
    export NOTION_PERSON="you@example.com" # optional: filter to your rows
    export NOTION_STATUS_PROP="Status"     # optional: property to group by

Then share the database with your integration (Notion → ⋯ → Connections),
or the API returns 404 even with a valid token.
"""
import json
import os
import sys
import urllib.request

TOKEN = os.environ.get("NOTION_TOKEN", "").strip()
DB = os.environ.get("NOTION_DATABASE", "").strip()
PERSON = os.environ.get("NOTION_PERSON", "").strip()
STATUS_PROP = os.environ.get("NOTION_STATUS_PROP", "Status").strip()

API = "https://api.notion.com/v1"
HEADERS = {
    "Authorization": f"Bearer {TOKEN}",
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
}

# Notion status colours → the colour names Tally understands
COLORS = {
    "blue": "blue", "purple": "purple", "green": "green",
    "yellow": "amber", "orange": "amber", "red": "amber",
    "gray": "dim", "brown": "dim", "default": "plain", "pink": "purple",
}


def post(path, body):
    req = urllib.request.Request(f"{API}/{path}", data=json.dumps(body).encode(),
                                headers=HEADERS, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def plain_text(prop):
    """Notion wraps text in rich-text arrays; flatten whichever shape we get."""
    if not prop:
        return ""
    kind = prop.get("type")
    if kind == "title":
        return "".join(t.get("plain_text", "") for t in prop.get("title", []))
    if kind == "rich_text":
        return "".join(t.get("plain_text", "") for t in prop.get("rich_text", []))
    return ""


def main():
    if not (TOKEN and DB):
        print("NOTION_TOKEN and NOTION_DATABASE are required", file=sys.stderr)
        return 1

    rows, cursor = [], None
    while True:
        body = {"page_size": 100}
        if cursor:
            body["start_cursor"] = cursor
        data = post(f"databases/{DB}/query", body)
        rows += data.get("results", [])
        cursor = data.get("next_cursor")
        if not data.get("has_more") or not cursor or len(rows) > 300:
            break

    buckets = {}
    for page in rows:
        props = page.get("properties") or {}

        # Optional: keep only rows where you are one of the people
        if PERSON:
            people = []
            for p in props.values():
                if p.get("type") == "people":
                    people += [
                        (u.get("person") or {}).get("email", "") or u.get("name", "")
                        for u in p.get("people", [])
                    ]
            if PERSON not in people:
                continue

        title = ""
        for p in props.values():
            if p.get("type") == "title":
                title = plain_text(p)
                break
        if not title:
            continue

        status = props.get(STATUS_PROP) or {}
        node = status.get("status") or status.get("select") or {}
        name = node.get("name") or "No status"
        color = COLORS.get(node.get("color", "default"), "plain")

        b = buckets.setdefault(name, {"color": color, "rows": []})
        b["rows"].append({
            "id": (page.get("id") or "")[:4],
            "title": title,
            "url": page.get("url") or "",
            "sort": page.get("last_edited_time") or "",
        })

    groups = []
    for name, b in buckets.items():
        b["rows"].sort(key=lambda r: r.get("sort") or "", reverse=True)
        groups.append({"title": name, "color": b["color"], "items": b["rows"]})

    json.dump({"key": "notion", "title": "Notion", "hue": "grey", "groups": groups},
              sys.stdout, ensure_ascii=False)
    return 0


if __name__ == "__main__":
    sys.exit(main())
