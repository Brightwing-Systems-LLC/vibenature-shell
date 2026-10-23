#!/usr/bin/env python3
"""Connect coding agents to VibeNature, or disconnect them (`just hook-install` / `just hook-uninstall`).

Harnesses (research: a private design note):
  claude   Claude Code: hook entries in ~/.claude/settings.json
  codex    Codex CLI:   hook entries in $CODEX_HOME/hooks.json (default ~/.codex/hooks.json)

install:   finds which harnesses are installed (or takes --harness), moves an old ~/.skypatch to
           ~/.vibenature (data_home.py), copies game/tools/vibenature-hook to
           ~/.vibenature/bin/vibenature-hook and adds one hook entry per event (contract §2's source
           mappings) to each harness's file. Old skypatch-hook entries (before the rename, issue 211)
           and VibeNature entries that no longer match are replaced, not doubled.
uninstall: removes exactly VibeNature's entries (any hook whose command runs vibenature-hook or the
           old skypatch-hook) from every harness file that exists. A file install made (or found empty)
           and that is empty again is deleted, so uninstall leaves things as they were (issue 281).
status:    prints, per harness, whether it is installed and connected.

Each file is backed up first (<name>.vibenature-backup-<time>), merged, never replaced: every other
key and every other hook stays as it was. Running install twice changes nothing the second time. A
file that is not valid JSON is left untouched. --dry-run says what would change and writes nothing.

Output (issue 281): a headline, one aligned row per harness (✓ done or fine, – skipped, ! left
untouched, → would change), then "Next" with only what the person still has to do. --verbose names
the hook events. Colour only on a terminal without NO_COLOR.

Codex runs a hook only after it is trusted. Codex's entries are named "VibeNature" (`statusMessage`,
which /hooks shows as the name) and the file gets a description. Install then asks Codex itself to
trust exactly VibeNature's hooks, the calls its own /hooks screen makes (`codex app-server`:
hooks/list for each hook's key and current hash, then config/batchWrite of hooks.state.<key>.trusted_hash),
so Codex computes the hashes; uninstall removes those entries the same way. Running the installer is
the consent; --no-trust leaves it to /hooks. If `codex` is missing or does not answer, Next says to
trust them in /hooks. Nothing else in config.toml is touched.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import textwrap
import time
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

MARKER = "vibenature-hook"
OLD_MARKERS = ("skypatch-hook",)
TIMEOUT_SEC = 2
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import data_home  # noqa: E402

# Harness event -> the hook's argument list. The hook maps the event to a contract §2 kind.
CLAUDE_EVENTS = ["SessionStart", "UserPromptSubmit", "Stop", "StopFailure", "PostToolUse", "PostToolUseFailure", "Notification", "SessionEnd"]
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "Stop", "Interrupt", "PermissionRequest", "SessionEnd"]
EVENTS = CLAUDE_EVENTS  # the name older callers used
# Codex's /hooks shows a hook's statusMessage as its name ("Unnamed hook" without one, issue 281); it also
# shows it in the status line for the moment the hook runs (under 0.2 s), so it stays this short.
CODEX_HOOK_NAME = "VibeNature"
CODEX_DESCRIPTION = "VibeNature: tells the pond when an agent starts or stops working, never what it works on."
TRUST_TIMEOUT_SEC = 15
NO_CODEX = "codex is not on PATH"

# Tests replace this so detection never depends on the machine running them.
which = shutil.which


@dataclass
class Harness:
    key: str
    name: str
    config: Path
    events: list
    prefix: list  # arguments before the event name
    home_dir: Path  # its folder; existing means installed
    binary: str

    def installed(self) -> bool:
        return self.home_dir.is_dir() or which(self.binary) is not None


def harnesses(home: Path, settings: Path | None = None, codex_dir: Path | None = None, use_env: bool = True) -> dict:
    if codex_dir is None:
        env = os.environ.get("CODEX_HOME", "") if use_env else ""
        codex_dir = Path(env).expanduser() if env else home / ".codex"
    claude_dir = home / ".claude"
    return {
        "claude": Harness("claude", "Claude Code", settings or claude_dir / "settings.json", CLAUDE_EVENTS, [], claude_dir, "claude"),
        "codex": Harness("codex", "Codex", codex_dir / "hooks.json", CODEX_EVENTS, ["codex"], codex_dir, "codex"),
    }


def quote(arg: str) -> str:
    if arg and not any(c in arg for c in " '\"\\$`;&|<>()*?![]{}#~\t\n"):
        return arg
    return "'" + arg.replace("'", "'\\''") + "'"


def command_for(hook: Path, event: str, prefix: list | None = None) -> str:
    return " ".join(quote(a) for a in [str(hook), *(prefix or []), event])


def is_ours(entry) -> bool:
    return isinstance(entry, dict) and MARKER in str(entry.get("command", ""))


def is_old(entry) -> bool:
    return isinstance(entry, dict) and any(m in str(entry.get("command", "")) for m in OLD_MARKERS)


def _remove(config: dict, match) -> list:
    """Removes every hook entry `match(event, entry)` picks. Returns [(event, command)] removed."""
    hooks = config.get("hooks")
    if not isinstance(hooks, dict):
        return []
    removed = []
    for event in list(hooks.keys()):
        groups = hooks[event]
        if not isinstance(groups, list):
            continue
        kept_groups = []
        for group in groups:
            if isinstance(group, dict) and isinstance(group.get("hooks"), list):
                kept = []
                for h in group["hooks"]:
                    if match(event, h):
                        removed.append((event, str(h.get("command", ""))))
                    else:
                        kept.append(h)
                if len(kept) != len(group["hooks"]):
                    if not kept:
                        continue
                    group = dict(group, hooks=kept)
            kept_groups.append(group)
        if kept_groups:
            hooks[event] = kept_groups
        else:
            del hooks[event]
    if not hooks:
        del config["hooks"]
    return removed


def install(config: dict, hook: Path, events: list | None = None, prefix: list | None = None) -> tuple:
    """Merges VibeNature's entries into a harness's hooks file (already parsed). Returns (added, removed),
    each a list of (event, command)."""
    events = CLAUDE_EVENTS if events is None else events
    if not isinstance(config.get("hooks", {}), dict):
        raise ValueError('"hooks" is not an object')
    for event in events:
        if not isinstance(config.get("hooks", {}).get(event, []), list):
            raise ValueError(f'"hooks.{event}" is not a list')
    wanted = {event: command_for(hook, event, prefix) for event in events}
    removed = _remove(config, lambda event, h: is_old(h) or (is_ours(h) and h.get("command") != wanted.get(event)))
    hooks = config.setdefault("hooks", {})
    added = []
    for event in events:
        groups = hooks.setdefault(event, [])
        present = any(is_ours(h) for g in groups if isinstance(g, dict) for h in g.get("hooks", []) or [])
        if not present:
            groups.append({"hooks": [{"type": "command", "command": wanted[event], "timeout": TIMEOUT_SEC}]})
            added.append((event, wanted[event]))
    # A command removed and put back unchanged is no change at all.
    for item in list(added):
        if item in removed:
            added.remove(item)
            removed.remove(item)
    return added, removed


def uninstall(config: dict) -> list:
    """Removes every VibeNature entry, old or new. Returns [(event, command)] removed."""
    return _remove(config, lambda event, h: is_ours(h) or is_old(h))


def wired(config: dict) -> list:
    hooks = config.get("hooks")
    if not isinstance(hooks, dict):
        return []
    return [event for event, groups in hooks.items() if isinstance(groups, list) and any(
        is_ours(h) for g in groups if isinstance(g, dict) for h in (g.get("hooks") or []))]


def codex_toml_defines_hooks(codex_dir: Path) -> bool:
    """Codex warns when one layer defines hooks in both hooks.json and config.toml; `hooks.state`
    (its trust records) is not a definition."""
    path = codex_dir / "config.toml"
    if not path.is_file():
        return False
    text = path.read_text(errors="replace")
    try:
        table = tomllib.loads(text).get("hooks")
        return isinstance(table, dict) and any(k != "state" for k in table)
    except tomllib.TOMLDecodeError:
        return re.search(r"^\s*\[\[?\s*hooks\.(?!state\b)", text, re.M) is not None


def read_config(path: Path) -> tuple:
    """(path to write, original text or None, parsed dict). Raises ValueError (in a few plain words) for a
    file that cannot be read or is not a JSON object."""
    # A symlinked file (dotfiles) is edited where it lives, and stays a symlink.
    real = path.resolve() if path.is_symlink() else path
    if not real.exists():
        return real, None, {}
    try:
        original = real.read_text()
    except (OSError, UnicodeDecodeError) as e:
        raise ValueError(f"not readable ({getattr(e, 'strerror', None) or e})")
    try:
        config = json.loads(original) if original.strip() else {}
    except json.JSONDecodeError as e:
        raise ValueError(f"not valid JSON at line {e.lineno}, column {e.colno}")
    if not isinstance(config, dict):
        raise ValueError("not a JSON object")
    return real, original, config


def write_atomic(path: Path, text: str) -> None:
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def name_codex_hooks(config: dict) -> int:
    """Names VibeNature's Codex entries and describes the file (what /hooks shows). Returns how many
    entries it named; a description is added only to a file without one."""
    named = 0
    for groups in (config.get("hooks") or {}).values():
        for g in groups if isinstance(groups, list) else []:
            for h in (g.get("hooks") or []) if isinstance(g, dict) else []:
                if is_ours(h) and h.get("statusMessage") != CODEX_HOOK_NAME:
                    h["statusMessage"] = CODEX_HOOK_NAME
                    named += 1
    if any(is_ours(h) for gs in (config.get("hooks") or {}).values() for g in gs or [] if isinstance(g, dict)
           for h in g.get("hooks") or []) and "description" not in config:
        config["description"] = CODEX_DESCRIPTION
    return named


def _codex_rpc(codex_dir: Path, calls):
    """Talks to `codex app-server` (JSON-RPC over stdio) the way Codex's own /hooks screen does. `calls`
    is a generator that yields (method, params) and receives each result. Returns (value, error)."""
    binary = which("codex")
    if not binary:
        return None, NO_CODEX
    try:
        proc = subprocess.Popen([binary, "app-server"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.DEVNULL, text=True, bufsize=1,
                                env=dict(os.environ, CODEX_HOME=str(codex_dir)))
    except OSError as e:
        return None, f"codex could not start ({e})"
    deadline = time.monotonic() + TRUST_TIMEOUT_SEC
    sel = selectors.DefaultSelector()
    sel.register(proc.stdout, selectors.EVENT_READ)
    next_id = 0

    def request(method, params):
        nonlocal next_id
        next_id += 1
        proc.stdin.write(json.dumps({"id": next_id, "method": method, "params": params}) + "\n")
        proc.stdin.flush()
        while True:
            left = deadline - time.monotonic()
            if left <= 0 or not sel.select(left):
                raise TimeoutError("codex did not answer")
            line = proc.stdout.readline()
            if not line:
                raise ConnectionError("codex stopped")
            msg = json.loads(line)
            if msg.get("id") == next_id:
                if "error" in msg:
                    raise RuntimeError(str(msg["error"].get("message", msg["error"])))
                return msg.get("result") or {}

    try:
        request("initialize", {"clientInfo": {"name": "vibenature-installer", "version": "1"}})
        proc.stdin.write(json.dumps({"method": "initialized"}) + "\n")
        proc.stdin.flush()
        value = None
        try:
            step = calls.send(None)
            while True:
                step = calls.send(request(*step))
        except StopIteration as done:
            value = done.value
        return value, ""
    except (OSError, ValueError, TimeoutError, ConnectionError, RuntimeError) as e:
        return None, str(e) or type(e).__name__
    finally:
        sel.close()
        proc.kill()
        proc.wait()


def _our_codex_hooks(listed: dict, hooks_file: Path) -> list:
    return [h for entry in listed.get("data", []) for h in entry.get("hooks", [])
            if MARKER in str(h.get("command", "")) and Path(str(h.get("sourcePath", ""))) == hooks_file]


def trust_codex(codex_dir: Path, hooks_file: Path, home: Path) -> tuple:
    """Asks Codex to trust VibeNature's hooks in hooks_file. Returns (trusted, newly, error)."""
    def calls():
        listed = yield ("hooks/list", {"cwds": [str(home)]})
        ours = _our_codex_hooks(listed, hooks_file)
        todo = {h["key"]: {"trusted_hash": h["currentHash"]} for h in ours if h.get("trustStatus") != "trusted"}
        if todo:
            yield ("config/batchWrite", {"edits": [{"keyPath": "hooks.state", "value": todo, "mergeStrategy": "upsert"}],
                                         "filePath": None, "expectedVersion": None, "reloadUserConfig": True})
        return len(ours), len(todo)

    value, error = codex_rpc(codex_dir, calls())
    return (value[0], value[1], "") if value else (0, 0, error or "no VibeNature hooks found")


