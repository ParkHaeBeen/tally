#!/bin/bash
# Prints the ids that are tedious to find by hand, so you can paste them into
# config.sh. Read-only: it only asks the APIs for lists.
#
#   ./discover.sh          # everything that is configured
#   ./discover.sh plane    # just Plane
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$DIR/config.sh" ] && source "$DIR/config.sh"
WHAT="${1:-all}"

hr() { printf '\n── %s %s\n' "$1" "$(printf '─%.0s' $(seq 1 $((60 - ${#1}))))"; }

# ── Plane: workspace, projects, your user id, states ──
if [ "$WHAT" = "all" ] || [ "$WHAT" = "plane" ]; then
  if [ -n "${MW_PLANE_BASE:-}" ] && [ -n "${MW_PLANE_KEY:-}" ] && [ -n "${MW_PLANE_WS:-}" ]; then
    hr "Plane projects"
    curl -sf -H "X-Api-Key: $MW_PLANE_KEY" \
      "$MW_PLANE_BASE/api/v1/workspaces/$MW_PLANE_WS/projects/" |
      /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
rows=d.get("results", d if isinstance(d,list) else [])
print(f"{len(rows)} projects — copy the id you want into MW_PLANE_PROJECT")
for p in rows:
    print(f"  {p.get(\"id\")}  {p.get(\"identifier\",\"\"):10s} {p.get(\"name\",\"\")}")
    print(f"      → MW_PLANE_KEY_PREFIX=\"{p.get(\"identifier\",\"\")}\"")
' || echo "  failed — check MW_PLANE_BASE / MW_PLANE_KEY / MW_PLANE_WS"

    if [ -n "${MW_PLANE_PROJECT:-}" ]; then
      hr "Plane members (MW_PLANE_ME)"
      curl -sf -H "X-Api-Key: $MW_PLANE_KEY" \
        "$MW_PLANE_BASE/api/v1/workspaces/$MW_PLANE_WS/projects/$MW_PLANE_PROJECT/members/" |
        /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
for m in d.get("results", []):
    u=m.get("member") or {}
    print(f"  {u.get(\"id\")}  {u.get(\"display_name\",\"\")} <{u.get(\"email\",\"\")}>")
' || echo "  members endpoint unavailable — open any issue in Plane and copy the assignee id from the URL"

      hr "Plane states (MW_PLANE_ORDER / MW_PLANE_EXCLUDE)"
      curl -sf -H "X-Api-Key: $MW_PLANE_KEY" \
        "$MW_PLANE_BASE/api/v1/workspaces/$MW_PLANE_WS/projects/$MW_PLANE_PROJECT/states/" |
        /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
names=[]
for s in d.get("results", []):
    print(f"  {s.get(\"group\",\"\"):12s} {s.get(\"name\",\"\")}")
    names.append(s.get("name",""))
print("\n  suggestion:")
print("    MW_PLANE_EXCLUDE=\"Done,Cancelled\"")
print("    MW_PLANE_ORDER=\"" + ",".join(n for n in names if n not in ("Done","Cancelled")) + "\"")
'
    fi
  else
    [ "$WHAT" = "plane" ] && echo "Plane is not configured (MW_PLANE_BASE / MW_PLANE_KEY / MW_PLANE_WS)"
  fi
fi

# ── Jira: does the connection work, and what statuses exist ──
if [ "$WHAT" = "all" ] || [ "$WHAT" = "jira" ]; then
  if [ -n "${MW_JIRA_BASE:-}" ] && [ -n "${MW_JIRA_TOKEN:-}" ]; then
    hr "Jira"
    if [ -n "${MW_JIRA_EMAIL:-}" ]; then
      AUTH=(-u "$MW_JIRA_EMAIL:$MW_JIRA_TOKEN")
    else
      AUTH=(-H "Authorization: Bearer $MW_JIRA_TOKEN")
    fi
    curl -sf "${AUTH[@]}" "$MW_JIRA_BASE/rest/api/2/myself" |
      /usr/bin/python3 -c 'import json,sys;d=json.load(sys.stdin);print("  connected as",d.get("displayName"),"<"+str(d.get("emailAddress"))+">")' \
      || echo "  connection failed — check MW_JIRA_BASE / MW_JIRA_EMAIL / MW_JIRA_TOKEN"
    curl -sf "${AUTH[@]}" "$MW_JIRA_BASE/rest/api/2/status" |
      /usr/bin/python3 -c '
import json,sys
d=json.load(sys.stdin)
names=[]
for s in d:
    cat=(s.get("statusCategory") or {}).get("key","")
    print(f"  {cat:14s} {s.get(\"name\",\"\")}")
    names.append(s.get("name",""))
seen=[]
for n in names:
    if n not in seen: seen.append(n)
print("\n  suggestion:")
print("    MW_JIRA_ORDER=\"" + ",".join(seen[:6]) + "\"")
' 2>/dev/null || true
  else
    [ "$WHAT" = "jira" ] && echo "Jira is not configured (MW_JIRA_BASE / MW_JIRA_TOKEN)"
  fi
fi

# ── Forges: is the login usable, and are the repo paths right ──
if [ "$WHAT" = "all" ] || [ "$WHAT" = "git" ]; then
  hr "GitLab"
  if [ -n "${MW_GITLAB_TOKEN:-}" ]; then
    echo "  using MW_GITLAB_TOKEN"
  elif command -v glab >/dev/null; then
    GITLAB_HOST="${MW_GITLAB_HOST:-gitlab.com}" glab auth status 2>&1 | sed 's/^/  /' | head -6
  else
    echo "  no token and no glab — set MW_GITLAB_TOKEN or install glab"
  fi

  hr "GitHub"
  if [ -n "${MW_GITHUB_TOKEN:-}" ]; then
    echo "  using MW_GITHUB_TOKEN"
  elif command -v gh >/dev/null; then
    gh auth status 2>&1 | sed 's/^/  /' | head -6
  else
    echo "  no token and no gh — set MW_GITHUB_TOKEN or install gh"
  fi
fi

hr "next"
echo "  paste what you need into config.sh, then run:  ./fetch.sh && ./tally --dump"
