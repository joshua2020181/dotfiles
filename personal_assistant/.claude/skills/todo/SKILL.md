---
name: todo
description: Read, add, complete, or reprioritize items in TODO.md — the local source of truth mixing Jira tickets, GitHub PRs, and ad-hoc tasks. Use when the user asks what they're working on, says an item is done, adds a task, or asks to reorder priorities. Also the file-format authority that /briefing and /standup follow when writing TODO.md.
---

# TODO.md

`TODO.md` at the repo root is the one local list. It mixes tracked work (Jira keys, PR
numbers) with ad-hoc work that exists nowhere else. Ad-hoc items are the whole point — they
are the items no remote system will ever remind the user about, so they must never be lost.

## Format

```markdown
# TODO

_Last synced: 2026-08-03 09:14 ET_

## Blocked
- [ ] `PROJ-274` short summary — In Review
      · [jira](<jira_site>/browse/PROJ-274)
      > blocked: needs test bench time

## Awaiting review
- [ ] `repo#398` my PR, review requested from @teammate 6 days ago
      · [pr](https://github.com/<org>/repo/pull/398)

## Now
- [ ] `PROJ-241` short summary — In Progress
      · [jira](<jira_site>/browse/PROJ-241)
      · [repo#412](https://github.com/<org>/repo/pull/412) checks failing
      > waiting on teammate's answer re: default value
- [ ] `AH-004` write up a process doc for the team wiki — due:2026-08-05

## Next
- [ ] `PROJ-321` short summary — Selected for Development
      · [jira](<jira_site>/browse/PROJ-321)

## Backlog
- [ ] `PROJ-381` short summary — To Do
      · [jira](<jira_site>/browse/PROJ-381)
      > stale: no update since 2025-06-03

## Done
- [x] `PROJ-200` short summary — 2026-07-30
```

### Line grammar

```
- [ ] `<id>` <summary> — <remote status>
      · <link> · <link>
      > <note>
```

- **`<id>`** — a Jira key (`PROJ-241`), a repo-qualified PR (`repo#412`), or an ad-hoc id
  (`AH-004`). Always present, always backticked. It is the sync handle; without it a sync
  cannot tell an item apart from a new one.
- **`<remote status>`** — verbatim from Jira or GitHub. Omit for ad-hoc items.
- **`·` links** — indented continuation. Jira and PR URLs, plus a short CI note if red.
- **`>` note** — the user's own context, blockers, questions. Sacred. Never rewrite or delete a
  note; carry it forward untouched across every sync.

### Sections

In file order, which is also render order:

| Section | Holds |
|---|---|
| `Blocked` | Cannot move without someone else's decision or resource. Say what the blocker is. |
| `Awaiting review` | Ball in someone else's court. The user's open PRs with **no unresolved comments and no change requests**, plus non-PR waits on a person. |
| `Now` | Active today. |
| `Next` | The next 1–2 weeks. Not "someday". |
| `Backlog` | Future or undecided — stale tickets, drafts nobody is progressing, anything with no date attached. |
| `Done` | History. |

Ordering inside a section is meaningful — it is the user's priority call. Preserve it unless
they ask for a reorder.

**The `Awaiting review` ⇄ `Now` rule.** A PR the user opened belongs in `Awaiting review` while
it is genuinely waiting on other people. The moment it picks up an unresolved review comment, a
requested change, a merge conflict, or a failing check, it's the user's turn again — **move it
to `Now`** and say why in the note. A PR with no reviewers requested at all is also `Now`, not
`Awaiting review`: nothing is waiting on anyone.

**Note budget: 300 characters per item.** Notes are for the current state and the decision
needed, not a changelog. Rewrite the note in place rather than appending another dated line —
the history lives in `log/YYYY-MM.md` and in git. The dashboard hides anything past 300
characters behind a `more` toggle, so overflow is invisible by default.

### Ad-hoc ids

`AH-NNN`, monotonic, never reused. Next id = highest `AH-` in the file (including `Done`)
plus one. Scan the whole file before assigning, so a completed `AH-012` doesn't get reissued.

### Project tags

A Jira key carries its project already (`PROJ-241` → its project name). Ad-hoc items don't, so
an ad-hoc item belonging to a named project gets a `#slug` at the end of its summary line:

```
- [ ] `AH-008` update the ICD doc for a partner integration `#project-slug`
```

Known non-Jira projects are listed in `local.md` — read it for the current set rather than
inventing a slug. When the user names a project that isn't there yet, add it to `local.md`
with its slug in the same pass, so the next session uses the same tag.

An untagged ad-hoc item is fine — it means standalone work, not a mistake. Don't retro-tag
items by guessing which project they belong to.

## Operations

**Show** — read the file and report it. Don't hit the network. If `_Last synced:_` is over a
day old, say so and offer `/briefing`.

**Add** — needs summary and section (default `Next`). If it maps to an existing Jira issue or
PR, use that key; otherwise mint an `AH-` id. Ask for a due date only if implied.

**Complete** — move the line to `Done`, `[x]`, append the completion date. Keep the id and
summary; links may be trimmed to one. If it has a Jira key still open remotely, say so and
ask whether to transition the ticket — do not transition unprompted.

**Reprioritize** — move lines between sections or reorder within one. Never edit the text
while moving.

**Prune** — keep `Done` to the current month. Older entries move to `log/YYYY-MM.md` under a
`## Completed` heading. Never delete outright.

## Invariants

Check these after every write:

- Every open item has an id, and ids are unique across the file.
- No `>` note was altered or dropped.
- No item vanished. If a Jira issue disappeared from a query, keep the line and mark it
  `— status unknown (not in last query)`; a query narrowing is not proof the work went away.
- The file is valid markdown with a live checkbox for every open item.

If `TODO.md` does not exist, create it with the five headings and an empty body.
