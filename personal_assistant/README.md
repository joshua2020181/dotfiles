# Personal assistant

Work-tracking hub. Claude gathers from Jira, GitHub, and local checkouts; `TODO.md` is the
single source of truth; `serve.py` renders it in a browser and writes it back.

```
CLAUDE.md          which sources exist, the rules
local.md           your name, ids, org, repos, project keys — gitignored, never committed
TODO.md            the list — authoritative for intent — gitignored, never committed
state.json         cross-source detail TODO.md can't hold — gitignored, never committed
serve.py           local dashboard: reads TODO.md live, writes it on tick
dashboard.html     published Artifact — a shareable snapshot, goes stale — gitignored
log/YYYY-MM.md     one entry per briefing — gitignored, never committed
references/        query recipes for each source
.claude/skills/    the slash commands below
```

## Setup

Copy `local.md.example` to `local.md` and fill in your name, email, Jira/GitHub/Slack ids,
org, repos, and project keys. Everything else in this repo reads from there instead of
hardcoding identity or org specifics, so the repo stays safe to make public. `local.md`,
`TODO.md`, `state.json`, `dashboard.html`, and `log/` are all gitignored — they're where your
actual data lives, and none of it is meant to be committed.

## Commands

| Command | Does |
|---|---|
| `/briefing` | Sweep Jira + GitHub + local checkouts, reconcile into `TODO.md`, write `state.json`, append to `log/` |
| `/standup` | Yesterday / today / blockers, paste-ready |
| `/todo` | Add, complete, reprioritize |
| `/jira-status` | Jira only |
| `/pr-status` | GitHub only |
| `/slack-task` | Turn a Slack message you point at into a task |

## The dashboard

```bash
./serve.py                 # http://127.0.0.1:8788
./serve.py --port 9000
./serve.py --no-token      # skip the write token
```

Tick items, hit **Mark done**, and `TODO.md` is rewritten immediately — notes and links carried
over verbatim, project tags preserved, the item moved to `Done` with today's date. The `↩` on a
done item reopens it (into `Next` — see limits). Every write copies the old file to
`.todo-backups/` first, keeping the last 20; the repo is git, so that's a second net.

Run it as a service:

```bash
mkdir -p ~/.config/systemd/user
cp todo-dashboard.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now todo-dashboard
systemctl --user status todo-dashboard      # the URL and token are in the log
```

### Chat about one task

Hover any row and click **chat**. A popup opens scoped to that item, with its notes in view.
Talk in plain language — no ids, no terminal:

> *punting this until thursday, i don't have bandwidth before then*

It resolves the date against today, writes an absolute one, adds a `>` deferral note keeping the
existing ones, and moves the item to whichever section now fits (`Blocked` when something else is
holding it, `Next` when it's just later). When a turn edits the file, that turn is labelled
**edited TODO.md** and the page reloads on close. Ask a question instead and nothing changes.

**The conversation is disposable.** Each popup gets a fresh session id; closing it (`esc`, the
button, or clicking outside) deletes the transcript from `~/.claude/projects/` and clears the log.
Edits to `TODO.md` are permanent — the chat about them isn't. Nothing is written to `log/`.

Backed by `claude -p` in the project directory, with tools limited to `Read` and `Edit`, and a
scoped system prompt that forbids touching any other item or the `_Last synced:_` line. Turn one
uses `--session-id`, later turns `--resume`, so context lives in Claude Code rather than in this
server. Expect **~10–20s per reply** and roughly **$0.15 a turn** — it's a real model call, not a
local heuristic. One turn runs at a time, so two popups can't edit the file at once.

### Why it renders from the file

The published Artifact embeds a *copy* of `TODO.md`, so it goes stale the moment anything edits
the file, and every change needs a republish. The server reads the file per request, so the
dashboard cannot disagree with it. Keep the Artifact for what it's actually good at — a link you
can open on a phone or hand to someone else.

### Security

Binds `127.0.0.1` only. Mutating routes need both a loopback `Origin` and the `X-Token` header —
any page in your browser can POST to localhost, but it can't read the token, which the server
mints per start and embeds only in the page it serves. `--no-token` drops that check; don't use
it if you run untrusted pages in the same browser. Don't bind `0.0.0.0` — that puts program
names like `usn-musv` on the network.

### Limits

- **Reopen lands in `Next`**, not the section the item came from. The file doesn't record where
  it was, and guessing wrong is worse than one predictable destination.
- **No conflict detection.** If Claude rewrites `TODO.md` while the page is open, the page shows
  the old state until you reload; ticking then writes against fresh content — but the item you
  ticked may already have moved, which returns a 409 rather than corrupting anything.
- **Markdown support is deliberately partial** — `` `code` ``, `**bold**`, and `[text](url)` in
  summaries and notes. Everything is HTML-escaped first, so unknown syntax renders as literal
  text rather than breaking the page.
- **`state.json` is optional.** Delete it and the dashboard degrades to just the task list.
