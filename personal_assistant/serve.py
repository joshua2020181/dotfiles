#!/usr/bin/env python3
"""Local dashboard for TODO.md — renders it live and writes it back.

    ./serve.py            # http://127.0.0.1:8787
    ./serve.py --port 9000 --no-token

Reads TODO.md on every request, so it can never disagree with the file.
Cross-source detail the file does not carry (CI state, review ages, repo
status) comes from state.json, which /briefing writes.

Stdlib only. Binds loopback only. Mutating routes require a token and a
loopback Origin, so a stray page in your browser cannot rewrite your TODO.
"""

import argparse
import html
import json
import os
import re
import secrets
import shutil
import subprocess
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
KEEP_BACKUPS = 20


def backup_dir(path):
    """Backups live beside the file they protect, not beside this script."""
    return path.parent / ".todo-backups"


def find_claude():
    """Absolute path to the CLI.

    A systemd user unit does not inherit a login shell's PATH, and the CLI
    installs to ~/.local/bin — so resolving this at startup is the difference
    between chat working and every turn failing with "not on PATH".
    """
    found = shutil.which("claude")
    if found:
        return found
    for cand in (Path.home() / ".local/bin/claude", Path("/usr/local/bin/claude")):
        if cand.exists():
            return str(cand)
    return ""


CLAUDE_BIN = find_claude()


# Anything that may write TODO.md takes this first. A chat turn holds it for
# seconds; a resync holds it for minutes, so callers use a timeout and report
# "busy" rather than hanging a request.
WRITER = threading.Lock()
CHAT_TIMEOUT = 180
RESYNC_TIMEOUT = 900

RESYNC_TOOLS = [
    "Read", "Edit", "Write", "Bash", "Glob", "Grep",
    "mcp__claude_ai_Atlassian_Rovo__searchJiraIssuesUsingJql",
    "mcp__claude_ai_Atlassian_Rovo__getJiraIssue",
    "mcp__claude_ai_Atlassian_Rovo__getAccessibleAtlassianResources",
]

RESYNC_PROMPT = """Read .claude/skills/briefing/SKILL.md and carry out that briefing now, \
end to end, following it exactly: gather from Jira, GitHub and the local checkouts, reconcile \
into TODO.md, write state.json, and append the report to log/.

You are running headless from the dashboard's Resync button, so there is nobody to answer \
questions — make the judgement calls the skill describes and note them in the log entry.

When you are completely finished, end your reply with a single line of the form:
RESYNC: <one sentence on what changed>"""

RESYNC = {
    "running": False, "ok": None, "error": "", "summary": "",
    "started": None, "finished": None,
}
RESYNC_STATE = threading.Lock()

CHAT_SYSTEM = """You are answering from a task-chat popup on Josh's local TODO dashboard, \
scoped to ONE task. Keep replies to a few sentences — this is a small popup, not a terminal.

You may edit TODO.md to act on what he says, but ONLY the block for this task. Never touch \
another item, never reorder sections, never rewrite the `_Last synced:_` line. Follow the file's \
existing format exactly: `- [ ] ` + backticked id + summary, six-space-indented `· ` links and \
`> ` notes. Preserve every existing note line; add to them rather than replacing them.

Deferrals and dates: resolve relative dates against today's date given below and write them \
absolute (2026-08-06, never "Thursday"). Record a deferral as a `> ` note on the item, and move \
the item to the section that now fits — `Blocked` when it is waiting on something, `Next` when \
it is simply later. Say plainly what you changed.

If he is only asking a question, answer it and change nothing."""


def task_block(text, ident):
    """Pull one item's lines out of TODO.md, with the section it sits in."""
    lines = text.split("\n")
    section = ""
    for i, line in enumerate(lines):
        if line.startswith("## "):
            section = line[3:].strip()
        m = ITEM_RE.match(line)
        if m and m.group(2) == ident:
            end = i
            while end + 1 < len(lines) and CONT_RE.match(lines[end + 1] or ""):
                end += 1
            return section, "\n".join(lines[i:end + 1])
    return "", ""


def transcript_path(project_dir, session_id):
    """Where Claude Code parks a headless session's transcript."""
    slug = str(project_dir).replace("/", "-")
    return Path.home() / ".claude" / "projects" / slug / ("%s.jsonl" % session_id)


