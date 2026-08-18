---
name: pr-status
description: GitHub-only check on the user's pull requests — their open PRs and CI, reviews requested from them, PRs stalled waiting on reviewers, and recent merges. Use when the user asks about PRs, reviews, CI, checks, or what's blocking a merge. For a full cross-source sweep use /briefing instead.
---

# PR status

Uses the `gh` CLI (already authenticated). Login, org, and repos are in `local.md`; recipes in
`references/sources.md`.

## Sweep

Concurrently:

```bash
gh search prs --author <login> --state open --json repository,number,title,url,isDraft,createdAt,updatedAt
gh search prs --review-requested <login> --state open --json repository,number,title,url,author,updatedAt
gh search prs --author <login> --merged --merged-at '>=<today-7d>' --json repository,number,title,url,closedAt
```

Then `gh pr view --json ...,mergeable,reviewDecision,statusCheckRollup` on the user's open
non-draft PRs to get CI and review state. Batch these in one message. Skip drafts unless asked
— a red draft is not news.

## Report

Ordered by who is blocked:

```
**Blocking others — review requested from you (2)**
- repo#421 @teammate · "short summary" · 2d waiting — <url>

**Your PRs needing action (1)**
- repo#412 CI red: 2 failing (build, tests) — <url>
- other-repo#88 merge conflict with main — <url>

**Your PRs waiting on review (2)**
- repo#398 approved 0/1, requested @teammate 6d ago — <url>
- repo#405 no reviewer assigned — <url>

**Merged last 7 days (3)**
- repo#390 short summary — 2026-07-27 — <url>
```

Per PR, when relevant: `reviewDecision` (`APPROVED`/`CHANGES_REQUESTED`/`REVIEW_REQUIRED`),
`mergeable` (call out `CONFLICTING`), failing check names — names, not just a count —
and days since the last update.

## Jira linkage

Extract the project-key regex for your Jira projects (see `local.md`) from the branch, title,
and body, and show the key beside the PR. Flag the mismatches:

- PR merged, Jira ticket still open → ticket needs transitioning
- PR open with no ticket key → ad-hoc work; offer a `TODO.md` `AH-` entry
- Ticket `In Review` with no open PR → the review is happening somewhere else, or the PR merged

## Depth on one PR

```bash
gh pr view <n> --repo <org>/<repo> --json number,title,url,state,isDraft,mergeable,reviewDecision,statusCheckRollup,reviews,comments,files
gh pr checks <n> --repo <org>/<repo>
```

For a failing check, name the job and, if the log is reachable
(`gh run view --log-failed`), quote the actual error line rather than paraphrasing it.

## Rules

- Read-only. Never merge, close, push, approve, or comment without the user asking in this
  turn.
- Reviewing the *content* of a diff is `/review` or `/code-review`, not this skill. This one
  reports state.
- If `gh` errors (auth, rate limit, network), quote the error and say which parts of the
  report are missing because of it.
