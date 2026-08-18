---
name: standup
description: Generate the user's standup update — what they finished, what they're on today, what's blocking them — as a short paste-ready block sourced from Jira, GitHub, and TODO.md. Use when the user asks for a standup, a status update to share, "what did I do yesterday", or an end-of-week summary.
---

# Standup

Short, factual, paste-ready. Written for teammates, so no `AH-` ids, no internal bookkeeping,
no links to `TODO.md`.

## Gather

Default window is the last working day; for `weekly` use the last 7 days. Concurrently:

**Jira** (see `references/sources.md`):
```jql
assignee = currentUser() AND statusCategory = Done AND resolutiondate >= -1d ORDER BY resolutiondate DESC
assignee = currentUser() AND status = "In Progress" ORDER BY updated DESC
assignee = currentUser() AND updated >= -1d ORDER BY updated DESC
```

**GitHub**: PRs merged in the window, PRs opened in the window, PRs of theirs awaiting review.

**TODO.md**: the `Now` section is what the user actually intends to do today — it beats any
inference from ticket status. `>` notes in `Blocked` are the real blockers, in their words.

**Local**: `git log --author` in nearby repos for work that hasn't become a PR yet.

## Output

```
**Yesterday**
- PROJ-200 short summary — done, merged repo#390
- Debugged a flaky integration test; root cause was a clock/timezone issue, not the test

**Today**
- PROJ-241 short summary — finishing the last edge case
- Reviewing repo#421 for @teammate

**Blockers**
- PROJ-274 needs test bench time — anyone have a slot Thursday?
```

Rules for the text:

- Ticket keys bare (`PROJ-241`), no URLs — teammates resolve keys themselves, and links make a
  Slack paste noisy. Add links only if asked.
- 2–4 bullets per section. Merge trivia into one line rather than listing six small things.
- Say what changed, not what the ticket is titled. "Finished the edge case, ran into a units
  mismatch" beats "worked on PROJ-241".
- `Blockers` is the section people act on. Empty is a fine answer — write `- None` rather
  than padding it. If a blocker needs a person, name them and state the ask.
- Nothing speculative. If a source was unreachable, tell the user in your own message (outside
  the paste block) so they can fill the gap themselves.

## After

Offer to post it if the user names a channel — **and only then**. Never post unprompted.

Ask whether anything in the update should land in `TODO.md`: a blocker voiced out loud here
often isn't recorded anywhere yet.
