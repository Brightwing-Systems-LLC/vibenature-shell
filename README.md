# VibeNature shell

VibeNature is a small living scene that sits in a corner of your desktop while you work with coding
agents. It notices, without reading anything, when an agent starts and finishes its turns, and the
scene answers quietly, with something to watch while a turn runs and a settling when it ends.

This repository is the **shell**: the open-source desktop app that plays a scene. It holds

- the windows and desktop integration (corner placement, never taking focus, never covering a
  full-screen app, Spaces), including the small macOS extension that keeps it that way
  (`game/native/macos_windows/`);
- the settings and configuration screens;
- **the agent hooks and the local event server** (below);
- the engine that plays a scene: sky, light, weather, wind, water, the director, and the general
  creature *bodies* (ways of moving a scene's animals: walkers, fliers, swimmers, waders, flocks);
- **the package loader**, which opens scene packages and refuses any that break the format.

It is written in GDScript for [Godot](https://godotengine.org) 4.7.

## Scenes are separate packages

The shell ships **no scene**. A scene (its painted plates, creatures, sounds, behaviour and tuning)
is a separate **package**: a folder of data, `package.json` plus `.json`, `.png`, `.ogg`, `.md` and
`.txt` files and nothing else. The loader reads JSON as text and images and sounds from bytes; it
never loads a Godot resource or a script from a package, so a package cannot run code. A package
that holds anything else, or a path outside its own folder, is refused with its reason, never a
crash. The checks are in `game/scripts/packages/` (`ScenePackage`, `ScenePackages`, `PackageGate`).

Brightwing's own scenes (the forest pond and the ones after it) are proprietary packages and are not
in this repository. Built from this repository alone, the shell starts with a plain **"No scene
installed"** card in the bottom-right corner of the screen and a Quit button, and starts nothing else.
A scene goes in `game/packages/<id>/`. The package format will be published here with a small example
package to take apart.

## What the hooks send

VibeNature learns that your agent is working through the agent's own hook mechanism. Nothing else in
the shell reads anything from your agents, and nothing leaves your machine.

**The hook** is one short shell script, `game/tools/vibenature-hook`. Claude Code (`~/.claude/settings.json`)
or Codex (`~/.codex/hooks.json`) runs it on a few of its events. It:

1. takes the event's name from its argument, mapped to one of seven kinds: `session_start`,
   `turn_start` (you sent a prompt), `still_busy` (a tool finished, the turn goes on), `turn_end`,
   `tool_fail`, `needs_input` (the agent is waiting for you) and `session_end`;
2. reads **only the session id** from the event's JSON (the first `"session_id"` in its first 4 KB);
   everything else on its input (the prompt, code, file names, paths, tool input and output) is
   discarded unread;
3. hashes the session id with a random salt made once on your machine (`~/.vibenature/salt`, never
   sent), keeping 16 hex characters, so sessions can be told apart but not identified;
4. posts exactly `{"kind", "source", "session_hash", "ts"}` (`source` is `claude_code` or `codex`;
   `ts` is the time in seconds) to `http://127.0.0.1:47474/event`, and refuses any other address.

It prints nothing, gives up after 0.2 s and always exits 0, so it can never slow or change your agent.

**The event server** (`game/scripts/bridge/event_server.gd`) listens on `127.0.0.1` only and accepts
exactly those four keys, a known kind, at most 512 bytes (`agent_event.gd`); anything else is dropped.
No event is saved. **The installer** (`game/tools/hook_install.py`) adds and removes only VibeNature's
own entries in those two files, backs each file up first, and shows what it would change with
`--dry-run`. `game/tools/test_hook.py` checks that prompts, paths and file names never leave the hook.

## Build and run

You need macOS (the window behaviour is macOS-only for now), [Godot 4.7](https://godotengine.org/download),
`just`, Python 3.11+ and the Xcode command line tools (`clang`, for the window extension).

```sh
just dev        # build the window extension, then run the shell in the background (never activated)
just stop       # quit it cleanly
just check      # start it headless with no scene: it must say "No scene installed" and quit cleanly
just test       # the hook and installer tests, and the window extension's tests
just hook-install --dry-run   # what connecting Claude Code or Codex would change; drop --dry-run to do it
just hook-uninstall           # remove exactly VibeNature's entries again
```

`GODOT=/path/to/godot just dev` picks a Godot that is not on your `PATH`. You can also open `game/`
in the Godot editor.

## Licence and contributing

The shell is licensed under the **GNU General Public License v3.0** (`LICENSE`). The VibeNature name
is a trademark of Brightwing Systems LLC; a fork must use another name. Scene packages, their art and
sound are not part of the shell and are not covered by its licence. The font in `game/assets/fonts/`
is under the SIL Open Font License (`Fraunces_OFL.txt`).

Issues are welcome. **Contributions open once a contributor licence agreement is in place**; until
then, pull requests cannot be merged.
