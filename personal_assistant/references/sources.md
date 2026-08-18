# Source query recipes

Copy-paste queries for Jira, GitHub, and Slack. Sites, ids, org, and repos are in `local.md` —
this file has the query shapes, not the values. Read `local.md` first and substitute.

Issue URL pattern: `<jira_site>/browse/<KEY>`.

---

## Jira (Atlassian Rovo MCP)

Tool: `mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql`, with `cloudId` from
`local.md`.

**Assume the assigned-issues query spills to a file, and plan to `jq` it.** Verified: a narrow
`fields` list does **not** prevent this — the MCP returns `description`, `issuetype`, and
`project` regardless of what you ask for, and a few dozen issues is already past the
tool-result token cap. Passing `responseContentFormat: "markdown"` doesn't help either.

Still pass a narrow list plus `maxResults: 50` — it shrinks the payload — but expect the spill
and parse it with `jq` rather than Read:

```bash
jq -r '.issues.nodes[] | "\(.key)\t\(.fields.status.name)\t\(.fields.summary)"' <file>
```

### Queries

Open and assigned to you — the backbone of every briefing:
```jql
assignee = currentUser() AND statusCategory != Done ORDER BY updated DESC
```

Awaiting your review:
```jql
status = "In Review" AND assignee = currentUser() ORDER BY updated DESC
```

Assigned to you in the last 7 days (surprise work landing on you):
```jql
assignee = currentUser() AND updated >= -7d ORDER BY updated DESC
```

Stale — yours, open, untouched 14+ days:
```jql
assignee = currentUser() AND statusCategory != Done AND updated <= -14d ORDER BY updated ASC
```

Closed this week, for standup:
```jql
assignee = currentUser() AND statusCategory = Done AND resolutiondate >= -7d ORDER BY resolutiondate DESC
```

