#!/usr/bin/env python3
"""Tests for the agent hook (Claude Code and Codex adapters) and its installer (contract §2). Stdlib only; `just test` runs it.

Never touches the real ~/.claude/settings.json, ~/.codex, ~/.skypatch or ~/.vibenature: every run gets its own temp HOME.
"""

import contextlib
import hashlib
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
import unittest
import unittest.mock
from pathlib import Path

HERE = Path(__file__).resolve().parent
HOOK = HERE / "vibenature-hook"
sys.path.insert(0, str(HERE))
import data_home  # noqa: E402
import hook_install  # noqa: E402

SECRETS = ["SECRET-PROMPT-TEXT", "/Users/someone/clients/acme", "transcript-acme.jsonl", "rm -rf build", "acme-billing"]


def payload(event: str, session_id: str = "5f1d2c3b-aaaa-4bbb-8ccc-0123456789ab") -> str:
    return json.dumps({
        "session_id": session_id,
        "transcript_path": "/Users/someone/.claude/projects/acme/transcript-acme.jsonl",
        "cwd": "/Users/someone/clients/acme",
        "hook_event_name": event,
        "prompt": "SECRET-PROMPT-TEXT: fix acme-billing, then rm -rf build",
        "tool_input": {"command": "rm -rf build", "session_id": "not-this-one"},
        "message": "Claude needs your permission in /Users/someone/clients/acme",
    })


class Catcher:
    """A one-shot HTTP listener on 127.0.0.1 that keeps every raw byte it is sent."""

    def __init__(self, wait: float = 3):
        self.sock = socket.socket()
        self.sock.bind(("127.0.0.1", 0))
        self.sock.listen(4)
        self.sock.settimeout(wait)
        self.port = self.sock.getsockname()[1]
        self.raw = b""
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    def _serve(self):
        try:
            conn, _ = self.sock.accept()
        except OSError:
            return
        conn.settimeout(1)
        try:
            while b"\r\n\r\n" not in self.raw or len(self.raw.split(b"\r\n\r\n", 1)[1]) < self._length():
                chunk = conn.recv(4096)
                if not chunk:
                    break
                self.raw += chunk
            conn.sendall(b"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n")
        except OSError:
            pass
        finally:
            conn.close()

    def _length(self) -> int:
        for line in self.raw.split(b"\r\n\r\n", 1)[0].split(b"\r\n"):
            if line.lower().startswith(b"content-length:"):
                return int(line.split(b":", 1)[1])
        return 0

    def close(self):
        self.thread.join(3)
        self.sock.close()


class HookTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def run_hook(self, event: str, stdin: str, port: int = 9):
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(self.home),
               "VIBENATURE_EVENT_URL": f"http://127.0.0.1:{port}/event"}
        start = time.monotonic()
        result = subprocess.run(["/bin/sh", str(HOOK), event], input=stdin.encode(), capture_output=True, env=env, timeout=5)
        return result, time.monotonic() - start

    def test_sends_only_kind_source_hash_and_time(self):
        catcher = Catcher()
        result, _ = self.run_hook("Stop", payload("Stop"), catcher.port)
        catcher.close()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"", "a hook's stdout reaches Claude; it must print nothing")
        raw = catcher.raw
        self.assertTrue(raw.startswith(b"POST /event HTTP/1.1\r\n"), raw[:40])
        for secret in SECRETS:
            self.assertNotIn(secret.encode(), raw, f"{secret!r} left the hook")
        body = json.loads(raw.split(b"\r\n\r\n", 1)[1])
        self.assertEqual(set(body), {"kind", "source", "session_hash", "ts"})
        self.assertEqual(body["kind"], "turn_end")
        self.assertEqual(body["source"], "claude_code")
        self.assertLessEqual(abs(body["ts"] - time.time()), 5)
        self.assertLessEqual(len(raw.split(b"\r\n\r\n", 1)[1]), 512)
        salt = (self.home / ".vibenature" / "salt").read_bytes()
        self.assertEqual(len(salt), 32)
        self.assertEqual(oct((self.home / ".vibenature" / "salt").stat().st_mode & 0o777), oct(0o600))
        expected = hashlib.sha256(salt + b"5f1d2c3b-aaaa-4bbb-8ccc-0123456789ab").hexdigest()[:16]
        self.assertEqual(body["session_hash"], expected, "the first session_id, salted and hashed")

    def test_maps_every_event_and_keeps_its_salt(self):
        wanted = {"SessionStart": "session_start", "UserPromptSubmit": "turn_start", "Stop": "turn_end",
                  "PostToolUse": "still_busy", "PostToolUseFailure": "tool_fail", "Notification": "needs_input", "SessionEnd": "session_end"}
        hashes = set()
        for event, kind in wanted.items():
            catcher = Catcher()
            self.run_hook(event, payload(event), catcher.port)
            catcher.close()
            body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
            self.assertEqual(body["kind"], kind, event)
            hashes.add(body["session_hash"])
        self.assertEqual(len(hashes), 1, "one session, one hash: the salt is made once")

    def test_sends_nothing_for_other_events_or_without_a_session(self):
        for event, stdin in [("SubagentStop", payload("SubagentStop")), ("PreToolUse", payload("PreToolUse")),
                             ("Stop", '{"prompt": "SECRET-PROMPT-TEXT"}'), ("Stop", "not json at all")]:
            catcher = Catcher(wait=0.5)
            result, _ = self.run_hook(event, stdin, catcher.port)
            catcher.close()
            self.assertEqual(result.returncode, 0)
            self.assertEqual(catcher.raw, b"", f"{event} sent something")

    def test_never_slows_a_turn_when_the_game_is_away(self):
        # A port that accepts and never answers: the hook gives up after 200 ms.
        silent = socket.socket()
        silent.bind(("127.0.0.1", 0))
        silent.listen(1)
        result, took = self.run_hook("Stop", payload("Stop"), silent.getsockname()[1])
        silent.close()
        self.assertEqual(result.returncode, 0)
        self.assertLess(took, 1.0)
        result, took = self.run_hook("Stop", payload("Stop"), 9)
        self.assertEqual(result.returncode, 0)
        self.assertLess(took, 1.0)

    def test_keeps_the_old_salt_until_the_folder_moves(self):
        # Before the move (issue 211) the old ~/.skypatch salt is used, and no ~/.vibenature is
        # made that would stop the move.
        (self.home / ".skypatch").mkdir()
        (self.home / ".skypatch" / "salt").write_bytes(b"o" * 32)
        catcher = Catcher()
        self.run_hook("Stop", payload("Stop"), catcher.port)
        catcher.close()
        body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
        self.assertEqual(body["session_hash"], hashlib.sha256(b"o" * 32 + b"5f1d2c3b-aaaa-4bbb-8ccc-0123456789ab").hexdigest()[:16])
        self.assertFalse((self.home / ".vibenature").exists())

    def test_refuses_a_url_off_this_machine(self):
        env = {"PATH": os.environ["PATH"], "HOME": str(self.home), "VIBENATURE_EVENT_URL": "http://example.com/event"}
        out = subprocess.run(["/bin/sh", "-x", str(HOOK), "Stop"], input=payload("Stop").encode(), capture_output=True, env=env)
        self.assertEqual(out.returncode, 0)
        self.assertNotIn(b"curl", out.stderr)