def run_claude(project_dir, session_id, message, first, context):
    """One chat turn. Returns (reply, error). Resume keeps context server-side."""
    if not CLAUDE_BIN:
        return "", "the claude CLI was not found (looked on PATH and in ~/.local/bin)"
    prompt = "%s\n\n---\nJosh says: %s" % (context, message) if first else message
    cmd = [CLAUDE_BIN or "claude", "-p"]
    if first:
        cmd += [prompt, "--session-id", session_id]
    else:
        cmd += ["--resume", session_id, prompt]
    cmd += ["--output-format", "json",
            "--allowedTools", "Read", "Edit",
            "--append-system-prompt", CHAT_SYSTEM]
    try:
        proc = subprocess.run(cmd, cwd=str(project_dir), capture_output=True,
                              text=True, timeout=CHAT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return "", "claude did not answer within %ds" % CHAT_TIMEOUT
    except FileNotFoundError:
        return "", "cannot execute the claude CLI at %r" % CLAUDE_BIN
    if proc.returncode != 0:
        return "", (proc.stderr or "claude exited %d" % proc.returncode).strip()[:400]
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return "", "unparseable reply: %s" % proc.stdout[:200]
    if data.get("is_error"):
        return "", str(data.get("result") or "claude reported an error")[:400]
    return str(data.get("result") or "").strip(), ""


def run_resync(project_dir):
    """Drive the /briefing skill headlessly. Runs on a worker thread."""
    if not CLAUDE_BIN:
        return False, "", "the claude CLI was not found (looked on PATH and in ~/.local/bin)"
    cmd = [CLAUDE_BIN or "claude", "-p", RESYNC_PROMPT, "--output-format", "json",
           "--allowedTools"] + RESYNC_TOOLS
    try:
        proc = subprocess.run(cmd, cwd=str(project_dir), capture_output=True,
                              text=True, timeout=RESYNC_TIMEOUT)
    except subprocess.TimeoutExpired:
        return False, "", "resync did not finish within %ds" % RESYNC_TIMEOUT
    except FileNotFoundError:
        return False, "", "the claude CLI is not on PATH for this service"
    if proc.returncode != 0:
        return False, "", (proc.stderr or "claude exited %d" % proc.returncode).strip()[:600]
    try:
        data = json.loads(proc.stdout)
    except json.JSONDecodeError:
        return False, "", "unparseable reply: %s" % proc.stdout[:300]
    if data.get("is_error"):
        return False, "", str(data.get("result") or "claude reported an error")[:600]

    text = str(data.get("result") or "").strip()
    summary = ""
    for line in reversed(text.split("\n")):
        if line.strip().upper().startswith("RESYNC:"):
            summary = line.split(":", 1)[1].strip()
            break
    return True, (summary or text.split("\n")[-1][:200] or "finished"), ""


def resync_worker(project_dir):
    got = WRITER.acquire(timeout=30)
    if not got:
        with RESYNC_STATE:
            RESYNC.update(running=False, ok=False, finished=time.time(),
                          error="something else is writing TODO.md; try again")
        return
    try:
        ok, summary, error = run_resync(project_dir)
    finally:
        WRITER.release()
    with RESYNC_STATE:
        RESYNC.update(running=False, ok=ok, summary=summary, error=error,
                      finished=time.time())

ITEM_RE = re.compile(r"^- \[( |x)\] `([^`]+)`\s*(.*)$")
CONT_RE = re.compile(r"^ {6}(\S.*)$")
TAG_RE = re.compile(r"`#([a-z0-9-]+)`\s*$", re.I)
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


# --------------------------------------------------------------------------
# parsing
# --------------------------------------------------------------------------

# Render and write order. Blocked first because it is the only section whose
# items cannot move without someone else; Done last because it is history.
SECTION_ORDER = ["Blocked", "Awaiting review", "Now", "Next", "Backlog", "Done"]

# Sections that start expanded. Backlog and Done are long and rarely urgent.
SECTION_OPEN = {"Blocked", "Awaiting review", "Now", "Next"}

# Renamed 2026-08-13: "Waiting on others" folded into "Awaiting review", which
# now covers both PRs waiting on a reviewer and non-PR waits on a person.
SECTION_ALIASES = {"Waiting on others": "Awaiting review"}

NOTE_LIMIT = 300


def insert_heading(lines, heading):
    """Add a missing section heading in SECTION_ORDER position."""
    name = heading[3:].strip()
    try:
        rank = SECTION_ORDER.index(name)
    except ValueError:
        return lines + ["", heading, ""]
    for i, line in enumerate(lines):
        if not line.startswith("## "):
            continue
        other = line[3:].strip()
        if other in SECTION_ORDER and SECTION_ORDER.index(other) > rank:
            return lines[:i] + [heading, ""] + lines[i:]
    return lines + ["", heading, ""]


def order_sections(sections):
    """Sort parsed sections into SECTION_ORDER, unknown names last, order kept.

    Every canonical section is materialised even when TODO.md has no heading for
    it yet, so an empty Backlog still renders and can be moved into.
    """
    have = {s["name"] for s in sections}
    sections = list(sections) + [{"name": n, "prose": "", "items": []}
                                 for n in SECTION_ORDER if n not in have]

    def key(s):
        try:
            return (0, SECTION_ORDER.index(s["name"]))
        except ValueError:
            return (1, 0)
    return sorted(sections, key=key)


def parse_todo(text):
    """TODO.md -> {meta, sections:[{name, prose, items:[...]}]}."""
    meta = ""
    sections = []
    current = None
    item = None

    for line in text.split("\n"):
        if line.startswith("_Last synced:"):
            meta = line.strip("_")
            continue
        if line.startswith("## "):
            name = line[3:].strip()
            name = SECTION_ALIASES.get(name, name)
            current = {"name": name, "prose": "", "items": []}
            sections.append(current)
            item = None
            continue
        if current is None:
            continue

        m = ITEM_RE.match(line)
        if m:
            done = m.group(1) == "x"
            rest = m.group(3)
            tag = None
            tm = TAG_RE.search(rest)
            if tm:
                tag = tm.group(1)
                rest = TAG_RE.sub("", rest).strip()
            summary, _, status = rest.partition(" — ")
            item = {
                "id": m.group(2),
                "summary": summary.strip(),
                "status": status.strip(),
                "tag": tag,
                "done": done,
                "links": [],
                "notes": [],
            }
            current["items"].append(item)
            continue

        c = CONT_RE.match(line)
        if c and item is not None:
            body = c.group(1)
            if body.startswith("· "):
                item["links"].append(body[2:].strip())
            elif body.startswith("> "):
                item["notes"].append(body[2:].strip())
            else:
                item["notes"].append(body.strip())
            continue

        if line.strip().startswith("_") and current is not None and not current["items"]:
            current["prose"] = line.strip().strip("_")

    return {"meta": meta, "sections": sections}


def rewrite(text, ids, done=True, today=None, target=None):
    """Move items into a section. Returns (text, moved, missing).

    Mirrors the export logic the artifact uses: lift the item's line plus its
    six-space continuation lines, then reinsert. Notes are carried verbatim.

    `target` names the destination section; it defaults to Done/Next so the
    original done/reopen callers keep their behaviour. Only a move into Done
    stamps a date, and only a move out of it strips one.
    """
    today = today or datetime.now().strftime("%Y-%m-%d")
    if target is None:
        target = "Done" if done else "Next"
    done = target == "Done"
    lines = text.split("\n")
    moved, missing = [], []

    for ident in ids:
        # An arbitrary move does not know the item's current checkbox state, so
        # match either and let the target decide what gets written back.
        start, needle = -1, None
        for cand in ("- [ ] `%s`" % ident, "- [x] `%s`" % ident):
            for i, line in enumerate(lines):
                if line is not None and line.startswith(cand):
                    start, needle = i, cand
                    break
            if start != -1:
                break
        if start == -1:
            missing.append(ident)
            continue

        end = start
        while end + 1 < len(lines) and lines[end + 1] is not None \
                and CONT_RE.match(lines[end + 1] or ""):
            end += 1

        block = [l for l in lines[start:end + 1] if l is not None]
        for j in range(start, end + 1):
            lines[j] = None

        if done:
            rest = block[0][len(needle):]
            # Keep the project tag on the completed line: it is the only record
            # of which project the work belonged to, and reopening needs it back.
            tag = ""
            tm = TAG_RE.search(rest)
            if tm:
                tag = " `#%s`" % tm.group(1)
                rest = TAG_RE.sub("", rest)
            summary = rest.split(" — ")[0].replace("**", "").strip()
            moved.append({
                "id": ident,
                "line": "- [x] `%s` %s%s — %s" % (ident, summary, tag, today),
                "block": block[1:],
            })
        else:
            rest = block[0][len(needle):]
            # Drop the completion stamp, keep everything else including the tag.
            summary = re.sub(r"\s+—\s+(merged\s+)?\d{4}-\d{2}-\d{2}\s*$", "", rest).strip()
            moved.append({
                "id": ident,
                "line": "- [ ] `%s` %s" % (ident, summary),
                "block": block[1:],
            })

    kept = [l for l in lines if l is not None]
    heading = "## %s" % target
    if heading not in kept:
        kept = insert_heading(kept, heading)
    at = kept.index(heading) + 1
    while at < len(kept) and kept[at].strip() == "":
        at += 1

    payload = []
    for m in moved:
        payload.append(m["line"])
        # Reopened items keep their notes; completed ones keep them too, so the
        # context survives. Never drop a note.
        payload.extend(m["block"])
    kept[at:at] = payload

    for k, line in enumerate(kept):
        if line.startswith("_Last synced:"):
            verb = "marked done" if done else "reopened"
            base = re.sub(r"\s*·\s*\d+ (marked done|reopened)[^_]*", "", line.rstrip("_"))
            kept[k] = "%s · %d %s locally %s_" % (base.rstrip(), len(moved), verb, today)
            break

    return "\n".join(kept), moved, missing


def write_atomic(path, text):
    backups = backup_dir(path)
    backups.mkdir(exist_ok=True)
    if path.exists():
        stamp = time.strftime("%Y%m%dT%H%M%S")
        shutil.copy2(path, backups / ("%s.%s" % (path.name, stamp)))
        old = sorted(backups.glob("%s.*" % path.name))
        for stale in old[:-KEEP_BACKUPS]:
            stale.unlink()
    tmp = path.with_suffix(".md.tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


# --------------------------------------------------------------------------
# rendering
# --------------------------------------------------------------------------

def inline(text):
    """Minimal markdown inline -> HTML. Escapes first, so input is inert."""
    out = html.escape(text, quote=False)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)

    def link(m):
        label, url = m.group(1), m.group(2)
        if not url.startswith(("http://", "https://", "s3://", "mailto:")):
            return m.group(0)
        return '<a class="id" href="%s" rel="noreferrer">%s</a>' % (html.escape(url, quote=True), label)

    return LINK_RE.sub(link, out)


SEVERITY = {"crit": "crit", "warn": "warn", "info": ""}


def render_attention(state):
    rows = state.get("attention") or []
    if not rows:
        return ""
    out = ['<section><h2>Needs you<span class="count">%02d</span></h2><div class="stack">' % len(rows)]
    for r in rows:
        sev = SEVERITY.get(r.get("severity", "info"), "")
        out.append('<article class="item %s"><div class="stripe"></div><div class="body">' % sev)
        out.append('<div class="top"><span class="title">%s</span>' % inline(r.get("title", "")))
        for p in r.get("pills") or []:
            out.append('<span class="pill %s">%s</span>' % (sev if r.get("severity") == "crit" else "", html.escape(p)))
        for l in r.get("links") or []:
            out.append('<a class="id" href="%s" rel="noreferrer">%s</a>'
                       % (html.escape(l.get("url", ""), quote=True), html.escape(l.get("label", ""))))
        out.append("</div>")
        if r.get("detail"):
            out.append('<p class="why">%s</p>' % inline(r["detail"]))
        out.append("</div></article>")
    out.append("</div></section>")
    return "".join(out)


def render_notes(notes):
    """Notes clamped to NOTE_LIMIT characters, with the rest behind a toggle."""
    if not notes:
        return ""
    joined = " ".join(notes)
    if len(joined) <= NOTE_LIMIT:
        return "".join('<small class="note-line">%s</small>' % inline(n) for n in notes)

    clipped = joined[:NOTE_LIMIT].rsplit(" ", 1)[0]
    full = "".join('<small class="note-line">%s</small>' % inline(n) for n in notes)
    return ('<div class="notes">'
            '<small class="note-line clip">%s…</small>'
            '<div class="note-full" hidden>%s</div>'
            '<button class="more" type="button">more</button>'
            "</div>") % (inline(clipped), full)


def render_move(item, current):
    """Dropdown that moves one item to another section."""
    opts = []
    for name in SECTION_ORDER:
        if name == current:
            continue
        opts.append('<option value="%s">%s</option>' % (html.escape(name, quote=True),
                                                        html.escape(name)))
    return ('<select class="mv" data-id="%s" title="Move %s" aria-label="Move %s to another section">'
            '<option value="">move…</option>%s</select>'
            % (html.escape(item["id"], quote=True), html.escape(item["id"], quote=True),
               html.escape(item["id"], quote=True), "".join(opts)))


def render_items(section):
    out = []
    for it in section["items"]:
        cls = "row done" if it["done"] else "row"
        out.append('<div class="%s" data-row="%s">' % (cls, html.escape(it["id"], quote=True)))
        if it["done"]:
            out.append('<button class="reopen" data-id="%s" title="Reopen">↩</button>'
                       % html.escape(it["id"], quote=True))
        else:
            out.append('<input class="ck" type="checkbox" data-id="%s" aria-label="Mark %s done">'
                       % (html.escape(it["id"], quote=True), html.escape(it["id"], quote=True)))
        out.append('<button class="chat" data-id="%s" title="Chat about %s">chat</button>'
                   % (html.escape(it["id"], quote=True), html.escape(it["id"], quote=True)))
        out.append(render_move(it, section["name"]))
        out.append('<span class="id">%s</span>' % html.escape(it["id"]))
        out.append('<span class="txt">%s' % inline(it["summary"]))
        if it["tag"]:
            out.append(' <span class="tag">#%s</span>' % html.escape(it["tag"]))
        if it["status"]:
            out.append("<small>%s</small>" % inline(it["status"]))
        for l in it["links"]:
            out.append("<small>%s</small>" % inline(l))
        out.append(render_notes(it["notes"]))
        out.append("</span></div>")
    return "".join(out)


def render_page(todo, state, token):
    counts = state.get("counts") or {}
    sources = state.get("sources") or []
    open_n = sum(1 for s in todo["sections"] for i in s["items"] if not i["done"])
    done_n = sum(1 for s in todo["sections"] for i in s["items"] if i["done"])

    src_html = "".join(
        '<span class="src %s">%s</span>' % ("" if s.get("ok") else "off", html.escape(s.get("name", "")))
        for s in sources
    )
    counts_html = "".join(
        '<span><b>%s</b> %s</span>' % (html.escape(str(v)), html.escape(k.replace("_", " ")))
        for k, v in counts.items()
    )

    sections_html = []
    for s in order_sections(todo["sections"]):
        name = s["name"]
        body = (render_items(s) if s["items"]
                else '<p class="lede">%s</p>' % inline(s["prose"] or "nothing here"))
        sections_html.append(
            '<details class="board" data-sec="%s"%s>'
            '<summary><h2>%s<span class="count">%02d</span></h2></summary>'
            '<div class="group">%s</div></details>'
            % (html.escape(name, quote=True),
               " open" if name in SECTION_OPEN else "",
               html.escape(name), len(s["items"]), body))

    moved = state.get("moved") or []
    moved_html = ""
    if moved:
        moved_html = ('<section><h2>Moved since last briefing<span class="count">%02d</span></h2>'
                      '<div class="group">%s</div></section>'
                      % (len(moved), "".join('<div class="row"><span class="txt">%s</span></div>'
                                             % inline(m) for m in moved)))

    repos = state.get("repos") or []
    repos_html = ""
    if repos:
        rows = []
        for r in repos:
            pill = "warn" if r.get("state") != "synced" else "ok"
            rows.append('<div class="row"><span class="id">%s</span><span class="txt">%s<small>%s</small></span>'
                        '<span class="pill %s">%s</span></div>'
                        % (html.escape(r.get("name", "")), html.escape(r.get("branch", "")),
                           inline(r.get("detail", "")), pill, html.escape(r.get("state", ""))))
        repos_html = ('<section class="board"><h2>Local checkouts</h2><div class="group">%s</div></section>'
                      % "".join(rows))

    queue = state.get("review_queue") or {}
    queue_html = ""
    if queue.get("oldest"):
        rows = []
        mx = max(q.get("days", 1) for q in queue["oldest"]) or 1
        for q in queue["oldest"]:
            pct = int(100 * q.get("days", 0) / mx)
            cls = "" if pct > 60 else "warn"
            rows.append('<tr><td><a class="id" href="%s" rel="noreferrer">%s</a></td><td>%s</td><td>%s</td>'
                        '<td class="barcell"><span class="bar %s" style="width:%d%%"></span></td>'
                        '<td class="num">%s</td></tr>'
                        % (html.escape(q.get("url", "#"), quote=True), html.escape(q.get("pr", "")),
                           html.escape(q.get("author", "")), html.escape(q.get("what", "")),
                           cls, pct, q.get("days", 0)))
        queue_html = (
            '<section><h2>Review queue<span class="count">%s</span></h2>'
            '<p class="lede">Every row is a teammate who cannot merge until you look.</p>'
            '<div class="scroll"><table><thead><tr><th>PR</th><th>Author</th><th>What</th>'
            '<th class="barcell">Waiting</th><th>Days</th></tr></thead><tbody>%s</tbody></table></div></section>'
            % (queue.get("total", len(queue["oldest"])), "".join(rows)))

    shipped = state.get("shipped") or []
    shipped_html = ""
    if shipped:
        chips = "".join('<a class="chip %s" href="%s" rel="noreferrer">%s · %s</a>'
                        % ("fresh" if s.get("fresh") else "", html.escape(s.get("url", "#"), quote=True),
                           html.escape(s.get("id", "")), html.escape(s.get("what", "")))
                        for s in shipped)
        shipped_html = ('<section><h2>Shipped, last 7 days<span class="count">%02d</span></h2>'
                        '<div class="chips">%s</div></section>' % (len(shipped), chips))

    return PAGE.format(
        css=CSS,
        headline=inline(state.get("headline") or "Everything, from the file itself."),
        generated=html.escape(state.get("generated") or "state.json missing — run /briefing"),
        meta=inline(todo["meta"] or ""),
        sources=src_html,
        counts=counts_html,
        open_n=open_n,
        done_n=done_n,
        moved=moved_html,
        attention=render_attention(state),
        sections="".join(sections_html),
        repos=repos_html,
        queue=queue_html,
        shipped=shipped_html,
        token=html.escape(token, quote=True),
    )


# --------------------------------------------------------------------------
# http
# --------------------------------------------------------------------------

class Handler(BaseHTTPRequestHandler):
    server_version = "todo-dashboard"
    todo_path: Path = HERE / "TODO.md"
    state_path: Path = HERE / "state.json"
    token: str = ""

    def log_message(self, format, *args):  # noqa: A002 - signature is the base class's
        sys.stderr.write("  %s\n" % (format % args))

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        data = body.encode("utf-8") if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy",
                         "default-src 'none'; style-src 'unsafe-inline'; "
                         "script-src 'unsafe-inline'; connect-src 'self'")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj), "application/json; charset=utf-8")

    def _load(self):
        todo = parse_todo(self.todo_path.read_text(encoding="utf-8"))
        state = {}
        if self.state_path.exists():
            try:
                state = json.loads(self.state_path.read_text(encoding="utf-8"))
            except json.JSONDecodeError as exc:
                state = {"headline": "state.json is malformed: %s" % exc}
        return todo, state

    def do_GET(self):
        if self.path.split("?")[0] == "/":
            todo, state = self._load()
            self._send(200, render_page(todo, state, self.token))
        elif self.path.split("?")[0] == "/api/todo":
            todo, _ = self._load()
            self._json(200, todo)
        elif self.path.split("?")[0] == "/api/resync/status":
            self._resync_status()
        else:
            self._json(404, {"error": "not found"})

    def _authorized(self):
        # A local server that rewrites a file needs both checks: any page in the
        # browser can POST to localhost, but it cannot read our token.
        origin = self.headers.get("Origin")
        if origin and not re.match(r"^https?://(127\.0\.0\.1|localhost)(:\d+)?$", origin):
            self._json(403, {"error": "bad origin"})
            return False
        if self.token and self.headers.get("X-Token") != self.token:
            self._json(403, {"error": "bad token"})
            return False
        return True

    def _body(self):
        length = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(length) or b"{}")

    def _chat(self):
        try:
            payload = self._body()
        except (ValueError, TypeError) as exc:
            self._json(400, {"error": "bad body: %s" % exc})
            return

        ident = str(payload.get("task") or "")
        session = str(payload.get("session") or "")
        message = str(payload.get("message") or "").strip()
        first = bool(payload.get("first"))
        if not (ident and session and message):
            self._json(400, {"error": "task, session and message are all required"})
            return
        if not re.match(r"^[0-9a-f-]{36}$", session):
            self._json(400, {"error": "session must be a uuid"})
            return

        before = self.todo_path.read_text(encoding="utf-8")
        section, block = task_block(before, ident)
        if not block:
            self._json(404, {"error": "%s is not in TODO.md" % ident})
            return

        context = ("Today is %s. The task is `%s`, currently in the `%s` section of TODO.md "
                   "at %s. Here is its exact block:\n\n%s"
                   % (datetime.now().strftime("%Y-%m-%d (%A)"), ident, section,
                      self.todo_path, block))

        if not WRITER.acquire(timeout=5):
            self._json(409, {"error": "a resync is running — try again when it finishes"})
            return
        try:
            reply, error = run_claude(self.todo_path.parent, session, message, first, context)
        finally:
            WRITER.release()
        if error:
            self._json(502, {"error": error})
            return

        after = self.todo_path.read_text(encoding="utf-8")
        self._json(200, {"reply": reply, "changed": after != before})

    def _chat_end(self):
        try:
            session = str(self._body().get("session") or "")
        except (ValueError, TypeError):
            session = ""
        if not re.match(r"^[0-9a-f-]{36}$", session):
            self._json(400, {"error": "session must be a uuid"})
            return
        path = transcript_path(self.todo_path.parent, session)
        existed = path.exists()
        if existed:
            path.unlink()
        self._json(200, {"deleted": existed})

    def _resync_start(self):
        with RESYNC_STATE:
            if RESYNC["running"]:
                self._json(409, {"error": "a resync is already running"})
                return
            RESYNC.update(running=True, ok=None, error="", summary="",
                          started=time.time(), finished=None)
        threading.Thread(target=resync_worker, args=(self.todo_path.parent,),
                         daemon=True).start()
        self._json(202, {"started": True})

    def _resync_status(self):
        with RESYNC_STATE:
            state = dict(RESYNC)
        if state["started"]:
            end = state["finished"] or time.time()
            state["elapsed"] = int(end - state["started"])
        self._json(200, state)

    def do_POST(self):
        route = self.path.split("?")[0]
        if route == "/api/resync":
            if self._authorized():
                self._resync_start()
            return
        if route == "/api/chat":
            if self._authorized():
                self._chat()
            return
        if route == "/api/chat/end":
            if self._authorized():
                self._chat_end()
            return
        if route not in ("/api/done", "/api/reopen", "/api/move"):
            self._json(404, {"error": "not found"})
            return

        if not self._authorized():
            return

        try:
            body = self._body()
            ids = [str(i) for i in (body.get("ids") or [])]
        except (ValueError, TypeError) as exc:
            self._json(400, {"error": "bad body: %s" % exc})
            return
        if not ids:
            self._json(400, {"error": "no ids"})
            return

        target = None
        if route == "/api/move":
            target = str(body.get("section") or "")
            if target not in SECTION_ORDER:
                self._json(400, {"error": "unknown section: %r" % target,
                                 "sections": SECTION_ORDER})
                return

        text = self.todo_path.read_text(encoding="utf-8")
        new_text, moved, missing = rewrite(text, ids, done=(route == "/api/done"),
                                           target=target)
        if missing:
            self._json(409, {"error": "not found in TODO.md", "missing": missing})
            return

        write_atomic(self.todo_path, new_text)
        self._json(200, {"moved": [m["id"] for m in moved]})