Reported by you, still open (things you're waiting on from others):
```jql
reporter = currentUser() AND assignee != currentUser() AND statusCategory != Done ORDER BY updated DESC
```

Triage queue you may own — swap in your triage project key from `local.md`:
```jql
project = <TRIAGE_KEY> AND status = Triage ORDER BY created DESC
```

Mentioned but not assigned:
```jql
text ~ "currentUser()" AND assignee != currentUser() AND statusCategory != Done ORDER BY updated DESC
```

### Status vocabulary

Most Jira instances customize status names beyond the defaults (extra open states, several
flavors of "won't do"). Don't hardcode the names you observe — **filter on `statusCategory`**
(`To Do` / `In Progress` / `Done`), which is stable across projects and instances; the name
list varies per project and next-gen boards add their own.

### Other useful tools

- `getJiraIssue` — one issue in full, including comments (`fields: ["comment"]`)
- `getTransitionsForJiraIssue` — legal next states before proposing a transition
- `transitionJiraIssue`, `editJiraIssue`, `addCommentToJiraIssue` — **writes, need your ok**
- `getJiraIssueRemoteIssueLinks` — linked PRs, if the GitHub-Jira integration is on

---

## GitHub (`gh` CLI)

Your open PRs across everything (`<login>` and `<org>` from `local.md`):
```bash
gh search prs --author <login> --state open \
  --json repository,number,title,url,isDraft,createdAt,updatedAt
```

Review requested from you:
```bash
gh search prs --review-requested <login> --state open \
  --json repository,number,title,url,author,updatedAt
```

Recently merged, for standup:
```bash
gh search prs --author <login> --merged --merged-at '>=2026-07-27' \
  --json repository,number,title,url,closedAt
```
Compute the date from today minus 7 days; `gh` has no relative-date syntax here.

Per-PR detail — CI, review state, mergeability, conflicts:
```bash
gh pr view <number> --repo <org>/<repo> \
  --json number,title,url,state,isDraft,mergeable,reviewDecision,statusCheckRollup,comments
```

Failing checks on a PR:
```bash
gh pr checks <number> --repo <org>/<repo>
```

Issues assigned to you:
```bash
gh search issues --assignee <login> --state open --json repository,number,title,url
```

Unpushed local work, when cwd is a repo:
```bash
git status --short --branch && git log --oneline @{u}..HEAD 2>/dev/null
```

### Linking PRs to Jira issues

There is no API join, but a PR title convention makes the match reliable, if your org uses one:

```
<type>(<KEY>): <summary>      e.g.  feat(PROJ-376): short summary
<type>(N/A): <summary>        e.g.  fix(N/A): short summary
```

`N/A` in the scope slot means deliberately no ticket — treat it as ad-hoc work and give it an
`AH-` id in `TODO.md`, don't go hunting for a ticket. Otherwise extract the project-key regex
for your Jira projects (see `local.md`) from the title, then the branch name, then the body.
Some repos follow no convention at all — that's normal, not a bug.

**Watch for placeholder ticket keys.** Some teams reuse a fixed dummy key as filler in PR
titles for a stretch (e.g. during a migration). If you notice one, treat it exactly like
`N/A` — a PR scoped to it is ad-hoc work, not work on that ticket. Never link such a PR to the
real issue at that key, never report the two as related, and never flag a status mismatch
between them. Keep a running list of any placeholder keys you find in `local.md`.

Watch for the reverse mismatch too: a PR open against a ticket still in an early open status
means the ticket needs transitioning. Flag it; don't fix it.

### Review-request volume

If you sit in a broad reviewer group, the review-requested-from-you query can return a long
tail of old PRs. Don't dump the whole list in a briefing. Report the count, then the 3 oldest
and anything touching code you own. `/pr-status` is where the full queue belongs.

---

## Slack (MCP connector)

Workspace, your user id, and your self-DM channel id are in `local.md`.

If a run finds only `authenticate` / `complete_authentication`, the connector dropped: run
**`/mcp`** → **"claude.ai Slack"**. It authenticates through the UI, not a URL.

Tools (load schemas with `ToolSearch("select:<name>")`):

| Tool | Use |
|---|---|
| `slack_search_public_and_private` | the workhorse — message search with filters |
| `slack_search_public` | public channels only |
| `slack_search_channels` | resolve a channel name → id |
| `slack_search_users` | resolve a person → user id |
| `slack_read_channel` | recent messages in one channel |
| `slack_read_thread` | full thread from a parent `ts` |
| `slack_read_user_profile` | detail on a known user id |
| `slack_send_message` | **write** — needs you asking in this turn |
| `slack_send_message_draft` | preferred write path when you haven't seen the text yet |
| `slack_schedule_message` | **write** — send later |
| `slack_{create,read,update}_canvas` | canvases |

### Pull-only — never scan

You follow Slack yourself. **Do not** produce unread digests, mention sweeps, or a Slack
section in a briefing. Read Slack for exactly two reasons: to resolve a message you pointed at
(`/slack-task`), or to answer a question asked outright.

There is also no conversations.list or unread-count tool, so read/unread isn't observable even
if you wanted it — one more reason the scan was never going to be honest.

### Resolving a permalink

`https://<workspace>.slack.com/archives/<CHANNEL>/p<DIGITS>` — the channel id is the path
segment (`C…` public, `D…` DM, `G…` group). The `p` number is the message `ts` with the decimal
removed; put it back ten digits from the left:

```
p1785758325747709  →  ts 1785758325.747709
```

Then `slack_read_thread` with that `ts` for the thread, or `slack_read_channel` on the channel
id for surrounding messages.

### Finding a message from a quote

`slack_search_public_and_private`. Filters: `from:<@U…>` / `from:username`, `to:me`,
`in:#channel`, `is:dm`, `is:thread`, `after:YYYY-MM-DD`, `before:`, `on:`, `"exact phrase"`,
`-exclude`. Semantic search is enabled for this account, so a natural-language question works
too. If several messages match, list the candidates with timestamps and ask which — don't
guess.

Capture for the task: who, channel, timestamp in the detected local zone (`date '+%Z'`, never
assume home base), the substance, and the permalink.