def codex_payload(event: str, session_id: str = "019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b") -> str:
    """Codex's hook input (https://learn.chatgpt.com/docs/hooks): session_id is the thread id."""
    return json.dumps({
        "session_id": session_id,
        "transcript_path": "/Users/someone/.codex/sessions/2026/10/19/rollout-transcript-acme.jsonl",
        "cwd": "/Users/someone/clients/acme",
        "hook_event_name": event,
        "model": "gpt-5.5-codex",
        "turn_id": "turn-7",
        "prompt": "SECRET-PROMPT-TEXT: fix acme-billing",
        "last_assistant_message": "Done: rm -rf build in /Users/someone/clients/acme",
        "tool_input": {"command": "rm -rf build", "session_id": "not-this-one"},
        "stop_hook_active": False,
    })


class CodexHookTest(unittest.TestCase):
    """The Codex adapter: `vibenature-hook codex <CodexEvent>`, reading hook JSON on stdin."""

    setUp = HookTest.setUp
    tearDown = HookTest.tearDown
    run_hook = HookTest.run_hook

    def run_codex(self, event: str, stdin: str, port: int = 9):
        env = {"PATH": os.environ.get("PATH", "/usr/bin:/bin"), "HOME": str(self.home),
               "VIBENATURE_EVENT_URL": f"http://127.0.0.1:{port}/event"}
        return subprocess.run(["/bin/sh", str(HOOK), "codex", event], input=stdin.encode(), capture_output=True, env=env, timeout=5)

    def test_codex_sends_only_signals_and_drops_content(self):
        for event in ["SessionStart", "UserPromptSubmit", "Stop", "Interrupt", "PermissionRequest", "SessionEnd"]:
            catcher = Catcher()
            result = self.run_codex(event, codex_payload(event), catcher.port)
            catcher.close()
            self.assertEqual(result.returncode, 0)
            self.assertEqual(result.stdout, b"", "Codex reads a Stop hook's stdout as a decision; print nothing")
            self.assertEqual(result.stderr, b"")
            for secret in SECRETS + ["gpt-5.5-codex", "turn-7", "rollout-"]:
                self.assertNotIn(secret.encode(), catcher.raw, f"{secret!r} left the Codex hook on {event}")
            body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
            self.assertEqual(set(body), {"kind", "source", "session_hash", "ts"})
            self.assertEqual(body["source"], "codex")

    def test_codex_maps_its_events(self):
        wanted = {"SessionStart": "session_start", "UserPromptSubmit": "turn_start", "Stop": "turn_end",
                  "Interrupt": "turn_end", "PermissionRequest": "needs_input", "SessionEnd": "session_end"}
        hashes = set()
        for event, kind in wanted.items():
            catcher = Catcher()
            self.run_codex(event, codex_payload(event), catcher.port)
            catcher.close()
            body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
            self.assertEqual(body["kind"], kind, event)
            hashes.add(body["session_hash"])
        self.assertEqual(len(hashes), 1)
        salt = (self.home / ".vibenature" / "salt").read_bytes()
        self.assertEqual(hashes.pop(), hashlib.sha256(salt + b"019a2b3c-4d5e-7f60-8a9b-0c1d2e3f4a5b").hexdigest()[:16])

    def test_codex_sends_nothing_for_other_events(self):
        for event in ["PreToolUse", "PostToolUse", "SubagentStop", "PreCompact", "", "Notification"]:
            catcher = Catcher(wait=0.5)
            result = self.run_codex(event, codex_payload(event), catcher.port)
            catcher.close()
            self.assertEqual(result.returncode, 0)
            self.assertEqual(catcher.raw, b"", f"codex {event!r} sent something")

    def test_claude_post_tool_use_is_a_keep_alive_carrying_only_the_session(self):
        catcher = Catcher()
        stdin = payload("PostToolUse").replace('"hook_event_name"', '"tool_response": {"stdout": "acme-billing SECRET-PROMPT-TEXT"}, "hook_event_name"', 1)
        self.assertIn("acme-billing SECRET", stdin)
        result, _ = self.run_hook("PostToolUse", stdin, catcher.port)
        catcher.close()
        self.assertEqual((result.returncode, result.stdout), (0, b""))
        for secret in SECRETS:
            self.assertNotIn(secret.encode(), catcher.raw, f"{secret!r} left the hook")
        body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
        self.assertEqual(set(body), {"kind", "source", "session_hash", "ts"})
        self.assertEqual((body["kind"], body["source"]), ("still_busy", "claude_code"))

    def test_claude_stop_failure_ends_the_turn(self):
        catcher = Catcher()
        self.run_hook("StopFailure", payload("StopFailure"), catcher.port)
        catcher.close()
        body = json.loads(catcher.raw.split(b"\r\n\r\n", 1)[1])
        self.assertEqual((body["kind"], body["source"]), ("turn_end", "claude_code"))


