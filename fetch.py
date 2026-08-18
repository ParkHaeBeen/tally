#!/usr/bin/env python3
"""Collect items from configured sources into data.json for the widget to draw.

Sources are declared in config.sh. Everything here is read-only: it never
creates, updates or deletes anything on the remote side.

Built-in sources
  gitlab   merge requests you authored (+ pipeline status)
  github   pull requests you authored (+ check status)
  plane    issues assigned to you, grouped by state
  jira     issues from a JQL query, grouped by status
  ci       latest pipelines/runs per branch, plus the ones you triggered

Anything else — Linear, Notion, Asana, a CSV on disk — plugs in as a script.
List it in MW_EXTRA_SOURCES and print one section as JSON on stdout; see
SOURCES.md for the (small) contract and sources/ for working examples.

Auth
  Tokens come from config.sh. If a token is empty, the matching CLI is used
  instead (`glab` for GitLab, `gh` for GitHub), so you can rely on a login you
  already have and keep no secrets in a file at all.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

DIR = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(DIR, "data.json")

errors = []


def env(key, default=""):
    return os.environ.get(key, default).strip()


def flag(key, default=False):
    v = env(key).lower()
    if not v:
        return default
    return v in ("1", "y", "yes", "true", "on")


# ─────────────────────────── generic HTTP ───────────────────────────

def http_json(url, headers=None, timeout=45):
    req = urllib.request.Request(url, headers=headers or {})
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.load(resp)


def cli_json(exe, args, extra_env=None, timeout=40):
    """Run a CLI that prints JSON (glab/gh). Returns None on any failure."""
    path = shutil.which(exe) or exe
    if not os.path.exists(path):
        return None
    try:
        out = subprocess.run([path] + args, capture_output=True, text=True,
                             timeout=timeout, env={**os.environ, **(extra_env or {})})
        if out.returncode != 0 or not out.stdout.strip():
            return None
        return json.loads(out.stdout)
    except Exception:
        return None


# ─────────────────────────────── config ───────────────────────────────

def repos(prefix):
    """MW_GITLAB_REPOS / MW_GITHUB_REPOS — one per line:
         name | path | ci-refs (comma, - for none)
    """
    for line in env(prefix).splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = [p.strip() for p in line.split("|")]
        while len(parts) < 3:
            parts.append("")
        name, path, refs = parts[0], parts[1], parts[2]
        if not path:
            continue
        yield {
            "name": name or path.split("/")[-1],
            "path": path,
            "refs": [] if refs in ("", "-") else
                    [r.strip() for r in refs.split(",") if r.strip()],
        }


def short_names():
    out = {}
    for pair in env("MW_REPO_SHORT").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            out[k.strip()] = v.strip()
    return out


SHORTS = None


def short(name):
    return (SHORTS or {}).get(name, name)


def pretty_ref(ref):
    """refs/merge-requests/12/head → !12 · refs/pull/12/head → #12"""
    if ref.startswith("refs/merge-requests/"):
        parts = ref.split("/")
        if len(parts) > 2:
            return "!" + parts[2]
    if ref.startswith("refs/pull/"):
        parts = ref.split("/")
        if len(parts) > 2:
            return "#" + parts[2]
    return ref


# ─────────────────────────────── GitLab ───────────────────────────────

def gitlab_api(path):
    """REST with a token if given, otherwise fall back to `glab api`."""
    host = env("MW_GITLAB_HOST", "gitlab.com")
    token = env("MW_GITLAB_TOKEN")
    if token:
        url = f"https://{host}/api/v4/{path}"
        try:
            return http_json(url, {"PRIVATE-TOKEN": token})
        except Exception:
            return None
    return cli_json(env("MW_GITLAB_CLI", "glab"), ["api", path],
                    {"GITLAB_HOST": host})


