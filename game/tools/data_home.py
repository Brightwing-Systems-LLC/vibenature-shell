#!/usr/bin/env python3
"""VibeNature's data folder, ~/.vibenature (Skypatch issue 211).

    python3 game/tools/data_home.py resolve   # prints the folder in use
    python3 game/tools/data_home.py migrate   # moves ~/.skypatch there (`just migrate-store`)

The folder was called ~/.skypatch until the rename. `resolve` picks VIBENATURE_HOME if that is
set. Otherwise it picks ~/.vibenature, unless only ~/.skypatch exists, in which case the old
folder is used until something moves it.

`migrate` moves ~/.skypatch to ~/.vibenature in one rename. It then leaves a folder at the old
place holding MOVED-TO-VIBENATURE.txt and one link per moved entry, so an old hook entry or an old
checkout's bench links keep working. It does nothing when ~/.vibenature already exists or there is
nothing to move. The game does the same on launch (scripts/core/data_home.gd).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

NEW = ".vibenature"
OLD = ".skypatch"
NOTE = "MOVED-TO-VIBENATURE.txt"


def resolve(home: Path | None = None) -> Path:
    env = os.environ.get("VIBENATURE_HOME", "")
    if env and home is None:
        return Path(env)
    home = home or Path.home()
    new, old = home / NEW, home / OLD
    if not new.exists() and old.is_dir() and not old.is_symlink():
        return old
    return new


def migrate(home: Path | None = None) -> str:
    """Move <home>/.skypatch to <home>/.vibenature. Returns what happened, in a few words."""
    home = home or Path.home()
    new, old = home / NEW, home / OLD
    if new.exists() or new.is_symlink():
        return "nothing to move: " + str(new) + " exists"
    if old.is_symlink() or not old.is_dir():
        return "nothing to move: no " + str(old)
    old.rename(new)
    old.mkdir()
    for entry in sorted(new.iterdir()):
        (old / entry.name).symlink_to(entry)
    (old / NOTE).write_text(
        f"VibeNature (formerly Skypatch) keeps its data in {new} now.\n"
        "The links in this folder point there, so old hook entries and bench links keep working.\n"
        "Delete this folder once `just hook-install` and `just link` have been run again.\n")
    return f"moved {old} to {new}"


def main(argv: list[str]) -> int:
    if argv[:1] == ["resolve"]:
        print(resolve())
        return 0
    if argv[:1] == ["migrate"]:
        print(migrate())
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
