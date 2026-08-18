#!/bin/bash
# The smallest possible source: print a section, hard-coded.
# Copy this, replace the echo with whatever produces your items.
cat <<'JSON'
{
  "key": "reading",
  "title": "Reading",
  "hue": "amber",
  "items": [
    { "id": "1", "title": "Designing Data-Intensive Applications", "url": "https://dataintensive.net" },
    { "id": "2", "title": "A Philosophy of Software Design", "url": "" }
  ]
}
JSON