def gitlab_items():
    user = env("MW_GITLAB_USER")
    items = []
    for r in repos("MW_GITLAB_REPOS"):
        enc = urllib.parse.quote(r["path"], safe="")
        q = f"projects/{enc}/merge_requests?state=opened&per_page=50"
        if user:
            q += f"&author_username={urllib.parse.quote(user)}"
        data = gitlab_api(q)
        if data is None:
            errors.append(f"{r['name']}: merge requests failed")
            continue
        for m in data:
            notes = m.get("user_notes_count") or 0
            row = {
                "id": f"!{m.get('iid')}",
                "title": (m.get("title") or "").strip(),
                "repo": short(r["name"]),
                "repoFull": r["name"],
                "ref": m.get("source_branch") or "",
                "url": m.get("web_url") or "",
                "badge": str(notes) if notes else "",
                "ok": bool(m.get("blocking_discussions_resolved")),
                "sort": m.get("updated_at") or "",
            }
            # head_pipeline is often null; ask for the MR ref pipeline directly
            ref = urllib.parse.quote(f"refs/merge-requests/{m.get('iid')}/head", safe="")
            pl = gitlab_api(f"projects/{enc}/pipelines?ref={ref}&per_page=1")
            if pl:
                row["ci"] = pl[0].get("status") or ""
                row["ciUrl"] = pl[0].get("web_url") or ""
            items.append(row)
    return items


def gitlab_ci():
    user = env("MW_GITLAB_USER")
    items, seen = [], {}
    for r in repos("MW_GITLAB_REPOS"):
        enc = urllib.parse.quote(r["path"], safe="")
        for ref in r["refs"]:
            data = gitlab_api(f"projects/{enc}/pipelines"
                              f"?ref={urllib.parse.quote(ref)}&per_page=1")
            if data is None:
                errors.append(f"{r['name']}: pipelines failed")
                continue
            if not data:
                continue
            p = data[0]
            row = {"id": ref, "title": short(r["name"]), "repo": short(r["name"]),
                   "repoFull": r["name"], "ref": ref,
                   "status": p.get("status") or "",
                   "at": p.get("updated_at") or p.get("created_at") or "",
                   "url": p.get("web_url") or "", "mine": False}
            items.append(row)
            seen[p.get("id")] = row
        if user:
            data = gitlab_api(f"projects/{enc}/pipelines"
                              f"?username={urllib.parse.quote(user)}&per_page=1")
            if data:
                p = data[0]
                if p.get("id") in seen:
                    seen[p["id"]]["mine"] = True
                else:
                    items.append({
                        "id": env("MW_LABEL_MINE", "me"),
                        "title": f"{short(r['name'])} · {pretty_ref(p.get('ref') or '')}",
                        "repo": short(r["name"]), "repoFull": r["name"],
                        "ref": p.get("ref") or "", "status": p.get("status") or "",
                        "at": p.get("updated_at") or p.get("created_at") or "",
                        "url": p.get("web_url") or "", "mine": True})
    return items


# ─────────────────────────────── GitHub ───────────────────────────────

def github_api(path):
    token = env("MW_GITHUB_TOKEN")
    api = env("MW_GITHUB_API", "https://api.github.com").rstrip("/")
    if token:
        try:
            return http_json(f"{api}/{path}", {
                "Authorization": f"Bearer {token}",
                "Accept": "application/vnd.github+json",
            })
        except Exception:
            return None
    return cli_json(env("MW_GITHUB_CLI", "gh"), ["api", path])


