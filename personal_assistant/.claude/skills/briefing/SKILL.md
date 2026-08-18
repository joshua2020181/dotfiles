---
name: briefing
description: Full status sweep across Jira, GitHub, and local checkouts, then reconcile everything into TODO.md and append the report to log/. Use when the user asks "what's my status", "catch me up", "what happened", "morning briefing", or starts the day and wants to know where things stand. Does not scan Slack — the user follows that themselves.
---

# Briefing

One pass over every source, one reconciled picture, one write to `TODO.md`.

Read `local.md` for identity and source constants, then `references/sources.md` for the
queries. Read the current `TODO.md` before touching any source — you need the existing notes
and ordering to reconcile against, and reading it first means a source failure still leaves you
able to report something.

## 1. Gather

Fire these concurrently; they're independent.

**Jira** — assigned-and-open, assigned-in-last-7d, stale-14d, and reported-by-you-not-yours.
Narrow `fields`, `maxResults: 50`.

**GitHub** — open PRs, review-requested-from-you, merged in the last 7 days. Then per-PR
detail only for PRs that appear in `TODO.md` or that are red — don't `pr view` all of them.

**Local** — `git status --short --branch` in each checkout you track (see `local.md` for the
repo list). Report unpushed commits, and branches with **no upstream configured** — that work
exists on one disk only.

**Not Slack.** The user reads their own Slack and does not want a digest of it. Don't search
it, don't count unreads, don't add a Slack section to the report. When they want a message
tracked they'll point at it — that's `/slack-task`.

Log the sources that failed. They go in the report verbatim.

## 2. Reconcile

Match sources by ticket key, per the regex convention in `references/sources.md`. Then,
against `TODO.md`:

| Situation | Do |
|---|---|
| Item in `TODO.md`, remote status changed | Update the status field. Keep section, order, note. |
| Item in `TODO.md`, no remote match this run | Keep it. Mark `— status unknown (not in last query)`. Never delete. |
| Remote item not in `TODO.md`, open, assigned to the user | Add to `Next`. Flag it as new in the report. |
| Remote item with no date pressure — stale, draft, or backlog status | Add to `Backlog`, not `Next`. |
| PR merged / issue Done | Move to `Done` with today's date. |
| Your PR, reviewers requested, **no** unresolved comments or change requests | `Awaiting review`. |
| Your PR with an unresolved comment, change request, conflict, or red check | `Now` — it's your turn again. Say which. |
| Your PR with **no** reviewers requested at all | `Now` — nothing is waiting on anyone. |
| Review requested from the user | Add to `Now` — this blocks a teammate. |
| Local branch with no upstream | Add to `Now` with an `AH-` id — unbacked-up work. |
| Waiting on a person, not a PR | `Awaiting review` — same section, name who. |

Sections, in file order: `Blocked`, `Awaiting review`, `Now`, `Next`, `Backlog`, `Done`.
`Next` means the next 1–2 weeks; anything vaguer belongs in `Backlog`.

**Notes are capped at 300 characters per item.** Rewrite the note to reflect current state
rather than appending another dated line — a note is not a changelog, and the history already
lives in `log/YYYY-MM.md` and in git. The dashboard hides overflow behind a `more` toggle, so
anything past 300 characters is invisible by default.

Follow `.claude/skills/todo/SKILL.md` for the file format and its invariants. Check the
invariants after writing.

### Also write `state.json`

`serve.py` renders the local dashboard from `TODO.md` **plus** `state.json`, so a briefing that
skips `state.json` leaves the dashboard showing stale CI and review data. Write both, every run.

`state.json` holds only what `TODO.md` cannot: `generated` (timestamp with zone), `headline`
(one line — the single most important finding), `sources` (`[{name, ok}]`), `counts`, `moved`
(what changed since the last briefing), `attention` (`[{severity: crit|warn|info, title, pills,
links, detail}]`), `repos`, `review_queue` (`{total, oldest:[{pr, url, author, what, days}]}`),
and `shipped` (`[{id, url, what, fresh}]`). Markdown inline formatting works in `detail`,
`headline`, and `moved`; link syntax is rendered, and everything is HTML-escaped first.

Do not restate task text there — the task list comes from `TODO.md`, and duplicating it is how
the two drift apart. `attention` entries reference ids, they don't replace items.

## 3. Report

Terse, scannable, most-actionable first. Every line carries a link.

```
## Briefing — 2026-08-03 15:05 CEST     <- always the zone `date '+%Z'` reported

**Needs you today**
- Review requested: repo#421 by @teammate, 2d old — <url>
- PROJ-241 In Progress, CI red on repo#412 (2 failing checks) — <url>
- other-repo `feat/foo` has no upstream — 1 commit exists only on this disk

**Moved since last briefing (2026-08-01)**
- PROJ-376 Triage → Selected for Development — <url>
- repo#398 merged 2026-08-02 — <url>

**Awaiting review**
- repo#398 → review requested from @teammate 6d ago — <url>

**Stale (14d+, yours, open)**
- PROJ-1115 Backlog, untouched since 2026-06-29 — <url>

**Sources:** Jira ok · GitHub ok · local repos ok
**TODO.md:** 2 added, 3 statuses updated, 1 moved to Done
```

Drop empty sections, except `Sources` — that one always prints.

## 4. Log

Write the report into `log/YYYY-MM.md`, creating the file with a `# YYYY-MM` heading if needed.

**Newest first.** Insert the new entry directly below the `# YYYY-MM` heading, above the
previous entry — do not append to the bottom of the file. The entry immediately below yours is
the baseline "since last briefing" is measured against, so reading the file top-down has to
read newest-to-oldest.

Heading format, exactly: `## YYYY-MM-DD HH:MM TZ — briefing`, e.g.
`## 2026-08-04 20:23 CEST — briefing`. No parentheses, no extra qualifiers; if the run was
headless from the dashboard's Resync button, say so in the body instead.

## Rules

- Read-only against every remote. Proposing a Jira transition or a comment is in scope;
  performing one without the user asking in this turn is not.
- Never state a status you didn't read this run. Stale is a label, not something to hide.
- If the user names a scope ("just jira", "only PRs"), honor it and say which sources you
  skipped.
- Don't reach into Slack here, even when a Jira ticket or PR obviously has a Slack thread
  behind it. If context is missing, say what's missing and let the user decide.