def main():
    ap = argparse.ArgumentParser()
    # 8787 is taken by the Kestrel Fleet dashboard on this machine.
    ap.add_argument("--port", type=int, default=8788)
    ap.add_argument("--todo", default=str(HERE / "TODO.md"))
    ap.add_argument("--state", default=str(HERE / "state.json"))
    ap.add_argument("--no-token", action="store_true",
                    help="skip the write token (convenient, less safe)")
    args = ap.parse_args()

    Handler.todo_path = Path(args.todo).resolve()
    Handler.state_path = Path(args.state).resolve()
    Handler.token = "" if args.no_token else secrets.token_urlsafe(16)

    if not Handler.todo_path.exists():
        sys.exit("no TODO.md at %s" % Handler.todo_path)

    try:
        srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    except OSError as exc:
        sys.exit("cannot bind 127.0.0.1:%d — %s\nSomething else is listening; try --port %d."
                 % (args.port, exc, args.port + 1))
    print("dashboard  http://127.0.0.1:%d" % args.port)
    print("todo       %s" % Handler.todo_path)
    print("state      %s%s" % (Handler.state_path,
                               "" if Handler.state_path.exists() else "  (missing — run /briefing)"))
    print("writes     %s" % ("token required" if Handler.token else "UNPROTECTED (--no-token)"))
    print("backups    %s (last %d)" % (backup_dir(Handler.todo_path), KEEP_BACKUPS))
    print("claude     %s" % (CLAUDE_BIN or "NOT FOUND — chat and resync will fail"))
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nstopped")