def github_items():
    user = env("MW_GITHUB_USER")
    items = []
    for r in repos("MW_GITHUB_REPOS"):
        data = github_api(f"repos/{r['path']}/pulls?state=open&per_page=50")
        if data is None:
            errors.append(f"{r['name']}: pull requests failed")
            continue
        for m in data:
            if user and (m.get("user") or {}).get("login") != user:
                continue
            row = {
                "id": f"#{m.get('number')}",
                "title": (m.get("title") or "").strip(),
                "repo": short(r["name"]), "repoFull": r["name"],
                "ref": (m.get("head") or {}).get("ref") or "",
                "url": m.get("html_url") or "",
                "badge": str(m.get("comments") or "") if m.get("comments") else "",
                "ok": not m.get("draft"),
                "sort": m.get("updated_at") or "",
            }
            sha = (m.get("head") or {}).get("sha")
            if sha:
                runs = github_api(f"repos/{r['path']}/commits/{sha}/check-runs")
                names = [c.get("conclusion") for c in (runs or {}).get("check_runs", [])]
                if names:
                    if any(c in ("failure", "timed_out", "cancelled") for c in names):
                        row["ci"] = "failed"
                    elif any(c is None for c in names):
                        row["ci"] = "running"
                    else:
                        row["ci"] = "success"
            items.append(row)
    return items


def github_ci():
    items = []
    for r in repos("MW_GITHUB_REPOS"):
        for ref in r["refs"]:
            data = github_api(f"repos/{r['path']}/actions/runs"
                              f"?branch={urllib.parse.quote(ref)}&per_page=1")
            if data is None:
                errors.append(f"{r['name']}: workflow runs failed")
                continue
            runs = data.get("workflow_runs") or []
            if not runs:
                continue
            w = runs[0]
            status = w.get("conclusion") or w.get("status") or ""
            status = {"failure": "failed", "cancelled": "canceled",
                      "in_progress": "running", "queued": "pending"}.get(status, status)
            items.append({"id": ref, "title": short(r["name"]), "repo": short(r["name"]),
                          "repoFull": r["name"], "ref": ref, "status": status,
                          "at": w.get("updated_at") or "",
                          "url": w.get("html_url") or "", "mine": False})
    return items


# ─────────────────────────────── Plane ───────────────────────────────

def plane_get(path):
    base = env("MW_PLANE_BASE").rstrip("/")
    return http_json(base + path, {"X-Api-Key": env("MW_PLANE_KEY")})


# state name → colour name the widget understands
STATE_COLORS = {
    "started": "blue", "unstarted": "plain", "backlog": "dim",
    "completed": "green", "cancelled": "dim",
}


def plane_groups():
    ws, proj, me = env("MW_PLANE_WS"), env("MW_PLANE_PROJECT"), env("MW_PLANE_ME")
    if not (ws and proj and env("MW_PLANE_KEY")):
        return []
    base = f"/api/v1/workspaces/{ws}/projects/{proj}"
    try:
        raw = plane_get(f"{base}/states/")["results"]
        states = {s["id"]: (s["name"], s.get("group") or "") for s in raw}
    except Exception as e:
        errors.append(f"Plane states failed: {type(e).__name__}")
        return []

    exclude = {x.strip() for x in env("MW_PLANE_EXCLUDE").split(",") if x.strip()}
    order = [x.strip() for x in env("MW_PLANE_ORDER").split(",") if x.strip()]
    colors = {}
    for pair in env("MW_PLANE_STATE_COLORS").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            colors[k.strip()] = v.strip()

    # The API ignores ?state= and ?assignees=, so page through and filter here.
    mine, cursor, pages = [], None, 0
    try:
        while pages < 40:
            q = (f"{base}/issues/?fields=sequence_id,name,state,assignees,updated_at"
                 f"&per_page=100")
            if cursor:
                q += f"&cursor={urllib.parse.quote(cursor)}"
            d = plane_get(q)
            pages += 1
            for i in d.get("results", []):
                if not me or me in (i.get("assignees") or []):
                    mine.append(i)
            if d.get("next_page_results") and d.get("next_cursor"):
                cursor = d["next_cursor"]
            else:
                break
    except Exception as e:
        errors.append(f"Plane issues failed: {type(e).__name__}")
        return []

    buckets = {}
    for i in mine:
        name, group = states.get(i.get("state"), ("?", ""))
        if name in exclude:
            continue
        buckets.setdefault(name, {"group": group, "rows": []})["rows"].append(i)

    prefix = env("MW_PLANE_KEY_PREFIX")
    base_url = env("MW_PLANE_BASE").rstrip("/")
    out = []
    for name in order + sorted(k for k in buckets if k not in order):
        b = buckets.get(name)
        if not b:
            continue
        b["rows"].sort(key=lambda x: x.get("updated_at") or "", reverse=True)
        out.append({
            "title": name,
            "color": colors.get(name, STATE_COLORS.get(b["group"], "plain")),
            "items": [{
                "id": str(r.get("sequence_id")),
                "title": (r.get("name") or "").strip(),
                "url": (f"{base_url}/{ws}/browse/{prefix}-{r.get('sequence_id')}/"
                        if prefix else
                        f"{base_url}/{ws}/projects/{proj}/issues/{r.get('id', '')}"),
            } for r in b["rows"]],
        })
    return out