class InstallerTest(unittest.TestCase):
    """Every run gets a temp HOME, and harness detection never looks at this machine's PATH."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.settings = self.dir / ".claude" / "settings.json"
        self.codex = self.dir / ".codex" / "hooks.json"
        self.hook_dir = self.dir / "bin"
        self.settings.parent.mkdir()
        self.codex.parent.mkdir()
        self._which = hook_install.which
        hook_install.which = lambda name: None

    def tearDown(self):
        hook_install.which = self._which
        self.tmp.cleanup()

    def run_installer(self, *args, harness=("claude",)):
        out = io.StringIO()
        flags = [f"--harness={h}" for h in harness]
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            code = hook_install.main([*args, *flags, "--home", str(self.dir), "--hook-dir", str(self.hook_dir)])
        self.output = out.getvalue()
        return code

    def theirs(self):
        return {
            "model": "opus",
            "permissions": {"allow": ["Bash(ls)"]},
            "hooks": {
                "Stop": [{"hooks": [{"type": "command", "command": "afplay done.aiff"}]}],
                "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "guard.sh"}]}],
            },
        }

    def codex_theirs(self):
        return {"hooks": {
            "Stop": [{"hooks": [{"type": "command", "command": "/usr/local/bin/notify-me", "timeout": 5}]}],
            "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command", "command": "codex-guard"}]}],
        }}

    def ours(self, path: Path, event: str) -> list:
        data = json.loads(path.read_text())
        return [h["command"] for g in data["hooks"].get(event, []) for h in g["hooks"] if "vibenature-hook" in h["command"]]

    def test_install_merges_backs_up_and_is_idempotent(self):
        self.settings.write_text(json.dumps(self.theirs()))
        self.assertEqual(self.run_installer("install"), 0)
        after = json.loads(self.settings.read_text())
        self.assertEqual(after["model"], "opus")
        self.assertEqual(after["permissions"], {"allow": ["Bash(ls)"]})
        self.assertEqual(after["hooks"]["PreToolUse"], self.theirs()["hooks"]["PreToolUse"])
        self.assertEqual(after["hooks"]["Stop"][0], self.theirs()["hooks"]["Stop"][0], "their Stop hook is kept")
        for event in hook_install.CLAUDE_EVENTS:
            ours = self.ours(self.settings, event)
            self.assertEqual(len(ours), 1, event)
            self.assertTrue(ours[0].endswith("/vibenature-hook " + event))
        self.assertNotIn("SubagentStop", after["hooks"])
        backups = list(self.settings.parent.glob("settings.json.vibenature-backup-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(json.loads(backups[0].read_text()), self.theirs())
        self.assertTrue(os.access(self.hook_dir / "vibenature-hook", os.X_OK))
        self.assertEqual(self.run_installer("install"), 0)
        self.assertEqual(json.loads(self.settings.read_text()), after, "a second install changes nothing")
        self.assertEqual(len(list(self.settings.parent.glob("settings.json.vibenature-backup-*"))), 1, "nor backs up again")

    def test_a_rerun_updates_an_old_hook_even_with_every_entry_in_place(self):
        # Issue 308: the entries were already right, but the copied hook still sent PostToolUse as turn_start.
        self.assertEqual(self.run_installer("install"), 0)
        hook = self.hook_dir / "vibenature-hook"
        hook.write_text("#!/bin/sh\n# an older hook\nexit 0\n")
        before = self.settings.read_text()
        self.assertEqual(self.run_installer("install", "--dry-run"), 0)
        self.assertIn("older hook", hook.read_text(), "a dry run copies nothing")
        self.assertEqual(self.run_installer("install"), 0)
        self.assertEqual(hook.read_bytes(), (Path(hook_install.__file__).parent / "vibenature-hook").read_bytes())
        self.assertTrue(os.access(hook, os.X_OK))
        self.assertEqual(self.settings.read_text(), before, "the settings are left as they were")

    def test_uninstall_removes_exactly_ours(self):
        self.settings.write_text(json.dumps(self.theirs()))
        self.run_installer("install")
        self.assertEqual(self.run_installer("uninstall"), 0)
        self.assertEqual(json.loads(self.settings.read_text()), self.theirs())
        self.assertEqual(len(list(self.settings.parent.glob("settings.json.vibenature-backup-*"))), 2, "no backup overwrites another")

    def test_fresh_settings_and_uninstall_leaves_no_file(self):
        self.assertEqual(self.run_installer("install"), 0)
        self.assertEqual(set(json.loads(self.settings.read_text())["hooks"]), set(hook_install.CLAUDE_EVENTS))
        self.run_installer("uninstall")
        self.assertFalse(self.settings.exists(), "a file the installer made is taken away again")

    def test_uninstall_restores_an_absent_codex_file(self):
        # The human's machine was left with `{}` in ~/.codex/hooks.json (issue 281).
        self.assertEqual(self.run_installer("install", harness=("codex",)), 0)
        self.assertTrue(self.codex.exists())
        self.assertEqual(self.run_installer("uninstall", "--dry-run", harness=("codex",)), 0)
        self.assertIn("would remove 6 hooks and delete the file", self.output)
        self.assertTrue(self.codex.exists())
        self.assertEqual(self.run_installer("uninstall", harness=("codex",)), 0)
        self.assertEqual(sorted(p.name for p in self.codex.parent.iterdir()), [], "no file, no backup left behind")
        self.assertFalse((self.dir / ".vibenature" / hook_install.MADE_FILE).exists(), "nothing left to remember")

    def test_uninstall_deletes_an_empty_file_it_found_but_keeps_one_with_more(self):
        self.codex.write_text("{}\n")
        self.run_installer("install", harness=("codex",))
        self.run_installer("uninstall", harness=("codex",))
        self.assertFalse(self.codex.exists(), "an empty {} it filled is emptied away")
        self.run_installer("install", harness=("codex",))
        data = json.loads(self.codex.read_text())
        data["theirs"] = 1
        self.codex.write_text(json.dumps(data))
        self.run_installer("uninstall", harness=("codex",))
        self.assertEqual(json.loads(self.codex.read_text()), {"theirs": 1}, "something of theirs: the file stays")
        self.settings.write_text(json.dumps(self.theirs()))
        self.run_installer("install")
        self.run_installer("uninstall")
        self.assertEqual(json.loads(self.settings.read_text()), self.theirs(), "a file it did not make stays")

    def test_never_clobbers_a_broken_file(self):
        self.settings.write_text('{"model": "opus",')
        self.assertEqual(self.run_installer("install"), 1)
        self.assertEqual(self.settings.read_text(), '{"model": "opus",')
        self.settings.write_text('{"hooks": []}')
        self.assertEqual(self.run_installer("install"), 1)
        self.assertEqual(self.settings.read_text(), '{"hooks": []}')
        self.settings.write_text('{"hooks": {"Stop": {}}}')
        self.assertEqual(self.run_installer("install"), 1)
        self.assertEqual(self.settings.read_text(), '{"hooks": {"Stop": {}}}')

    def test_dry_run_writes_nothing_for_either_harness(self):
        self.settings.write_text(json.dumps(self.theirs()))
        self.codex.write_text(json.dumps(self.codex_theirs()))
        before = {p: (p.read_bytes(), p.stat().st_mtime_ns) for p in (self.settings, self.codex)}
        self.assertEqual(self.run_installer("install", "--dry-run", harness=("claude", "codex")), 0)
        self.assertEqual({p: (p.read_bytes(), p.stat().st_mtime_ns) for p in before}, before)
        self.assertEqual(sorted(x.name for x in self.dir.rglob("*") if x.is_file()), ["hooks.json", "settings.json"],
                         "no backup, no hook copy, no salt")
        self.assertIn("would add 8 hooks", self.output)
        self.assertIn("would add 6 hooks", self.output)
        self.assertTrue(self.output.startswith("Dry run: nothing was written."))
        self.assertNotIn("guard.sh", self.output, "the dry run shows only what it would change")

    def test_json_dry_run_reports_each_harness_and_writes_nothing(self):
        # The welcome (issue 199) shows this in plain words before anything is installed.
        self.settings.write_text(json.dumps(self.theirs()))
        before = self.settings.read_bytes()
        self.assertEqual(self.run_installer("install", "--dry-run", "--json", harness=("claude", "codex")), 0)
        report = json.loads(self.output)
        self.assertTrue(report["dry_run"])
        self.assertEqual([h["key"] for h in report["harnesses"]], ["claude", "codex"])
        claude, codex = report["harnesses"]
        self.assertFalse(claude["create"])
        self.assertTrue(codex["create"])
        self.assertEqual(claude["added"], hook_install.CLAUDE_EVENTS)
        self.assertEqual(self.settings.read_bytes(), before)
        self.assertFalse(self.codex.exists())
        self.assertFalse((self.hook_dir / "vibenature-hook").exists())
        self.assertEqual(self.run_installer("install", "--json"), 0)
        self.assertFalse(json.loads(self.output)["dry_run"])
        self.assertEqual(len(self.ours(self.settings, "Stop")), 1, "the same call without --dry-run installs")

    def test_install_replaces_old_skypatch_entries_and_keeps_theirs(self):
        settings = self.theirs()
        for event in hook_install.CLAUDE_EVENTS:
            settings["hooks"].setdefault(event, []).append(
                {"hooks": [{"type": "command", "command": f"/Users/x/.skypatch/bin/skypatch-hook {event}", "timeout": 2}]})
        self.settings.write_text(json.dumps(settings))
        self.assertEqual(self.run_installer("install"), 0)
        after = json.loads(self.settings.read_text())
        commands = [h["command"] for groups in after["hooks"].values() for g in groups for h in g["hooks"]]
        self.assertFalse([c for c in commands if "skypatch-hook" in c], "old entries are gone")
        for event in hook_install.CLAUDE_EVENTS:
            self.assertEqual(len(self.ours(self.settings, event)), 1, event)
        self.assertEqual(after["hooks"]["PreToolUse"], self.theirs()["hooks"]["PreToolUse"])
        self.assertEqual(after["hooks"]["Stop"][0], self.theirs()["hooks"]["Stop"][0], "their Stop hook is kept")
        self.assertEqual(len(list(self.settings.parent.glob("settings.json.vibenature-backup-*"))), 1)

    def test_install_moves_an_entry_whose_hook_moved(self):
        self.run_installer("install")
        self.hook_dir = self.dir / "elsewhere"
        self.assertEqual(self.run_installer("install"), 0)
        for event in hook_install.CLAUDE_EVENTS:
            self.assertEqual(self.ours(self.settings, event), [f"{self.hook_dir}/vibenature-hook {event}"])

    def test_uninstall_also_removes_old_entries(self):
        settings = self.theirs()
        settings["hooks"]["SessionStart"] = [{"hooks": [{"type": "command", "command": "skypatch-hook SessionStart"}]}]
        self.settings.write_text(json.dumps(settings))
        self.assertEqual(self.run_installer("uninstall"), 0)
        self.assertEqual(json.loads(self.settings.read_text()), self.theirs())

    def test_symlinked_settings_stay_a_symlink(self):
        real = self.dir / "dotfiles.json"
        real.write_text("{}")
        self.settings.symlink_to(real)
        self.run_installer("install")
        self.assertTrue(self.settings.is_symlink())
        self.assertIn("hooks", json.loads(real.read_text()))

    def test_codex_install_merges_and_uninstalls_cleanly(self):
        self.codex.write_text(json.dumps(self.codex_theirs()))
        self.assertEqual(self.run_installer("install", harness=("codex",)), 0)
        for event in hook_install.CODEX_EVENTS:
            self.assertEqual(self.ours(self.codex, event), [f"{self.hook_dir}/vibenature-hook codex {event}"])
        after = json.loads(self.codex.read_text())
        self.assertEqual(after["hooks"]["PreToolUse"], self.codex_theirs()["hooks"]["PreToolUse"])
        self.assertEqual(after["hooks"]["Stop"][0], self.codex_theirs()["hooks"]["Stop"][0])
        self.assertIn("/hooks", self.output, "the human is told to trust the hooks in Codex")
        self.assertFalse(self.settings.exists(), "Claude Code's settings are not touched")
        self.assertEqual(self.run_installer("install", harness=("codex",)), 0)
        self.assertEqual(json.loads(self.codex.read_text()), after)
        self.assertEqual(self.run_installer("uninstall", harness=("codex",)), 0)
        self.assertEqual(json.loads(self.codex.read_text()), self.codex_theirs())
        self.assertEqual(len(list(self.codex.parent.glob("hooks.json.vibenature-backup-*"))), 2)

    def test_codex_refuses_when_config_toml_defines_hooks(self):
        toml = self.codex.parent / "config.toml"
        toml.write_text('model = "x"\n[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "x"\n')
        self.assertEqual(self.run_installer("install", harness=("codex",)), 1)
        self.assertFalse(self.codex.exists())
        toml.write_text('model = "x"\n[hooks.state."user:Stop:0"]\ntrusted_hash = "abc"\n')
        self.assertEqual(self.run_installer("install", harness=("codex",)), 0, "trust records are not hook definitions")
        self.assertTrue(self.codex.exists())
        self.assertEqual(toml.read_text(), 'model = "x"\n[hooks.state."user:Stop:0"]\ntrusted_hash = "abc"\n', "config.toml is never edited")

    def test_install_finds_installed_harnesses_only(self):
        self.codex.parent.rmdir()
        self.assertEqual(self.run_installer("install", harness=()), 0)
        self.assertTrue(self.settings.exists())
        self.assertFalse(self.codex.parent.exists(), "Codex is not installed here: nothing made for it")
        self.assertIn("– Codex        not installed: skipped", self.output)
        hook_install.which = lambda name: "/usr/local/bin/codex" if name == "codex" else None
        self.assertEqual(self.run_installer("install", harness=()), 0)
        self.assertEqual(len(self.ours(self.codex, "Stop")), 1, "a codex on PATH counts as installed")

    def test_status_reports_each_harness(self):
        self.run_installer("install")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            hook_install.main(["status", "--json", "--home", str(self.dir), "--hook-dir", str(self.hook_dir)])
        report = json.loads(out.getvalue())
        self.assertTrue(report["claude"]["complete"])
        self.assertTrue(report["codex"]["installed"])
        self.assertEqual(report["codex"]["wired"], [])

    def test_codex_home_moves_codex_files(self):
        other = self.dir / "codex-work"
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = hook_install.main(["install", "--harness=codex", "--home", str(self.dir), "--codex-dir", str(other),
                                      "--hook-dir", str(self.hook_dir)])
        self.assertEqual(code, 0)
        self.assertTrue((other / "hooks.json").exists())
        self.assertFalse(self.codex.exists())


class OutputTest(unittest.TestCase):
    """What a person reads (issue 281), golden, on a temp HOME: plain when piped, colour only on a terminal."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        (self.home / ".claude").mkdir()
        (self.home / ".claude" / "settings.json").write_text(json.dumps({"model": "opus"}))
        (self.home / ".codex").mkdir()
        self._saved = (hook_install.which, hook_install.stamp, hook_install.use_color)
        hook_install.which = lambda name: None
        hook_install.stamp = lambda: "20261020-090000"
        hook_install.use_color = lambda stream: False

    def tearDown(self):
        hook_install.which, hook_install.stamp, hook_install.use_color = self._saved
        self.tmp.cleanup()

    def run_it(self, *args, code=0):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            self.assertEqual(hook_install.main([*args, "--home", str(self.home)]), code)
        return out.getvalue()

    def assertGolden(self, got, want):
        self.assertEqual(got, textwrap.dedent(want).lstrip("\n"))

    def test_install_dry_run_install_rerun_status_and_uninstall(self):
        self.assertGolden(self.run_it("install", "--dry-run"), """
            Dry run: nothing was written.

              → Claude Code  ~/.claude/settings.json  would add 8 hooks
                             a backup is made first
              → Codex        ~/.codex/hooks.json      would create it with 6 hooks

            Run it without --dry-run to make these changes.

            VibeNature hears only when an agent starts or stops working, never what it works on.
            """)
        self.assertGolden(self.run_it("install"), """
            Connected VibeNature to Claude Code and Codex.

              ✓ Claude Code  ~/.claude/settings.json  8 hooks added
                             backup ~/.claude/settings.json.vibenature-backup-20261020-090000
              ✓ Codex        ~/.codex/hooks.json      6 hooks added, new file

            Next
              • Codex: open codex, type /hooks and trust VibeNature's 6 hooks. Until
                then Codex runs none of them.
              • Claude Code: restart sessions already open; new ones are connected.

            VibeNature hears only when an agent starts or stops working, never what it works on.
            """)
        self.assertGolden(self.run_it("install"), """
            VibeNature is already connected. Nothing changed.

              ✓ Claude Code  ~/.claude/settings.json  already connected
              ✓ Codex        ~/.codex/hooks.json      already connected
            """)
        self.assertGolden(self.run_it("status"), """
            VibeNature's connections

              ✓ Claude Code  ~/.claude/settings.json  connected
              ✓ Codex        ~/.codex/hooks.json      connected
            """)
        self.assertGolden(self.run_it("uninstall", "--dry-run"), """
            Dry run: nothing was written.

              → Claude Code  ~/.claude/settings.json  would remove 8 hooks
                             a backup is made first
              → Codex        ~/.codex/hooks.json      would remove 6 hooks and delete the file

            Run it without --dry-run to make these changes.
            """)
        self.assertGolden(self.run_it("uninstall"), """
            Disconnected VibeNature from Claude Code and Codex.

              ✓ Claude Code  ~/.claude/settings.json  8 hooks removed
                             backup ~/.claude/settings.json.vibenature-backup-20261020-090000-2
              ✓ Codex        ~/.codex/hooks.json      6 hooks removed, file deleted (VibeNature made it)

            The hook stays at ~/.vibenature/bin/vibenature-hook; delete it if you like.
            """)
        self.assertGolden(self.run_it("uninstall"), """
            VibeNature was not connected. Nothing changed.

              – Claude Code  ~/.claude/settings.json  not connected
              – Codex        ~/.codex/hooks.json      not connected
            """)

    def test_a_harness_not_installed_in_colour_on_a_terminal(self):
        (self.home / ".codex").rmdir()
        hook_install.use_color = lambda stream: True
        b, d, g, x = "\x1b[1m", "\x1b[2m", "\x1b[32m", "\x1b[0m"
        self.assertEqual(self.run_it("install"), "".join([
            f"{b}Connected VibeNature to Claude Code.{x}\n\n",
            f"  {g}✓{x} {b}Claude Code{x}  ~/.claude/settings.json  8 hooks added\n",
            f"                 {d}backup {x}~/.claude/settings.json.vibenature-backup-20261020-090000\n",
            f"  {d}–{x} {b}Codex{x}        not installed: skipped\n\n",
            f"{b}Next{x}\n",
            "  • Claude Code: restart sessions already open; new ones are connected.\n\n",
            f"{d}VibeNature hears only when an agent starts or stops working, never what it works on.{x}\n"]))

    def test_verbose_names_the_events_and_the_hook(self):
        out = self.run_it("install", "--harness=codex", "--verbose")
        self.assertGolden(out, """
            Connected VibeNature to Codex.

              ✓ Codex  ~/.codex/hooks.json                6 hooks added, new file
                       adds SessionStart, UserPromptSubmit, Stop, Interrupt, PermissionRequest, SessionEnd
              ✓ Hook   ~/.vibenature/bin/vibenature-hook  copied

            Next
              • Codex: open codex, type /hooks and trust VibeNature's 6 hooks. Until
                then Codex runs none of them.

            VibeNature hears only when an agent starts or stops working, never what it works on.
            """)

    def test_errors_say_what_to_do(self):
        (self.home / ".claude" / "settings.json").write_text('{"model": "opus",')
        (self.home / ".codex" / "config.toml").write_text('[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "x"\n')
        self.assertGolden(self.run_it("install", code=1), """
            VibeNature could not connect.

              ! Claude Code  ~/.claude/settings.json  left untouched: not valid JSON at line 1, column 18
              ! Codex        ~/.codex/hooks.json      left untouched: config.toml already defines hooks

            Next
              • Claude Code: correct ~/.claude/settings.json, then run this again.
                Nothing in it was changed.
              • Codex: move the hooks defined in ~/.codex/config.toml into
                ~/.codex/hooks.json, then run this again. Codex warns when both define
                hooks.
            """)
        (self.home / ".claude" / "settings.json").write_text("{}")
        out = self.run_it("install", code=1)
        self.assertTrue(out.startswith("Connected VibeNature to Claude Code. Codex was left untouched.\n"), out)

    def test_no_harness_found(self):
        (self.home / ".codex").rmdir()
        (self.home / ".claude" / "settings.json").unlink()
        (self.home / ".claude").rmdir()
        self.assertGolden(self.run_it("install"), """
            No coding agent found here.

              – Claude Code  not installed: skipped
              – Codex        not installed: skipped

            Next
              • Install Claude Code or Codex, then run this again.
            """)
        self.assertEqual(list(self.home.iterdir()), [], "nothing made")

    def test_json_carries_the_same_words(self):
        report = json.loads(self.run_it("install", "--dry-run", "--json"))
        self.assertEqual(report["privacy"], hook_install.PRIVACY)
        self.assertEqual([(n["key"], n["text"]) for n in report["next"]],
                         [("codex", hook_install.NEXT["codex"].format(n=6)), ("claude", hook_install.NEXT["claude"])])
        self.assertEqual([h["said"] for h in report["harnesses"]], ["would add 8 hooks", "would create it with 6 hooks"])
        self.assertNotIn("\x1b", report["log"])

    def test_colour_only_on_a_terminal_without_no_color(self):
        hook_install.use_color = self._saved[2]
        tty = type("Tty", (), {"isatty": lambda self: True})()
        env = {k: v for k, v in os.environ.items() if k not in ("NO_COLOR", "TERM")}
        with unittest.mock.patch.dict(os.environ, env, clear=True):
            self.assertTrue(hook_install.use_color(tty))
            self.assertFalse(hook_install.use_color(io.StringIO()))
            os.environ["NO_COLOR"] = "1"
            self.assertFalse(hook_install.use_color(tty))


