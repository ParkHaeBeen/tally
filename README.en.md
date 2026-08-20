# Tally

A menu-bar widget for macOS that keeps the things you are on the hook for in one
place: **your open reviews, your issues, your notes, and your CI.**

Click the menu-bar item and the list drops down under it. Click again and it
closes. It does not steal focus, so you can keep it open while you work.

<p align="center">
  <img src="docs/menubar.png" alt="Tally in the menu bar" width="232"><br>
  <img src="docs/screenshot.png" alt="The Tally panel" width="320">
</p>

<p align="center"><sub>The counts live in the menu bar; the panel drops down when you click them.<br>Sample data — your own repos, issues and notes go in the same places.</sub></p>

- **Read-only.** Tally never writes to GitLab, GitHub, Plane or Jira. It only reads.
- **No dependencies.** Compiled with the `swiftc` that ships with macOS
  developer tools; data fetching uses the system `python3`. Nothing to install,
  nothing vendored.
- **Your tokens stay yours.** They live in `config.sh`, which is git-ignored.
  If you already ran `glab auth login` or `gh auth login`, you can keep *no*
  tokens on disk at all.

## Why

Reviews stall because nobody notices the comments. Issues drift because they
live in a tab you closed. CI breaks on a branch you pushed twenty minutes ago.
None of that needs a dashboard — it needs a glance.

## Install

Requires macOS 13+ and the Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/ParkHaeBeen/tally.git ~/tally
cd ~/tally
cp config.example.sh config.sh && chmod 600 config.sh
$EDITOR config.sh          # see "Configure" below
./build.sh                 # compiles and makes Tally.app
./install.sh               # starts it, and starts it at login
```

Check it works without opening the window:

```bash
./fetch.sh                 # prints: reviews 5 · issues 18 · ci 4
./tally --dump             # prints the widget contents as text
```

To remove it completely: `./uninstall.sh && rm -rf ~/tally`.

## Configure

Everything lives in `config.sh`. The parts people change first:

```bash
export MW_LANG="en"                  # en | ko
export MW_REFRESH_HOURS="4"          # normal refresh interval
export MW_GITLAB_USER="your-name"    # only your MRs are listed
export MW_GITLAB_REPOS="
api|acme/backend/api|main
web|acme/frontend/web|main,develop
"                                    # name | path | branches to watch CI on
```

`./discover.sh` prints the ids that are annoying to find by hand — your Plane
workspace, project and user id, or a Jira connection check.

### Sources

| Source | What you get | Auth |
|---|---|---|
| GitLab | your open MRs, unresolved-comment counts, pipeline per MR | token, or an existing `glab` login |
| GitHub | your open PRs, comment counts, check runs | token, or an existing `gh` login |
| Plane | issues assigned to you, grouped by state | API key |
| Jira | issues from any JQL, grouped by status | Cloud API token or server PAT |
| Notes | a plain text file you own | — |
| CI | latest pipeline per branch, plus the ones you triggered | same as the forge |

Using something else? A source is a script that prints JSON — about ten lines.
And if the thing has a CLI, `sources/command.example.sh` turns any command's
output into a section with no code at all:

```bash
export CMD_TITLE="Unhealthy pods"
export CMD_LINE='kubectl get pods --field-selector=status.phase!=Running -o name'
export MW_EXTRA_SOURCES="sources/command.example.sh"
```

See [SOURCES.md](SOURCES.md) for the contract and `sources/` for working
examples (a static list, any command, Linear via GraphQL, Notion databases).

## How it behaves

**Refresh.** Every four hours, which is enough for reviews and issues. But when
a pipeline is running it switches to every two minutes, and when you push it
refreshes ~25 seconds later — so CI is current when it matters and quiet when it
does not. Pushes are noticed by watching the remote-tracking refs under
`MW_WATCH_DIRS` (no git hooks, no config changes to your repos).

**Banners.** When a pipeline *you* triggered changes state, a banner slides in
at the top right: green ✓, red ✗, amber ◍, with a sound for pass and fail.
Click it to open the pipeline. Pipelines other people triggered stay silent.
Pick the sounds with `MW_SOUND_OK` / `MW_SOUND_FAIL` / `MW_SOUND_RUN` — a macOS
sound name, a path to your own file, or empty for silence. Audition them with
`./tally --sound-test`.

**Folding.** Every section folds, and so does every group inside Issues. Each
group shows the first 8 rows and a `+ N more`. The window height follows the
content up to 55% of the screen, then scrolls. Fold state is remembered.

**Search.** Type in the box and reviews, issues and notes filter together by
title. Ids match too, so `42` finds `!42`. `ESC` clears it.

**Notes.** A note is a title plus optional detail, kept in `memo.txt` — the
title shows in the list, the detail unfolds when clicked. Finishing a note moves
it to `done.txt` rather than deleting it, and the menu can undo the last one.
There is a small CLI too:

```bash
./memo ask DBA about the query plan
./memo -d needs the prod EXPLAIN first
./memo -l
```

**Offline.** Away from the VPN, fetches fail. Tally keeps the last data and
labels it — `fetch failed · 5h ago` in red — rather than showing an empty list
that looks like good news.

## Files

| file | what |
|---|---|
| `widget.swift` | the window, menu bar, banners, search, folding, notes |
| `fetch.py` | reads your sources, writes `data.json` |
| `config.sh` | your settings and tokens (git-ignored) |
| `make-icon.swift` | draws the app icon in code → `icon.icns` |
| `build.sh` | compile, bundle, ad-hoc sign |
| `install.sh` / `uninstall.sh` | login item on/off |
| `sources/` | example plug-in sources |

State files (`data.json`, `memo.txt`, `done.txt`, `ui-state.json`, `tally.log`)
are all git-ignored and all plain text, so you can read or edit them by hand.

## Notes and limits

- **Notifications are drawn by Tally, not by macOS.** Unsigned apps are denied
  notification permission, and macOS pins the notification icon to the app icon
  anyway — so pass and fail would look identical. A window Tally draws itself can
  change with the state.
- The app is **ad-hoc signed** (`codesign --sign -`). That is enough to run and
  to sit in your login items; it is not notarised, so do not expect it to pass
  Gatekeeper on someone else's machine without a build of their own.
- Plane's REST API ignores `?state=` and `?assignees=`, so Tally pages through
  the project and filters locally. That costs about eight seconds; at a
  four-hour interval nobody notices.
- Multi-monitor: the window anchors under the menu-bar item on whichever screen
  holds it. If it ever ends up off-screen, the menu has **Snap under menu bar**.

## Theme

Six built-in palettes: `titanium` (default), `sage`, `ice`, `copper`, `deep`,
`soft`. Set `MW_THEME` and restart. Section colours (reviews teal, issues blue,
notes amber, CI grey) carry meaning, so they stay put across themes.

## License

MIT — see [LICENSE](LICENSE).