# ──────────────────────────────── Jira ────────────────────────────────

# Jira status categories → colour names the widget knows
JIRA_CATEGORY_COLORS = {
    "indeterminate": "blue",   # In Progress-ish
    "new": "plain",            # To Do-ish
    "done": "green",
}


def jira_groups():
    base = env("MW_JIRA_BASE").rstrip("/")
    email = env("MW_JIRA_EMAIL")
    token = env("MW_JIRA_TOKEN")
    jql = env("MW_JIRA_JQL", "assignee = currentUser() AND resolution = Unresolved")
    if not (base and token):
        return []

    import base64
    if email:                                   # Jira Cloud: email:token
        auth = base64.b64encode(f"{email}:{token}".encode()).decode()
        headers = {"Authorization": f"Basic {auth}", "Accept": "application/json"}
    else:                                       # Jira Server/DC: bearer PAT
        headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}

    fields = "summary,status,updated"
    issues, start = [], 0
    try:
        while start < 500:
            url = (f"{base}/rest/api/2/search?jql={urllib.parse.quote(jql)}"
                   f"&fields={fields}&maxResults=100&startAt={start}")
            d = http_json(url, headers)
            batch = d.get("issues") or []
            issues += batch
            start += len(batch)
            if len(batch) < 100 or start >= (d.get("total") or 0):
                break
    except Exception as e:
        errors.append(f"Jira search failed: {type(e).__name__}")
        return []

    order = [x.strip() for x in env("MW_JIRA_ORDER").split(",") if x.strip()]
    colors = {}
    for pair in env("MW_JIRA_STATUS_COLORS").split(","):
        if "=" in pair:
            k, v = pair.split("=", 1)
            colors[k.strip()] = v.strip()

    buckets = {}
    for i in issues:
        fl = i.get("fields") or {}
        st = (fl.get("status") or {})
        name = st.get("name") or "?"
        cat = ((st.get("statusCategory") or {}).get("key") or "").lower()
        b = buckets.setdefault(name, {"cat": cat, "rows": []})
        b["rows"].append({
            "id": i.get("key") or "",
            "title": (fl.get("summary") or "").strip(),
            "url": f"{base}/browse/{i.get('key')}",
            "sort": fl.get("updated") or "",
        })

    out = []
    for name in order + sorted(k for k in buckets if k not in order):
        b = buckets.get(name)
        if not b:
            continue
        b["rows"].sort(key=lambda r: r.get("sort") or "", reverse=True)
        out.append({
            "title": name,
            "color": colors.get(name, JIRA_CATEGORY_COLORS.get(b["cat"], "plain")),
            "items": b["rows"],
        })
    return out


# ────────────────────────── plug-in sources ──────────────────────────

