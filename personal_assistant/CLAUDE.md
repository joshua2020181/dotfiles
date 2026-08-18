# Personal Assistant

This directory is a personal work-tracking hub. Its job: pull status from Slack, Jira, and
GitHub, and keep `TODO.md` as the single local source of truth for what you're doing.

There is no application code here. Do not look for a build, tests, or a package manifest.
The deliverables are `TODO.md`, the skills in `.claude/skills/`, and the logs in `log/`.

**Identity and source constants (name, email, Jira/GitHub/Slack ids, project keys, repos) live
in `local.md`** — gitignored, never committed. Read it before running any source query. If it
doesn't exist yet, copy `local.md.example` and fill it in.

## Sources

**Jira** — via the Atlassian Rovo MCP. Site and cloud id are in `local.md`, along with your
active projects by volume.

**Projects with no Jira presence** — tracked only in `TODO.md`, via the `#slug` tag convention
in `.claude/skills/todo/SKILL.md`. Don't go looking for tickets or repos for these; if a Jira
project appears for one later, move it into `local.md`'s project table and keep the tag as an
alias. Current slugs are in `local.md` too.

**GitHub** — via the `gh` CLI (authenticated, ssh). Org, login, and the repos you work in are
in `local.md`.

**Slack** — via the claude.ai Slack MCP connector. Workspace, your user id, and your self-DM
channel id are in `local.md`. **Pull-only.** You stay on top of Slack yourself and don't want
it scanned: no unread digests, no mention sweeps, no Slack section in a briefing. Read it only
to resolve a message you've pointed at (`/slack-task`) or to answer a question asked outright.
If a session finds only `authenticate` / `complete_authentication`, the connector dropped — run
`/mcp` and select "claude.ai Slack" (it authenticates through the UI, not a URL).

Detailed query recipes (JQL, `gh` invocations, Slack patterns) live in
`references/sources.md`. Read that file before running source queries; don't re-derive them.

## Reaching you

Use `PushNotification` — terminal notification, plus phone if Remote Control is connected
(silently no-ops on mobile until you turn that on). Reserve it for things worth interrupting
over: a long sweep finished, a decision blocks progress.

**Do not use a Slack self-DM as a notification.** Messages sent through the connector post *as
you* into your self-DM channel, and Slack never notifies you about your own messages. They land
and are silently marked read. `slack_schedule_message` has the same flaw.

Your self-DM is still useful as a scratch pad — logs and commit SHAs parked there are worth
mining for untracked work during a briefing; useless as an alerting channel.

## Rules

- **`TODO.md` is authoritative for intent, the sources are authoritative for state.** When they
  disagree, the remote status wins for the `status` field; your ordering, notes, and ad-hoc
  items always survive a sync. Never drop a line just because no remote match exists.
- **Never mutate a remote system without you saying so in that turn.** Reading Jira, GitHub,
  and Slack is always fine. Transitioning an issue, commenting, merging, or posting to Slack
  requires an explicit ask. Report what you would change instead.
- **Cite everything.** Every claim about a ticket, PR, or message gets a URL. If a fact came
  from a source that couldn't be reached, label it stale, don't infer it.
- **Say when a source failed.** A briefing missing Slack must say "Slack: unavailable (not
  authenticated)", never omit the section silently.
- **Detect the timezone, never assume it.** Run `date '+%Y-%m-%d %H:%M %Z'` at the start of any
  run that reports times, and render every timestamp in that zone with the abbreviation
  attached. Your home base is a default, not a guarantee — you travel, and remote systems
  return their own zones: Slack renders in the workspace zone, Jira `updated` carries a UTC
  offset, `gh` returns UTC `Z` timestamps. Convert all of them to the detected local zone
  before showing them side by side.
- Dates absolute (`2026-08-03`), never "yesterday", in any file you write.
- Append each briefing to `log/YYYY-MM.md` so there's a history of what was reported when.
