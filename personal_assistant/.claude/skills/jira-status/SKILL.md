---
name: jira-status
description: Jira-only status check for the user's board — what's assigned, what's in review, what landed on them recently, what's gone stale. Use when the user asks about Jira, tickets, their board, sprint work, or a specific issue key. For a full cross-source sweep use /briefing instead.
---

# Jira status

Read `local.md` for the cloud id and project keys, then `references/sources.md` for the JQL
and the field-list constraint before querying.

## Whole-board check

Run these concurrently:

1. `assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC`
2. `status = "In Review" AND assignee = currentUser() ORDER BY updated DESC`
3. `assignee = currentUser() AND updated >= -7d ORDER BY updated DESC`
4. `assignee = currentUser() AND statusCategory != Done AND updated <= -14d ORDER BY updated ASC`
5. `reporter = currentUser() AND assignee != currentUser() AND statusCategory != Done ORDER BY updated DESC`

Group the output by what the user has to do about it, not by project:

```
**In Progress (2)**
- PROJ-241 short summary — updated 2026-07-15 — <url>

**In Review — yours (2)**
- PROJ-274 short summary — <url>

**New on your plate this week (1)**
- PROJ-376 short summary — Selected for Development — <url>

**Queued (Selected for Development, 6)**
- ... one line each

**Stale 14d+ (3)**
- PROJ-1115 short summary — Backlog, 2026-06-29 — <url>

**You reported, someone else owns (2)**
- PROJ-197 short summary — @owner — <url>
```

Collapse any group over 8 items to the top 5 plus a count, and say you truncated.

## Single issue

Given a key, `getJiraIssue` with `fields: ["summary","status","assignee","priority","description","comment","duedate","parent","labels"]`. Report: status, assignee,
last update, the last 2–3 comments, linked PRs if `getJiraIssueRemoteIssueLinks` returns any,
and — if the user is likely to want to move it — the legal transitions from
`getTransitionsForJiraIssue`. Listing transitions is not performing one.

## Cross-checks worth flagging

- Ticket `In Progress` with no matching open PR → likely uncommitted or unpushed work
- Ticket `In Review` whose PR already merged → the ticket needs transitioning, tell the user
- Ticket `Done` still sitting in `TODO.md` under an open section → offer to close it out
- Two tickets `In Progress` at once is normal for most people; a lot more than that is worth a note

## Rules

- Writes (transition, comment, edit, assign) need the user asking in this turn. Otherwise say
  "want me to move PROJ-241 to In Review?" and wait.
- Status names vary per instance — don't assume the Jira defaults. Quote whatever you observe
  verbatim; filter on `statusCategory`, not the status name.
- If a result spills to a file, `jq` it — don't Read it, and don't silently report a subset.
- Every issue mentioned gets its `<jira_site>/browse/<KEY>` link (site from `local.md`).