def extra_sections():
    """Run each script in MW_EXTRA_SOURCES and take the JSON it prints.

    A script prints either one section object or a list of them:
      {"key": "linear", "title": "Linear", "hue": "blue",
       "items":  [{"id": "ENG-12", "title": "…", "url": "…"}]}
    or with groups instead of items:
      {"key": "linear", "title": "Linear", "hue": "blue",
       "groups": [{"title": "In Progress", "color": "blue", "items": [...]}]}

    Everything is optional except key/title and items-or-groups.
    """
    out = []
    for raw in env("MW_EXTRA_SOURCES").replace("\n", ",").split(","):
        cmd = raw.strip()
        if not cmd or cmd.startswith("#"):
            continue
        path = cmd if os.path.isabs(cmd) else os.path.join(DIR, cmd)
        try:
            r = subprocess.run(["/bin/bash", "-c", f'"{path}"'] if os.path.exists(path)
                               else ["/bin/bash", "-c", cmd],
                               capture_output=True, text=True, timeout=60,
                               cwd=DIR, env=os.environ.copy())
            if r.returncode != 0:
                errors.append(f"{os.path.basename(cmd)}: exit {r.returncode}")
                continue
            data = json.loads(r.stdout)
        except Exception as e:
            errors.append(f"{os.path.basename(cmd)}: {type(e).__name__}")
            continue
        for sec in (data if isinstance(data, list) else [data]):
            if not isinstance(sec, dict) or not sec.get("key"):
                errors.append(f"{os.path.basename(cmd)}: bad shape")
                continue
            sec.setdefault("title", sec["key"])
            sec.setdefault("hue", "grey")
            out.append(sec)
    return out


# ──────────────────────────────── main ────────────────────────────────

def main():
    global SHORTS
    SHORTS = short_names()

    sections = []

    code_items = []
    if env("MW_GITLAB_REPOS"):
        code_items += gitlab_items()
    if env("MW_GITHUB_REPOS"):
        code_items += github_items()
    if code_items or env("MW_GITLAB_REPOS") or env("MW_GITHUB_REPOS"):
        code_items.sort(key=lambda x: x.get("sort", ""), reverse=True)
        sections.append({"key": "code", "title": env("MW_TITLE_CODE", "Reviews"),
                         "hue": "teal", "items": code_items})

    groups = plane_groups() + jira_groups()
    if groups:
        sections.append({"key": "issues", "title": env("MW_TITLE_ISSUES", "Issues"),
                         "hue": "blue", "groups": groups})

    ci = []
    if flag("MW_CI", True):
        ci += gitlab_ci()
        ci += github_ci()
        rank = {"running": 0, "pending": 0, "created": 0, "failed": 1}
        ci.sort(key=lambda x: (not x.get("mine"), rank.get(x.get("status"), 2)))
    if ci:
        sections.append({"key": "ci", "title": env("MW_TITLE_CI", "CI"),
                         "hue": "grey", "items": ci})

    sections += extra_sections()

    # Order sections the way the config asks; unknown keys keep their own order.
    wanted = [x.strip() for x in env("MW_SECTION_ORDER").split(",") if x.strip()]
    if wanted:
        def rank(sec):
            key = sec.get("key", "")
            return wanted.index(key) if key in wanted else len(wanted)
        sections.sort(key=rank)

    if not sections:
        print("nothing configured — see config.example.sh", file=sys.stderr)
        return 1

    total = sum(len(s.get("items", [])) + sum(len(g.get("items", []))
                for g in s.get("groups", [])) for s in sections)
    if total == 0 and errors:
        # Every source failed — leave the previous data.json in place so the
        # widget keeps showing the last known state instead of an empty list.
        print("all sources failed — keeping previous data.json", file=sys.stderr)
        return 1

    payload = {
        "fetchedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sections": sections,
        "errors": errors,
    }
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, ensure_ascii=False, indent=1)
    os.replace(tmp, OUT)

    n_issues = sum(len(g["items"]) for g in groups)
    n_extra = sum(len(s.get("items", [])) + sum(len(g.get("items", []))
                  for g in s.get("groups", [])) for s in sections
                  if s.get("key") not in ("code", "issues", "ci"))
    print(f"reviews {len(code_items)} · issues {n_issues} · ci {len(ci)}"
          + (f" · extra {n_extra}" if n_extra else "")
          + (f" · errors {len(errors)}" if errors else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