class FakeCodex:
    """Stands in for `codex app-server` (issue 281): answers hooks/list from the real hooks.json and keeps
    the trust state config/batchWrite writes, the way Codex's /hooks screen uses them."""

    def __init__(self, answers=True):
        self.answers = answers
        self.state = {}
        self.calls = []

    def __call__(self, codex_dir, calls):
        if not self.answers:
            return None, "codex did not answer"
        hooks_file = Path(codex_dir) / "hooks.json"
        try:
            result = None
            step = calls.send(None)
            while True:
                method, params = step
                self.calls.append(method)
                if method == "hooks/list":
                    config = json.loads(hooks_file.read_text()) if hooks_file.exists() else {}
                    listed = []
                    for event, groups in (config.get("hooks") or {}).items():
                        for g, group in enumerate(groups):
                            for i, h in enumerate(group.get("hooks", [])):
                                key = f"{hooks_file}:{event}:{g}:{i}"
                                listed.append({"key": key, "command": h.get("command"), "sourcePath": str(hooks_file),
                                               "statusMessage": h.get("statusMessage"), "currentHash": "sha256:" + key,
                                               "trustStatus": "trusted" if key in self.state else "untrusted"})
                    result = {"data": [{"cwd": "x", "hooks": listed}]}
                else:
                    for edit in params["edits"]:
                        if edit["mergeStrategy"] == "upsert":
                            self.state.update(edit["value"])
                        else:
                            self.state.pop(json.loads(edit["keyPath"][len("hooks.state."):]), None)
                    result = {"status": "ok"}
                step = calls.send(result)
        except StopIteration as done:
            return done.value, ""


