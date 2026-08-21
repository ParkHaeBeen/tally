#!/bin/bash
# Tally configuration — copy this file to config.sh and edit it.
#
#   cp config.example.sh config.sh && chmod 600 config.sh
#
# config.sh is git-ignored, so tokens never leave your machine.
# Everything Tally reads is read-only: it never writes to GitLab/GitHub/Plane.

# ── Look ──────────────────────────────────────────────────
# titanium | sage | ice | copper | deep | soft
export MW_THEME="titanium"
# ko | en   (widget labels, menu items, banner titles)
export MW_LANG="en"

# ── Refresh ───────────────────────────────────────────────
export MW_REFRESH_HOURS="4"          # normal interval
export MW_FAST_SECONDS="120"         # while a pipeline is running / after a push
# Folders to watch for pushes. When a remote-tracking ref changes under any of
# these, Tally refreshes ~25s later. Leave empty to disable.
export MW_WATCH_DIRS="$HOME/src"
export MW_NOTIFY_CI="all"            # all | fail | n
# Banner sounds. Use a macOS sound name (Basso Blow Bottle Frog Funk Glass Hero
# Morse Ping Pop Purr Sosumi Submarine Tink), a path to your own .aiff/.wav/.mp3,
# or leave empty for silence. Audition them with:
#   for s in /System/Library/Sounds/*.aiff; do echo $(basename $s .aiff); afplay $s; done
export MW_SOUND_OK="Tink"
export MW_SOUND_FAIL="Basso"
export MW_SOUND_RUN=""
export MW_SOUND_ALARM="Ping"         # alarms get their own sound
export MW_ROWS_PER_SECTION="8"       # rows per group before "+N more" (0 = all)
export MW_MAX_HEIGHT_PCT="55"        # window height cap, % of screen
export MW_WIDTH="320"                # window width in points (260-560)

# Text size and spacing. The menu bar and notification banners are not affected.
# Raising the scale without widening the window truncates more titles.
export MW_FONT_SCALE="1.0"           # 1.0 = as built; 0.8-1.6
export MW_HEAD_SIZE="12.5"           # section title size, points (9-20); ignores the scale
export MW_HOVER="y"                  # tint the row under the mouse (y/n)
export MW_HOVER_STRENGTH="60"        # how strong that tint is, 0-100
export MW_MR_LABEL="branch"          # what leads an MR row: branch | number
export MW_LINE_SPACING="2.5"         # gap between lines, points (0-14)
export MW_ROW_GAP="1"                # gap between items, points (0-14)
# Alarms. Add them in the widget (+ Add alarm) — this file only sets defaults.
# They are stored in alarm.txt, one per line and readable by hand:
#   <when> <HH:MM>  <what to say>  [sound=Glass] [snooze=10]
#   when: daily · mon,wed,fri · 1st · 08-25 (yearly) · 2026-12-25 (once)
#   a leading "off " keeps the alarm but switches it off
# A missed alarm stays lit for this many hours, then goes quiet — so a weekend
# away does not greet you with a pile of them. `./tally --alarms` shows how
# each line was read.
export MW_ALARM_GRACE_HOURS="12"

export MW_FOLDED_DEFAULT="issues"    # sections folded on first run: code,issues,memo,ci

# Section headings shown in the widget
export MW_TITLE_CODE="Reviews"
export MW_TITLE_ISSUES="Issues"
export MW_TITLE_CI="CI"
export MW_TITLE_MEMO="Notes"
export MW_TITLE_ALARM="Alarms"

# Long repo names eat the title. Shorten them here.
export MW_REPO_SHORT="my-very-long-service-name=svc"

# ── GitLab ────────────────────────────────────────────────
# Leave MW_GITLAB_TOKEN empty to reuse an existing `glab auth login`.
export MW_GITLAB_HOST="gitlab.com"
export MW_GITLAB_TOKEN=""
export MW_GITLAB_USER="your-username"   # only your MRs are listed
# one repo per line:  name | full/path/to/project | ci refs (comma, - for none)
export MW_GITLAB_REPOS="
web|acme/backend/web|main,develop
api|acme/backend/api|main
"

# ── GitHub ────────────────────────────────────────────────
# Leave MW_GITHUB_TOKEN empty to reuse an existing `gh auth login`.
export MW_GITHUB_API="https://api.github.com"
export MW_GITHUB_TOKEN=""
export MW_GITHUB_USER=""                # your login; empty = all open PRs
export MW_GITHUB_REPOS="
# tally|yourname/tally|main
"

# ── Plane (issue tracker) ─────────────────────────────────
# Create a key at Plane → Settings → API tokens.
export MW_PLANE_BASE=""                 # e.g. https://plane.example.com or https://app.plane.so
export MW_PLANE_KEY=""
export MW_PLANE_WS=""                   # workspace slug
export MW_PLANE_PROJECT=""              # project id (uuid) — run ./discover.sh to find it
export MW_PLANE_ME=""                   # your user id (uuid) — ./discover.sh prints it
export MW_PLANE_KEY_PREFIX=""           # project identifier, e.g. ENG → links use ENG-123

# States to hide, and the order to show the rest in.
export MW_PLANE_EXCLUDE="Done,Cancelled"
export MW_PLANE_ORDER="In Progress,Todo,Backlog,QA"
# Optional per-state colours: blue | green | amber | purple | plain | dim
export MW_PLANE_STATE_COLORS="In Progress=blue,QA=purple,Backlog=dim"

# ── Jira (instead of, or alongside, Plane) ────────────────
# Cloud: set MW_JIRA_EMAIL + an API token from id.atlassian.com
# Server/DC: leave the email empty and use a personal access token
export MW_JIRA_BASE=""                  # e.g. https://acme.atlassian.net
export MW_JIRA_EMAIL=""
export MW_JIRA_TOKEN=""
export MW_JIRA_JQL="assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"
export MW_JIRA_ORDER="In Progress,In Review,To Do,Backlog"
export MW_JIRA_STATUS_COLORS="In Progress=blue,In Review=purple,Backlog=dim"

# ── Anything else: plug in your own script ────────────────
# Each script prints one section as JSON on stdout. See SOURCES.md.
# Examples live in sources/ — copy one and edit.
export MW_EXTRA_SOURCES="
# sources/linear.example.py
# sources/static.example.sh
"

# Order of sections in the widget. "notes" is the local notes section and
# "alarms" the local alarm section. Sections you leave out still show, at
# the end — which is why alarms lands below CI unless you say otherwise.
export MW_SECTION_ORDER="code,issues,notes,ci,alarms"

# ── Misc ──────────────────────────────────────────────────
export MW_LABEL_MINE="me"               # tag on pipelines you triggered
export MW_CI="y"                        # y | n — show the CI section at all