def untrust_codex(codex_dir: Path, hooks_file: Path, home: Path) -> tuple:
    """Removes Codex's trust entries for VibeNature's hooks (while they are still in the file). Returns (removed, error)."""
    def calls():
        listed = yield ("hooks/list", {"cwds": [str(home)]})
        keys = [h["key"] for h in _our_codex_hooks(listed, hooks_file) if h.get("trustStatus") in ("trusted", "modified")]
        if keys:
            yield ("config/batchWrite", {"edits": [{"keyPath": "hooks.state." + json.dumps(k), "value": None,
                                                    "mergeStrategy": "replace"} for k in keys],
                                         "filePath": None, "expectedVersion": None, "reloadUserConfig": True})
        return len(keys)

    value, error = codex_rpc(codex_dir, calls())
    return (value or 0, error)


# Tests replace this so no test ever starts the real Codex.
codex_rpc = _codex_rpc


def stamp() -> str:
    """The backup's time; tests pin it."""
    return time.strftime("%Y%m%d-%H%M%S")


def backup(path: Path, original: str) -> Path:
    stem = f"{path.name}.vibenature-backup-{stamp()}"
    target, n = path.with_name(stem), 1
    while target.exists():
        n += 1
        target = path.with_name(f"{stem}-{n}")
    target.write_text(original)
    os.chmod(target, path.stat().st_mode & 0o777)
    return target