CSS = """
:root{--paper:#F0EADB;--ink:#0E2027;--depth:#4E6E79;--rule:#CFC5AE;--magenta:#B32A6E;
--magenta-dim:#EBD4DF;--amber:#A9761A;--amber-dim:#EFE1C4;--kelp:#2E6A52;--kelp-dim:#D6E4DB;
--bg:var(--paper);--panel:#F7F3E9;--fg:var(--ink);--fg-2:var(--depth);--edge:var(--rule);
--sounding:#C6D6DB;
--sans:ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
--serif:"Iowan Old Style","Palatino Linotype",Palatino,"Book Antiqua",Georgia,serif;
--mono:ui-monospace,"SF Mono",SFMono-Regular,"Cascadia Mono",Menlo,Consolas,monospace;
--step--1:.78rem;--step-0:.94rem;--step-2:1.45rem;--step-3:2.1rem}
@media(prefers-color-scheme:dark){:root{--bg:#0A171D;--panel:#10242C;--fg:#E6EDEF;--fg-2:#93AEB6;
--edge:#1E3B45;--sounding:#24454F;--magenta:#F07BB0;--magenta-dim:#3A1E2C;--amber:#D9A748;
--amber-dim:#33290F;--kelp:#6FBF97;--kelp-dim:#143224}}
:root[data-theme=dark]{--bg:#0A171D;--panel:#10242C;--fg:#E6EDEF;--fg-2:#93AEB6;--edge:#1E3B45;
--sounding:#24454F;--magenta:#F07BB0;--magenta-dim:#3A1E2C;--amber:#D9A748;--amber-dim:#33290F;
--kelp:#6FBF97;--kelp-dim:#143224}
:root[data-theme=light]{--bg:var(--paper);--panel:#F7F3E9;--fg:var(--ink);--fg-2:var(--depth);
--edge:var(--rule);--sounding:#C6D6DB;--magenta:#B32A6E;--magenta-dim:#EBD4DF;--amber:#A9761A;
--amber-dim:#EFE1C4;--kelp:#2E6A52;--kelp-dim:#D6E4DB}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font-family:var(--sans);font-size:var(--step-0);
line-height:1.5;-webkit-font-smoothing:antialiased}
.wrap{max-width:74rem;margin:0 auto;padding:clamp(1.25rem,3vw,2.75rem) clamp(1rem,3vw,2rem) 7rem;
display:flex;flex-direction:column;gap:2.25rem}
.eyebrow{font-size:var(--step--1);text-transform:uppercase;letter-spacing:.16em;color:var(--fg-2);margin:0}
h1{font-family:var(--serif);font-size:var(--step-3);font-weight:400;line-height:1.1;
text-wrap:balance;margin:0;letter-spacing:-.01em}
h1 em{font-style:italic;color:var(--magenta)}
.masthead{display:flex;flex-direction:column;gap:.9rem}
.readout{display:flex;flex-wrap:wrap;gap:0 1.5rem;align-items:baseline;padding:.7rem 0;
border-top:1px solid var(--edge);border-bottom:1px solid var(--edge);font-family:var(--mono);
font-size:var(--step--1);font-variant-numeric:tabular-nums;color:var(--fg-2)}
.readout b{color:var(--fg);font-weight:600}
.src{display:inline-flex;align-items:center;gap:.4rem}
.src::before{content:"";width:.5rem;height:.5rem;border-radius:50%;background:var(--kelp)}
.src.off::before{background:transparent;box-shadow:inset 0 0 0 1px var(--fg-2)}
section{display:flex;flex-direction:column;gap:.9rem}
h2{font-family:var(--serif);font-style:italic;font-size:var(--step-2);font-weight:400;margin:0}
h2 .count{font-family:var(--mono);font-style:normal;font-size:var(--step--1);color:var(--fg-2);
vertical-align:.35em;margin-left:.5rem;font-variant-numeric:tabular-nums}
.lede{margin:0;color:var(--fg-2);max-width:62ch}
.stack{display:flex;flex-direction:column;gap:.6rem}
.item{display:grid;grid-template-columns:.28rem 1fr;gap:0 1rem;background:var(--panel);
border:1px solid var(--edge);border-left:0;overflow:hidden}
.item>.stripe{background:var(--sounding)}
.item.crit>.stripe{background:var(--magenta)}
.item.warn>.stripe{background:var(--amber)}
.item>.body{padding:.85rem 1rem .9rem 0;display:flex;flex-direction:column;gap:.35rem}
.item .top{display:flex;flex-wrap:wrap;align-items:baseline;gap:.5rem .7rem}
.item .title{font-weight:600}
.item .why{color:var(--fg-2);font-size:var(--step--1);margin:0;max-width:74ch}
.board{display:flex;flex-direction:column;gap:1.1rem}
.group{display:flex;flex-direction:column;gap:.3rem}
.row{display:flex;gap:.65rem;align-items:baseline;padding:.35rem 0;border-bottom:1px dotted var(--edge)}
.row:last-child{border-bottom:0}
.row .txt{flex:1;min-width:0}
.row .txt small{display:block;color:var(--fg-2);font-size:var(--step--1)}
.row .txt small.note-line{padding-left:.7rem;border-left:1px solid var(--edge)}
.notes button.more{background:none;border:0;padding:0 0 0 .7rem;cursor:pointer;
  font:inherit;font-size:var(--step--1);color:var(--fg-2);text-decoration:underline dotted}
.notes button.more:hover{color:var(--fg)}
select.mv{background:none;border:1px solid var(--edge);border-radius:3px;color:var(--fg-2);
  font:inherit;font-size:var(--step--1);padding:0 .2rem;opacity:0;transition:opacity .12s}
.row:hover select.mv,select.mv:focus-visible{opacity:1}
/* The whole header bar is the hit target, not a small caret. */
details.board>summary{cursor:pointer;list-style:none;display:flex;align-items:center;
  gap:.7rem;padding:.75rem 1rem;border:1px solid var(--edge);border-radius:5px;
  background:var(--panel);user-select:none}
details.board>summary::-webkit-details-marker{display:none}
details.board>summary:hover{border-color:var(--fg-2)}
details.board>summary:focus-visible{outline:2px solid var(--fg-2);outline-offset:2px}
details.board>summary h2{display:inline-flex;align-items:baseline;gap:.6rem;flex:1}
details.board>summary::before{content:"▸";font-size:1.1rem;line-height:1;color:var(--fg-2);
  transition:transform .12s;display:inline-block;width:1rem;text-align:center}
details.board[open]>summary::before{transform:rotate(90deg)}
details.board[open]>summary{border-bottom-left-radius:0;border-bottom-right-radius:0}
details.board[open]>.group{border:1px solid var(--edge);border-top:0;
  border-radius:0 0 5px 5px;padding:.6rem 1rem .8rem}
.row.done{opacity:.55}
.row.done .txt{text-decoration:line-through;text-decoration-thickness:1px}
.id{font-family:var(--mono);font-size:var(--step--1);font-variant-numeric:tabular-nums;
color:var(--fg);text-decoration:none;white-space:nowrap}
a.id{border-bottom:1px solid var(--sounding)}
a.id:hover,a.id:focus-visible{border-bottom-color:var(--magenta);color:var(--magenta)}
a:focus-visible,.ck:focus-visible,button:focus-visible{outline:2px solid var(--magenta);outline-offset:3px}
.pill{font-size:.68rem;text-transform:uppercase;letter-spacing:.1em;font-weight:600;
padding:.15rem .45rem;border:1px solid var(--edge);color:var(--fg-2);white-space:nowrap}
.pill.crit{color:var(--magenta);border-color:var(--magenta);background:var(--magenta-dim)}
.pill.warn{color:var(--amber);border-color:var(--amber);background:var(--amber-dim)}
.pill.ok{color:var(--kelp);border-color:var(--kelp);background:var(--kelp-dim)}
.tag{font-family:var(--mono);font-size:var(--step--1);color:var(--fg-2)}
.ck{appearance:none;-webkit-appearance:none;flex:0 0 auto;width:.95rem;height:.95rem;margin:0;
border:1px solid var(--fg-2);background:transparent;cursor:pointer;position:relative;top:.15rem}
.ck:hover{border-color:var(--magenta)}
.ck:checked{background:var(--magenta);border-color:var(--magenta)}
.ck:checked::after{content:"";position:absolute;left:.24rem;top:.06rem;width:.28rem;height:.52rem;
border:solid var(--bg);border-width:0 1.5px 1.5px 0;transform:rotate(45deg)}
.marked{opacity:.5}
.marked .txt{text-decoration:line-through}
button.reopen{flex:0 0 auto;width:1.1rem;height:1.1rem;padding:0;line-height:1;font-size:.7rem;
border:1px solid var(--edge);background:transparent;color:var(--fg-2);cursor:pointer}
button.reopen:hover{border-color:var(--magenta);color:var(--magenta)}
button.chat{flex:0 0 auto;padding:.05rem .35rem;font-family:var(--mono);font-size:.66rem;
border:1px solid var(--edge);background:transparent;color:var(--fg-2);cursor:pointer;
opacity:0;transition:opacity .12s}
.row:hover button.chat,button.chat:focus-visible{opacity:1}
button.chat:hover{border-color:var(--magenta);color:var(--magenta)}
dialog.chatbox{border:1px solid var(--edge);background:var(--bg);color:var(--fg);padding:0;
width:min(46rem,94vw);max-height:86vh;box-shadow:0 1.5rem 3rem rgba(0,0,0,.35)}
dialog.chatbox::backdrop{background:rgba(8,20,26,.62)}
.chatbox .head{display:flex;align-items:baseline;gap:.7rem;padding:.85rem 1rem;
border-bottom:1px solid var(--edge);background:var(--panel)}
.chatbox .head .who{font-family:var(--mono);font-size:var(--step--1)}
.chatbox .head .sum{flex:1;font-weight:600;min-width:0}
.chatbox .head .x{border:1px solid var(--edge);background:transparent;color:var(--fg-2);
cursor:pointer;padding:.1rem .45rem;font-family:var(--mono)}
.chatbox .head .x:hover{border-color:var(--magenta);color:var(--magenta)}
.chatbox .ctx{margin:0;padding:.7rem 1rem;border-bottom:1px solid var(--edge);color:var(--fg-2);
font-size:var(--step--1);white-space:pre-wrap;font-family:var(--mono);max-height:9rem;overflow:auto}
.chatbox .log{padding:1rem;display:flex;flex-direction:column;gap:.7rem;overflow-y:auto;
max-height:44vh;min-height:5rem}
.chatbox .turn{display:flex;flex-direction:column;gap:.2rem;max-width:56ch}
.chatbox .turn.me{align-self:flex-end;align-items:flex-end;text-align:right}
.chatbox .turn .lbl{font-family:var(--mono);font-size:.66rem;text-transform:uppercase;
letter-spacing:.1em;color:var(--fg-2)}
.chatbox .turn .txt{white-space:pre-wrap}
.chatbox .turn.me .txt{background:var(--magenta-dim);border:1px solid var(--magenta);padding:.4rem .6rem}
.chatbox .turn.err .txt{color:var(--magenta)}
.chatbox .turn.wrote .lbl{color:var(--kelp)}
.chatbox form{display:flex;gap:.6rem;padding:.85rem 1rem;border-top:1px solid var(--edge);
background:var(--panel)}
.chatbox input[type=text]{flex:1;min-width:0;font-family:var(--sans);font-size:var(--step-0);
padding:.45rem .6rem;border:1px solid var(--edge);background:var(--bg);color:var(--fg)}
.chatbox input[type=text]:focus-visible{outline:2px solid var(--magenta);outline-offset:1px}
.chatbox .foot{padding:0 1rem .8rem;color:var(--fg-2);font-size:.7rem;font-family:var(--mono)}
.dots::after{content:"";animation:dots 1.2s steps(4,end) infinite}
@keyframes dots{0%{content:""}25%{content:"."}50%{content:".."}75%{content:"..."}}
@media(prefers-reduced-motion:reduce){.dots::after{content:"..."; animation:none}
button.chat{opacity:1}}
.scroll{overflow-x:auto}
table{border-collapse:collapse;width:100%;font-size:var(--step--1)}
th{text-align:left;font-size:.68rem;text-transform:uppercase;letter-spacing:.12em;color:var(--fg-2);
font-weight:600;padding:0 .7rem .4rem 0;border-bottom:1px solid var(--edge);white-space:nowrap}
td{padding:.45rem .7rem;border-bottom:1px dotted var(--edge);vertical-align:baseline}
td.num{font-family:var(--mono);font-variant-numeric:tabular-nums;text-align:right}
.bar{display:block;height:.4rem;background:var(--magenta);min-width:2px}
.bar.warn{background:var(--amber)}
.barcell{width:34%;min-width:6rem}
.chips{display:flex;flex-wrap:wrap;gap:.4rem}
.chip{font-family:var(--mono);font-size:var(--step--1);padding:.2rem .5rem;border:1px solid var(--kelp);
background:var(--kelp-dim);color:var(--fg);text-decoration:none}
.chip.fresh{border-width:2px;font-weight:600}
.chip:hover{border-color:var(--magenta)}
/* Sections stack full width, one per row — never side by side. */
.cols{display:flex;flex-direction:column;gap:.75rem}
footer{border-top:1px solid var(--edge);padding-top:1rem;color:var(--fg-2);font-size:var(--step--1);
font-family:var(--mono);display:flex;flex-wrap:wrap;gap:.3rem 1.25rem}
.bar-fixed{position:fixed;left:0;right:0;bottom:0;z-index:10;background:var(--panel);
border-top:1px solid var(--edge);padding:.7rem clamp(1rem,3vw,2rem);font-family:var(--mono);
font-size:var(--step--1)}
.bar-fixed .inner{max-width:74rem;margin:0 auto;display:flex;flex-wrap:wrap;align-items:center;gap:.6rem 1rem}
.bar-fixed .msg{flex:1;min-width:12rem;color:var(--fg-2)}
.bar-fixed .msg.err{color:var(--magenta)}
.bar-fixed .msg.ok{color:var(--kelp)}
.bar-fixed button.go{font-family:var(--sans);text-transform:uppercase;letter-spacing:.1em;
font-weight:600;padding:.4rem .9rem;border:1px solid var(--fg);background:transparent;color:var(--fg);cursor:pointer}
.bar-fixed button.go:hover:not(:disabled){background:var(--magenta);border-color:var(--magenta);color:var(--bg)}
.bar-fixed button.go:disabled{opacity:.4;cursor:not-allowed}
@media(prefers-reduced-motion:no-preference){a.id,.chip,button,.ck{transition:color .12s,border-color .12s,background .12s,opacity .12s}}
"""

PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>TODO — live</title><style>{css}</style></head><body>
<div class="wrap">
  <header class="masthead">
    <p class="eyebrow">Local dashboard · reads and writes TODO.md</p>
    <h1>{headline}</h1>
    <div class="readout">
      <span><b>{generated}</b></span>
      {sources}
      {counts}
      <span><b>{open_n}</b> open here</span>
      <span><b>{done_n}</b> done here</span>
    </div>
  </header>
  {moved}
  {attention}
  <div class="cols">{sections}</div>
  {repos}
  {queue}
  {shipped}
  <footer>
    <span>{meta}</span>
    <span>live from TODO.md · every write is backed up under .todo-backups/</span>
  </footer>
</div>
<div class="bar-fixed"><div class="inner">
  <span><b id="tally">0</b> selected</span>
  <button class="go" id="apply" disabled>Mark done</button>
  <button class="go" id="resync">Resync</button>
  <span class="msg" id="msg">Tick items, then apply. Hover a row for <b>chat</b>.</span>
</div></div>

<dialog class="chatbox" id="chatbox">
  <div class="head">
    <span class="who" id="c-id"></span>
    <span class="sum" id="c-sum"></span>
    <button class="x" id="c-close" aria-label="Close chat">esc</button>
  </div>
  <pre class="ctx" id="c-ctx"></pre>
  <div class="log" id="c-log"></div>
  <form id="c-form">
    <input type="text" id="c-input" autocomplete="off"
           placeholder="punt this to Thursday · what's blocking it? · add a note that…">
    <button class="go" id="c-send">Send</button>
  </form>
  <p class="foot">Closing deletes this conversation. Edits to TODO.md are kept.</p>