class CodexTrustTest(unittest.TestCase):
    """Install names Codex's hooks and asks Codex to trust them; uninstall takes the trust away (issue 281)."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        (self.home / ".codex").mkdir()
        self.codex = self.home / ".codex" / "hooks.json"
        self._saved = (hook_install.which, hook_install.stamp, hook_install.use_color, hook_install.codex_rpc)
        hook_install.which = lambda name: None
        hook_install.stamp = lambda: "20261020-090000"
        hook_install.use_color = lambda stream: False

    def tearDown(self):
        hook_install.which, hook_install.stamp, hook_install.use_color, hook_install.codex_rpc = self._saved
        self.tmp.cleanup()

    def run_it(self, *args):
        out = io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
            hook_install.main([*args, "--home", str(self.home)])
        return out.getvalue()

    def test_hooks_are_named_and_trusted_and_untrusted_on_uninstall(self):
        fake = hook_install.codex_rpc = FakeCodex()
        out = self.run_it("install")
        config = json.loads(self.codex.read_text())
        names = {h["statusMessage"] for gs in config["hooks"].values() for g in gs for h in g["hooks"]}
        self.assertEqual(names, {"VibeNature"}, "/hooks shows a name, not 'Unnamed hook'")
        self.assertEqual(config["description"], hook_install.CODEX_DESCRIPTION)
        self.assertEqual(len(fake.state), 6, "Codex is asked to trust all six")
        self.assertIn("6 hooks added, new file, trusted", out)
        self.assertNotIn("type /hooks", out, "nothing left for the person to trust")
        again = self.run_it("install")
        self.assertIn("already connected", again)
        self.assertNotIn("config/batchWrite", fake.calls[2:], "a re-run trusts nothing twice")
        out = self.run_it("uninstall")
        self.assertEqual(fake.state, {}, "uninstall takes the trust away")
        self.assertIn("trust removed", out)
        self.assertFalse(self.codex.exists())

    def test_without_codex_answering_it_says_to_use_hooks(self):
        hook_install.codex_rpc = FakeCodex(answers=False)
        out = self.run_it("install")
        self.assertIn("type /hooks and trust VibeNature's 6 hooks", out)
        self.assertNotIn("trusted", out.split("Next")[0])

    def test_no_trust_leaves_it_to_the_person(self):
        fake = hook_install.codex_rpc = FakeCodex()
        out = self.run_it("install", "--no-trust")
        self.assertEqual(fake.calls, [], "Codex is not asked")
        self.assertIn("type /hooks", out)

    def test_an_older_install_gets_named(self):
        hook_install.codex_rpc = FakeCodex()
        self.run_it("install")
        config = json.loads(self.codex.read_text())
        for gs in config["hooks"].values():
            for g in gs:
                for h in g["hooks"]:
                    h.pop("statusMessage")
        self.codex.write_text(json.dumps(config))
        out = self.run_it("install")
        self.assertIn("6 hooks named", out)


class DataHomeTest(unittest.TestCase):
    """~/.skypatch -> ~/.vibenature (issue 211), on a temp HOME only."""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)
        self.old, self.new = self.home / ".skypatch", self.home / ".vibenature"

    def tearDown(self):
        self.tmp.cleanup()

    def test_resolve_prefers_the_new_folder_and_falls_back_to_the_old(self):
        self.assertEqual(data_home.resolve(self.home), self.new, "neither: the new name")
        self.old.mkdir()
        self.assertEqual(data_home.resolve(self.home), self.old, "only the old one: keep using it until it moves")
        self.new.mkdir()
        self.assertEqual(data_home.resolve(self.home), self.new, "both: the new one")

    def test_migrate_moves_once_and_leaves_links_and_a_note(self):
        (self.old / "notes" / "work").mkdir(parents=True)
        (self.old / "salt").write_bytes(b"s" * 32)
        (self.old / "notes.env").write_text("KEY=1\n")
        self.assertTrue(data_home.migrate(self.home).startswith("moved"))
        self.assertEqual((self.new / "salt").read_bytes(), b"s" * 32)
        self.assertTrue((self.new / "notes" / "work").is_dir())
        self.assertTrue((self.old / data_home.NOTE).is_file())
        for name in ("salt", "notes", "notes.env"):
            self.assertTrue((self.old / name).is_symlink(), name)
        self.assertEqual((self.old / "notes.env").read_text(), "KEY=1\n", "old paths still read through the links")
        self.assertEqual(data_home.resolve(self.home), self.new)
        self.assertTrue(data_home.migrate(self.home).startswith("nothing"), "a second run does nothing")

    def test_migrate_never_merges_into_an_existing_folder(self):
        self.old.mkdir()
        (self.old / "salt").write_text("old")
        self.new.mkdir()
        self.assertTrue(data_home.migrate(self.home).startswith("nothing"))
        self.assertEqual((self.old / "salt").read_text(), "old")
        self.assertFalse((self.new / "salt").exists())

    def test_migrate_without_an_old_folder_makes_nothing(self):
        self.assertTrue(data_home.migrate(self.home).startswith("nothing"))
        self.assertFalse(self.new.exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