# What a person must still do, and what the hook hears. The game's welcome and Config's Connections tab
# say these same words (they arrive in the --json report as "next" and "privacy").
PRIVACY = "VibeNature hears only when an agent starts or stops working, never what it works on."
NEXT = {
    "codex": "open codex, type /hooks and trust VibeNature's {n} hooks. Until then Codex runs none of them.",
    "claude": "restart sessions already open; new ones are connected.",
}
FIX = {
    "toml": "move the hooks defined in {toml} into {hooks}, then run this again. Codex warns when both define hooks.",
    "file": "correct {path}, then run this again. Nothing in it was changed.",
    "none": "install Claude Code or Codex, then run this again.",
    "status": "run `just hook-install` to connect.",
}
# Files VibeNature made (or found empty), so uninstall can take them away again instead of leaving `{}`.
MADE_FILE = "hook-files.json"


@dataclass
class Outcome:
    """What happened (or would happen) to one harness."""
    harness: Harness
    path: Path
    state: str  # changed | same | skipped | refused
    added: list = field(default_factory=list)
    removed: list = field(default_factory=list)
    create: bool = False
    delete: bool = False
    backup: Path | None = None
    why: str = ""
    fix: str = ""
    named: int = 0  # Codex entries given their name
    trusted: int = 0  # Codex hooks trusted after this run
    newly_trusted: int = 0
    untrusted: int = 0
    trust_error: str = ""