</dialog>
<script>
(function(){{
  var TOKEN = "{token}";
  var msg = document.getElementById("msg");
  var tally = document.getElementById("tally");
  var apply = document.getElementById("apply");

  function say(t, k){{ msg.textContent = t; msg.className = "msg" + (k ? " " + k : ""); }}
  function ticked(){{
    return Array.prototype.slice.call(document.querySelectorAll(".ck:checked"))
      .map(function(b){{ return b.dataset.id; }});
  }}
  function refresh(){{
    var n = ticked().length;
    tally.textContent = String(n);
    apply.disabled = n === 0;
  }}

  function post(route, ids, extra){{
    say("Writing…");
    var payload = {{ ids: ids }};
    if (extra) {{ Object.keys(extra).forEach(function(k){{ payload[k] = extra[k]; }}); }}
    return fetch(route, {{
      method: "POST",
      headers: {{ "Content-Type": "application/json", "X-Token": TOKEN }},
      body: JSON.stringify(payload)
    }}).then(function(r){{
      return r.json().then(function(body){{
        if (!r.ok) {{ throw new Error(body.error + (body.missing ? ": " + body.missing.join(", ") : "")); }}
        return body;
      }});
    }});
  }}

  document.addEventListener("change", function(e){{
    if (e.target.classList.contains("ck")) {{
      var id = e.target.dataset.id, on = e.target.checked;
      Array.prototype.slice.call(document.querySelectorAll('.ck[data-id="' + id + '"]'))
        .forEach(function(b){{ b.checked = on; var r = b.closest("[data-row]");
          if (r) {{ r.classList.toggle("marked", on); }} }});
      refresh();
    }}
    if (e.target.classList.contains("mv")) {{
      var sel = e.target, to = sel.value;
      if (!to) {{ return; }}
      sel.disabled = true;
      post("/api/move", [sel.dataset.id], {{ section: to }}).then(function(){{
        say("Moved " + sel.dataset.id + " to " + to + ". Reloading…", "ok");
        location.reload();
      }}, function(err){{ say(err.message, "err"); sel.disabled = false; sel.value = ""; }});
    }}
  }});

  // Note clamp: swap the 300-char preview for the full set, and back.
  document.addEventListener("click", function(e){{
    var more = e.target.closest(".notes button.more");
    if (!more) {{ return; }}
    var box = more.closest(".notes");
    var full = box.querySelector(".note-full");
    var clip = box.querySelector(".clip");
    var open = full.hasAttribute("hidden");
    if (open) {{ full.removeAttribute("hidden"); clip.setAttribute("hidden", ""); more.textContent = "less"; }}
    else {{ full.setAttribute("hidden", ""); clip.removeAttribute("hidden"); more.textContent = "more"; }}
  }});

  // Remember which sections the user collapsed, across reloads.
  try {{
    var SKEY = "todo.sections";
    var saved = JSON.parse(localStorage.getItem(SKEY) || "{{}}");
    Array.prototype.slice.call(document.querySelectorAll("details.board")).forEach(function(d){{
      var k = d.dataset.sec;
      if (Object.prototype.hasOwnProperty.call(saved, k)) {{ d.open = !!saved[k]; }}
      d.addEventListener("toggle", function(){{
        saved[k] = d.open;
        localStorage.setItem(SKEY, JSON.stringify(saved));
      }});
    }});
  }} catch (err) {{ /* private mode or blocked storage: sections just use defaults */ }}

  apply.addEventListener("click", function(){{
    var ids = ticked();
    if (!ids.length) {{ return; }}
    apply.disabled = true;
    post("/api/done", ids).then(function(body){{
      say("Wrote " + body.moved.length + " to Done. Reloading…", "ok");
      location.reload();
    }}, function(err){{ say(err.message, "err"); apply.disabled = false; }});
  }});

  document.addEventListener("click", function(e){{
    var b = e.target.closest(".reopen");
    if (!b) {{ return; }}
    post("/api/reopen", [b.dataset.id]).then(function(){{
      say("Reopened. Reloading…", "ok");
      location.reload();
    }}, function(err){{ say(err.message, "err"); }});
  }});

  // ---- resync ------------------------------------------------------------
  // Long job: start it, then poll. Survives a page reload because the state
  // lives on the server, so a refresh mid-resync picks the progress back up.

  var resyncBtn = document.getElementById("resync");
  var polling = null;

  function fmt(sec){{
    var m = Math.floor(sec / 60), s = sec % 60;
    return m ? (m + "m " + (s < 10 ? "0" : "") + s + "s") : (s + "s");
  }}

  function showResync(st){{
    if (st.running) {{
      resyncBtn.disabled = true;
      apply.disabled = true;
      say("Resyncing Jira, GitHub and local checkouts… " + fmt(st.elapsed || 0), null);
      return true;
    }}
    resyncBtn.disabled = false;
    refresh();
    if (st.ok === true) {{
      say("Resynced in " + fmt(st.elapsed || 0) + ". " + (st.summary || "") + " Reloading…", "ok");
      setTimeout(function(){{ location.reload(); }}, 1200);
    }} else if (st.ok === false) {{
      say("Resync failed: " + (st.error || "unknown"), "err");
    }}
    return false;
  }}

  function poll(){{
    fetch("/api/resync/status").then(function(r){{ return r.json(); }}).then(function(st){{
      if (!showResync(st) && polling) {{ clearInterval(polling); polling = null; }}
    }}, function(){{}});
  }}

  resyncBtn.addEventListener("click", function(){{
    resyncBtn.disabled = true;
    say("Starting resync…");
    fetch("/api/resync", {{
      method: "POST",
      headers: {{ "Content-Type": "application/json", "X-Token": TOKEN }},
      body: "{{}}"
    }}).then(function(r){{
      return r.json().then(function(body){{
        if (!r.ok) {{ throw new Error(body.error || "could not start"); }}
        return body;
      }});
    }}).then(function(){{
      if (!polling) {{ polling = setInterval(poll, 3000); }}
      poll();
    }}, function(err){{
      say(err.message, "err");
      resyncBtn.disabled = false;
    }});
  }});

  // If a resync was already running when this page loaded, rejoin it.
  fetch("/api/resync/status").then(function(r){{ return r.json(); }}).then(function(st){{
    if (st.running && !polling) {{ polling = setInterval(poll, 3000); poll(); }}
  }}, function(){{}});

  // ---- per-task chat -----------------------------------------------------
  // Session lives only while the dialog is open. Closing deletes the transcript
  // server-side and drops the DOM log, so nothing about the conversation stays.

  var box = document.getElementById("chatbox");
  var log = document.getElementById("c-log");
  var input = document.getElementById("c-input");
  var sendBtn = document.getElementById("c-send");
  var chat = {{ task: null, session: null, first: true, busy: false, changed: false }};

  function uuid(){{
    if (window.crypto && crypto.randomUUID) {{ return crypto.randomUUID(); }}
    return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, function(c){{
      var r = crypto.getRandomValues(new Uint8Array(1))[0] % 16;
      var v = c === "x" ? r : ((r & 0x3) | 0x8);
      return v.toString(16);
    }});
  }}

  function turn(role, text, extra){{
    var d = document.createElement("div");
    d.className = "turn " + role + (extra ? " " + extra : "");
    var l = document.createElement("div");
    l.className = "lbl";
    l.textContent = role === "me" ? "you" : (extra === "err" ? "failed" : "claude");
    var t = document.createElement("div");
    t.className = "txt";
    t.textContent = text;
    d.appendChild(l); d.appendChild(t); log.appendChild(d);
    log.scrollTop = log.scrollHeight;
    return t;
  }}

  function openChat(id){{
    var row = document.querySelector('[data-row="' + id + '"]');
    chat = {{ task: id, session: uuid(), first: true, busy: false, changed: false }};
    log.textContent = "";
    input.value = "";
    document.getElementById("c-id").textContent = id;
    var txt = row ? row.querySelector(".txt") : null;
    document.getElementById("c-sum").textContent =
      txt ? (txt.childNodes[0] ? txt.childNodes[0].textContent.trim() : id) : id;
    var notes = [];
    if (row) {{
      Array.prototype.slice.call(row.querySelectorAll("small")).forEach(function(s){{
        notes.push(s.textContent.trim());
      }});
    }}
    document.getElementById("c-ctx").textContent = notes.join("\\n") || "(no notes on this item)";
    box.showModal();
    input.focus();
  }}

  function closeChat(){{
    var session = chat.session;
    var changed = chat.changed;
    chat = {{ task: null, session: null, first: true, busy: false, changed: false }};
    log.textContent = "";
    input.value = "";
    if (session) {{
      // Fire and forget: the transcript goes away whether or not we hear back.
      fetch("/api/chat/end", {{
        method: "POST",
        headers: {{ "Content-Type": "application/json", "X-Token": TOKEN }},
        body: JSON.stringify({{ session: session }}),
        keepalive: true
      }}).catch(function(){{}});
    }}
    if (box.open) {{ box.close(); }}
    if (changed) {{ location.reload(); }}
  }}

  document.addEventListener("click", function(e){{
    var b = e.target.closest("button.chat");
    if (b) {{ e.preventDefault(); openChat(b.dataset.id); }}
  }});

  document.getElementById("c-close").addEventListener("click", function(e){{
    e.preventDefault(); closeChat();
  }});
  // Esc fires dialog's cancel; route it through the same teardown.
  box.addEventListener("cancel", function(e){{ e.preventDefault(); closeChat(); }});

  document.getElementById("c-form").addEventListener("submit", function(e){{
    e.preventDefault();
    var text = input.value.trim();
    if (!text || chat.busy || !chat.task) {{ return; }}
    turn("me", text);
    input.value = "";
    chat.busy = true;
    sendBtn.disabled = true;
    var pending = turn("claude", "thinking");
    pending.className = "txt dots";

    fetch("/api/chat", {{
      method: "POST",
      headers: {{ "Content-Type": "application/json", "X-Token": TOKEN }},
      body: JSON.stringify({{
        task: chat.task, session: chat.session, message: text, first: chat.first
      }})
    }}).then(function(r){{
      return r.json().then(function(body){{
        if (!r.ok) {{ throw new Error(body.error || "request failed"); }}
        return body;
      }});
    }}).then(function(body){{
      chat.first = false;
      pending.className = "txt";
      pending.textContent = body.reply || "(no reply)";
      if (body.changed) {{
        chat.changed = true;
        var d = pending.parentNode;
        d.className = "turn claude wrote";
        d.querySelector(".lbl").textContent = "claude · edited TODO.md";
      }}
    }}, function(err){{
      pending.className = "txt";
      pending.parentNode.className = "turn claude err";
      pending.parentNode.querySelector(".lbl").textContent = "failed";
      pending.textContent = err.message;
    }}).then(function(){{
      chat.busy = false;
      sendBtn.disabled = false;
      input.focus();
      log.scrollTop = log.scrollHeight;
    }});
  }});

  refresh();
}})();
</script>
</body></html>
"""


if __name__ == "__main__":
    main()
