# Adding a source

Tally does not care where items come from. `fetch.py` writes one file,
`data.json`, and the widget draws whatever is in it. So a new source is just a
script that prints JSON.

Built in already: **GitLab** merge requests, **GitHub** pull requests,
**Plane** issues, **Jira** issues, and CI pipelines/runs for both forges. If
your team uses something else — Linear, Notion, Asana, Redmine, a spreadsheet,
a CSV your PM emails you — write ten lines and list it in `MW_EXTRA_SOURCES`.

## The contract

Your script prints **one section** (or an array of sections) on stdout and exits
0. Nothing else is required; anything you print on stderr shows up in
`tally.log`.

```json
{
  "key": "linear",
  "title": "Linear",
  "hue": "blue",
  "items": [
    { "id": "ENG-42", "title": "Fix retry policy", "url": "https://…" }
  ]
}
```

To group rows under sub-headings, use `groups` instead of `items`:

```json
{
  "key": "linear",
  "title": "Linear",
  "hue": "blue",
  "groups": [
    {
      "title": "In Progress",
      "color": "blue",
      "items": [ { "id": "ENG-42", "title": "Fix retry policy", "url": "https://…" } ]
    },
    {
      "title": "Backlog",
      "color": "dim",
      "items": [ { "id": "ENG-51", "title": "Split the fetch layer", "url": "" } ]
    }
  ]
}
```

### Section fields

| field | required | meaning |
|---|---|---|
| `key` | yes | Stable id. Used for fold state and `MW_SECTION_ORDER`. |
| `title` | yes | Heading shown in the widget and the menu bar count. |
| `hue` | no | Band colour: `teal` `blue` `amber` `grey`. Default `grey`. |
| `items` | one of | Flat list of rows. |
| `groups` | one of | Sub-headings, each with `title`, optional `color`, and `items`. |

### Row fields

| field | meaning |
|---|---|
| `id` | Short handle on the left — `!42`, `#17`, `ENG-42`, `DEV` |
| `title` | The text. Truncated to fit; the full string shows on hover. |
| `url` | Opened in the browser when clicked. Omit for non-clickable rows. |
| `repo` | Optional short label between id and title. |
| `badge` | Number shown as a pill on the right — unread comments, say. |
| `ok` | `true` draws a ✓ when there is no badge or CI status. |
| `ci` | `success` `failed` `running` `pending` `canceled` — drives the ✓/✗/◍ mark, the menu-bar CI summary, and banners. |
| `ciUrl` | Where the CI mark links to, if different from `url`. |
| `at` | ISO timestamp appended to the title as `2h ago`. |
| `mine` | `true` if you triggered it. Only `mine` rows raise banners. |

### Group colours

`blue` `green` `amber` `purple` `plain` `dim` — names, not hex, so a theme
change does not break your script. Pick by meaning: `blue` for in-flight,
`plain` for waiting, `dim` for far-off, `purple` for review/QA, `green` for
ready to ship.

## Wiring it up

```bash
chmod +x sources/mysource.py
```

```bash
# config.sh
export MW_EXTRA_SOURCES="
sources/mysource.py
"
export MW_SECTION_ORDER="code,issues,mysource,notes,ci"
```

Then check it without opening the widget:

```bash
./fetch.sh && ./tally --dump
```

If a script fails, Tally keeps the rest and shows a red line in the widget with
the script name — one broken source never blanks the others.

## Notes

- Scripts run with the environment from `config.sh`, so put your tokens there
  (`config.sh` is git-ignored) and read them with `os.environ`.
- They run on every refresh — every four hours by default, plus manual
  refreshes. Keep them under a few seconds, and cache if the API is slow.
- Nothing is written back to your tracker. Tally is read-only by design; keep
  your source scripts read-only too, so a stray refresh can never change data.

## Examples

| file | what it shows |
|---|---|
| `sources/static.example.sh` | The smallest possible source — a hard-coded list |
| `sources/command.example.sh` | **Any command's output**, configured from `config.sh` — no code |
| `sources/linear.example.py` | Linear issues by state, via GraphQL |
| `sources/notion.example.py` | Notion database rows grouped by a status property |

`command.example.sh` is the one to reach for first. Anything with a CLI becomes
a section without writing code:

```bash
export CMD_KEY="pods"
export CMD_TITLE="Unhealthy pods"
export CMD_HUE="amber"
export CMD_LINE='kubectl get pods --field-selector=status.phase!=Running \
                   -o custom-columns=":metadata.name,:status.phase" --no-headers'
export MW_EXTRA_SOURCES="sources/command.example.sh"
```

Print `id <TAB> title <TAB> url` and you get ids and clickable links too.

Built-in sources live in `fetch.py` (`gitlab_items`, `github_items`,
`plane_groups`, `jira_groups`) and follow the same shape — read those if you
want a fuller example.