def use_color(stream) -> bool:
    """Colour only on a terminal, and never with NO_COLOR (https://no-color.org) or TERM=dumb."""
    isatty = getattr(stream, "isatty", None)
    return bool(isatty and isatty()) and "NO_COLOR" not in os.environ and os.environ.get("TERM") != "dumb"


class Style:
    def __init__(self, on: bool):
        self.on = on

    def _wrap(self, code: str, text: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.on and text else text

    def bold(self, t): return self._wrap("1", t)
    def dim(self, t): return self._wrap("2", t)
    def green(self, t): return self._wrap("32", t)
    def yellow(self, t): return self._wrap("33", t)
    def red(self, t): return self._wrap("31", t)
    def cyan(self, t): return self._wrap("36", t)


MARKS = {"ok": ("✓", "green"), "off": ("–", "dim"), "warn": ("!", "yellow"), "bad": ("!", "red"), "would": ("→", "cyan")}


def tilde(path, home: Path) -> str:
    text, base = str(path), str(home).rstrip("/")
    if base and (text == base or text.startswith(base + "/")):
        return "~" + text[len(base):]
    return text


def hooks(n: int) -> str:
    return f"{n} hook" if n == 1 else f"{n} hooks"


def names(items) -> str:
    items = list(items)
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def said(o: Outcome, action: str, dry: bool) -> str:
    """What happened to one harness, in a few words."""
    if o.state == "skipped":
        return "not installed: skipped"
    if o.state == "refused":
        return f"left untouched: {o.why}"
    trusted = o.harness.key == "codex" and not dry and o.trusted and o.trusted == len(o.harness.events)
    if o.state == "same":
        if action != "install":
            return "not connected"
        return "already connected" + (", now trusted" if trusted and o.newly_trusted else "")
    a, r = len(o.added), len(o.removed)
    if action == "uninstall":
        if dry:
            return f"would remove {hooks(r)}" + (" and delete the file" if o.delete else "")
        return (f"{hooks(r)} removed" + (", trust removed" if o.untrusted else "")
                + (", file deleted (VibeNature made it)" if o.delete else ""))
    if not a and not r and o.named:
        return (f"would name its {hooks(o.named)}" if dry else f"{hooks(o.named)} named") + (", trusted" if trusted else "")
    if dry:
        if o.create:
            return f"would create it with {hooks(a)}"
        if a and r:
            return f"would update {hooks(a)}" if a == r else f"would add {hooks(a)} and remove {r} old"
        return f"would add {hooks(a)}" if a else f"would remove {r} old"
    if a and r:
        text = f"{hooks(a)} updated" if a == r else f"{hooks(a)} added, {r} old removed"
    else:
        text = f"{hooks(a)} added" if a else f"{r} old removed"
    return text + (", new file" if o.create else "") + (", trusted" if trusted else "")


def next_steps(outcomes: list, action: str) -> list:
    """[(key, name, text)]: only what the person must still do, fixes first."""
    out = [(o.harness.key, o.harness.name, o.fix) for o in outcomes if o.state == "refused"]
    if action == "install":
        for key in ("codex", "claude"):
            for o in outcomes:
                if o.harness.key != key or o.state not in ("changed", "same"):
                    continue
                if key == "codex":
                    # Only when Codex was not asked, or did not answer: then /hooks is the way.
                    if o.trusted < len(o.harness.events) and (o.state == "changed" or (o.trust_error and o.trust_error != NO_CODEX)):
                        out.append((key, o.harness.name, NEXT[key].format(n=len(o.harness.events))))
                elif o.state == "changed" and o.added:
                    out.append((key, o.harness.name, NEXT[key].format(n=len(o.harness.events))))
        if not any(o.state != "skipped" for o in outcomes):
            out.append(("", "", FIX["none"]))
    return out


def headline(outcomes: list, action: str, dry: bool) -> str:
    ok = [o for o in outcomes if o.state in ("changed", "same")]
    changed = [o for o in ok if o.state == "changed"]
    refused = [o.harness.name for o in outcomes if o.state == "refused"]
    if dry:
        return "Dry run: nothing was written."
    if not any(o.state != "skipped" for o in outcomes):
        return "No coding agent found here."
    if action == "install":
        if changed:
            text = f"Connected VibeNature to {names(o.harness.name for o in ok)}."
        elif ok:
            text = "VibeNature is already connected. Nothing changed."
        else:
            text = "VibeNature could not connect."
    else:
        if changed:
            text = f"Disconnected VibeNature from {names(o.harness.name for o in changed)}."
        elif ok:
            text = "VibeNature was not connected. Nothing changed."
        else:
            text = "VibeNature could not disconnect."
    if refused and (changed or ok):
        text += f" {names(refused)} was left untouched."
    return text


def render(action: str, dry: bool, outcomes: list, home: Path, *, color: bool = False, verbose: bool = False,
           extra_rows: list | None = None, hook: Path | None = None) -> str:
    """The whole report for a person: a headline, one aligned row per harness, then Next."""
    s = Style(color)
    rows = list(extra_rows or [])  # (mark, name, path, what, [sub-lines])
    for o in outcomes:
        subs = []
        if o.backup is not None:
            subs.append(s.dim("backup ") + tilde(o.backup, home))
        elif dry and o.state == "changed" and not o.create and not o.delete:
            subs.append(s.dim("a backup is made first"))
        if verbose:
            for label, events in (("adds", o.added), ("removes", o.removed)):
                if events:
                    subs.append(s.dim(f"{label} ") + ", ".join(e for e, _ in events))
        if o.state == "same" and action == "uninstall":
            mark = "off"
        elif o.state == "same":
            mark = "ok"
        elif o.state == "skipped":
            mark = "off"
        elif o.state == "refused":
            mark = "bad"
        else:
            mark = "would" if dry else "ok"
        rows.append((mark, o.harness.name, "" if o.state == "skipped" else tilde(o.path, home), said(o, action, dry), subs))
    if verbose and hook is not None and action == "install" and any(o.state == "changed" for o in outcomes):
        rows.append(("would" if dry else "ok", "Hook", tilde(hook, home), "would be copied" if dry else "copied", []))

    name_w = max((len(r[1]) for r in rows), default=0)
    path_w = max((len(r[2]) for r in rows if r[2]), default=0)
    lines = [s.bold(headline(outcomes, action, dry)), ""]
    for mark, name, path, what, subs in rows:
        glyph, paint = MARKS[mark]
        if path:
            line = f"  {getattr(s, paint)(glyph)} {s.bold(name)}{' ' * (name_w - len(name))}  {path.ljust(path_w)}  {what}"
        else:
            line = f"  {getattr(s, paint)(glyph)} {s.bold(name)}{' ' * (name_w - len(name))}  {what}"
        lines.append(line.rstrip())
        for sub in subs:
            lines.append(" " * (4 + name_w + 2) + sub)

    changed = any(o.state == "changed" for o in outcomes)
    steps = [] if dry else next_steps(outcomes, action)
    if steps:
        lines += ["", s.bold("Next")]
        for _, name, text in steps:
            body = f"{name}: {text}" if name else text[0].upper() + text[1:]
            wrapped = textwrap.wrap(body, width=76, initial_indent="  • ", subsequent_indent="    ")
            lines += wrapped
    if dry and changed:
        lines += ["", "Run it without --dry-run to make these changes."]
    if action == "install" and changed:
        lines += ["", s.dim(PRIVACY)]
    if action == "uninstall" and changed and not dry and hook is not None:
        lines += ["", s.dim(f"The hook stays at {tilde(hook, home)}; delete it if you like.")]
    return "\n".join(lines) + "\n"


def render_status(report: dict, home: Path, *, color: bool = False) -> str:
    s = Style(color)
    rows = []
    for r in report.values():
        if r["error"]:
            rows.append(("bad", r["name"], tilde(r["config"], home), f"could not check: {r['error']}"))
        elif r["complete"]:
            rows.append(("ok", r["name"], tilde(r["config"], home), "connected"))
        elif r["wired"]:
            rows.append(("warn", r["name"], tilde(r["config"], home), f"partly connected ({len(r['wired'])} of {r['events']} hooks)"))
        elif r["installed"]:
            rows.append(("off", r["name"], tilde(r["config"], home), "not connected"))
        else:
            rows.append(("off", r["name"], "", "not installed"))
    name_w = max(len(r[1]) for r in rows)
    path_w = max((len(r[2]) for r in rows if r[2]), default=0)
    lines = [s.bold("VibeNature's connections"), ""]
    for mark, name, path, what in rows:
        glyph, paint = MARKS[mark]
        cell = f"{path.ljust(path_w)}  {what}" if path else what
        lines.append(f"  {getattr(s, paint)(glyph)} {s.bold(name)}{' ' * (name_w - len(name))}  {cell}".rstrip())
    if any(r["installed"] and not r["complete"] and not r["error"] for r in report.values()):
        lines += ["", s.bold("Next"), f"  • {FIX['status'][0].upper()}{FIX['status'][1:]}"]
    return "\n".join(lines) + "\n"


def _made_files(data_dir: Path) -> list:
    try:
        made = json.loads((data_dir / MADE_FILE).read_text()).get("made", [])
        return [str(p) for p in made] if isinstance(made, list) else []
    except (OSError, ValueError, AttributeError):
        return []


def _save_made_files(data_dir: Path, made: list) -> None:
    path = data_dir / MADE_FILE
    if made:
        write_atomic(path, json.dumps({"made": sorted(set(made))}, indent=2) + "\n")
    elif path.exists():
        path.unlink()


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("action", choices=["install", "uninstall", "status"])
    p.add_argument("--harness", action="append", choices=["claude", "codex"],
                   help="only this harness (repeatable); default: every one installed (uninstall: every one)")
    p.add_argument("--home", type=Path, default=None, help="default: your home folder")
    p.add_argument("--settings", type=Path, default=None, help="Claude Code's settings (default ~/.claude/settings.json)")
    p.add_argument("--codex-dir", type=Path, default=None, help="Codex's folder (default $CODEX_HOME or ~/.codex)")
    p.add_argument("--hook-dir", type=Path, default=None, help="default: ~/.vibenature/bin")
    p.add_argument("--dry-run", action="store_true", help="say what would change; write nothing")
    p.add_argument("--verbose", "-v", action="store_true", help="also name each hook event, and the hook's path")
    p.add_argument("--no-trust", dest="trust", action="store_false",
                   help="don't ask Codex to trust the hooks; trust them yourself in codex's /hooks")
    p.add_argument("--json", action="store_true", help="print JSON (status; install and uninstall: what was or would be done)")
    args = p.parse_args(argv)
    return _run(args)


def _run(args) -> int:
    home = args.home or Path.home()
    every = harnesses(home, args.settings, args.codex_dir, use_env=args.home is None)
    data_dir = data_home.resolve() if args.home is None else data_home.resolve(home)
    extra_rows = []
    if args.hook_dir is None:
        if args.action == "install" and not args.dry_run and args.home is None:
            # Says nothing unless it moved something: there is nothing to do about a folder already in place.
            if data_home.migrate().startswith("moved"):
                data_dir = data_home.resolve()
                extra_rows.append(("ok", "Data folder", tilde(data_dir, home), f"moved from ~/{data_home.OLD}", []))
        args.hook_dir = data_dir / "bin"
    hook = args.hook_dir / MARKER
    color = use_color(sys.stdout) and not args.json

    if args.action == "status":
        report = {}
        for h in every.values():
            try:
                events = wired(read_config(h.config)[2])
                error = ""
            except ValueError as e:
                events, error = [], str(e)
            report[h.key] = {"name": h.name, "installed": h.installed(), "config": str(h.config), "wired": events,
                             "events": len(h.events), "complete": set(h.events) <= set(events), "error": error}
        print(json.dumps(report, indent=2) if args.json else render_status(report, home, color=color), end="" if not args.json else "\n")
        return 0

    if args.harness:
        chosen = [every[k] for k in dict.fromkeys(args.harness)]
    elif args.action == "install":
        chosen = [h for h in every.values() if h.installed()]
    else:
        chosen = list(every.values())

    outcomes, pending, status = [], [], 0
    made = _made_files(data_dir)
    for h in every.values():
        if h not in chosen:
            if not args.harness:
                outcomes.append(Outcome(h, h.config, "skipped"))
            continue
        toml = h.config.parent / "config.toml"
        if args.action == "install" and h.key == "codex" and codex_toml_defines_hooks(h.config.parent):
            outcomes.append(Outcome(h, h.config, "refused", why="config.toml already defines hooks",
                                    fix=FIX["toml"].format(toml=tilde(toml, home), hooks=tilde(h.config, home))))
            status = 1
            continue
        try:
            path, original, config = read_config(h.config)
            was_empty = not config
            named = 0
            if args.action == "install":
                added, removed = install(config, hook, h.events, h.prefix)
                if h.key == "codex":
                    named = name_codex_hooks(config)
            else:
                added, removed = [], uninstall(config)
                if h.key == "codex" and config.get("description") == CODEX_DESCRIPTION:
                    del config["description"]
        except ValueError as e:
            outcomes.append(Outcome(h, h.config, "refused", why=str(e),
                                    fix=FIX["file"].format(path=tilde(h.config, home), why=str(e))))
            status = 1
            continue
        changed = bool(added or removed or named)
        o = Outcome(h, path, "changed" if changed else "same", added, removed, create=changed and original is None,
                    delete=args.action == "uninstall" and changed and not config and str(path) in made, named=named)
        outcomes.append(o)
        pending.append((o, original, config, was_empty))

    # A hook copied by an older install is brought up to date even when every entry is already in place
    # (issue 308: PostToolUse became its own kind, and only the copied script changed).
    stale = args.action == "install" and hook.is_file() and hook.read_bytes() != (HERE / MARKER).read_bytes()
    if stale:
        extra_rows.append(("ok", "Hook", tilde(hook, home), "would be updated" if args.dry_run else "updated", []))
    if not args.dry_run:
        wrote = [o for o, *_ in pending if o.state == "changed"]
        if args.action == "install" and (wrote or stale):
            hook.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(HERE / MARKER, hook)
            os.chmod(hook, 0o755)
        codex_home = every["codex"].home_dir
        if args.action == "uninstall" and args.trust:
            for o, *_ in pending:
                if o.harness.key == "codex" and o.state == "changed":
                    o.untrusted, o.trust_error = untrust_codex(codex_home, o.path, home)
        for o, original, config, was_empty in pending:
            if o.state != "changed":
                continue
            if o.delete:
                o.path.unlink()
                made.remove(str(o.path))
                continue
            if original is not None:
                o.backup = backup(o.path, original)
            write_atomic(o.path, json.dumps(config, indent=2) + "\n")
            if args.action == "install" and was_empty and str(o.path) not in made:
                made.append(str(o.path))
            elif args.action == "uninstall" and str(o.path) in made:
                made.remove(str(o.path))
        if wrote:
            _save_made_files(data_dir, made)
        if args.action == "install" and args.trust:
            for o, *_ in pending:
                if o.harness.key == "codex":
                    o.trusted, o.newly_trusted, o.trust_error = trust_codex(codex_home, o.path, home)

    text = render(args.action, args.dry_run, outcomes, home, color=color, verbose=args.verbose,
                  extra_rows=extra_rows, hook=hook)
    if not args.json:
        print(text, end="")
        return status
    # The game's welcome and Config's Connections tab (issue 199) read this and say it in their own layout.
    report = {
        "action": args.action, "dry_run": args.dry_run, "status": status, "hook": str(hook),
        "headline": headline(outcomes, args.action, args.dry_run),
        "harnesses": [{"key": o.harness.key, "name": o.harness.name, "path": str(o.path), "state": o.state,
                       "create": o.create, "delete": o.delete, "backup": str(o.backup) if o.backup else "",
                       "added": [e for e, _ in o.added], "removed": [e for e, _ in o.removed], "said": said(o, args.action, args.dry_run),
                       "trusted": o.trusted, "trust_error": o.trust_error}
                      for o in outcomes if o.state in ("changed", "same")],
        "skipped": [{"key": o.harness.key, "name": o.harness.name} for o in outcomes if o.state == "skipped"],
        "refused": [{"key": o.harness.key, "name": o.harness.name, "why": o.why, "fix": o.fix} for o in outcomes if o.state == "refused"],
        # For a dry run: what will be left to do once it is done for real, so it can be said up front.
        "next": [{"key": k, "name": n, "text": t} for k, n, t in next_steps(outcomes, args.action) if k],
        "privacy": PRIVACY,
        "log": text,
    }
    print(json.dumps(report, indent=2))
    return status


if __name__ == "__main__":
    sys.exit(main())
