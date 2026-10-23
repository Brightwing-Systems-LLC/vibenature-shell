godot := env("GODOT", `command -v godot || echo "$HOME/Library/Application Support/godotenv/godot/bin/godot"`)

default:
    @just --list

# Build the native macOS window extension if its source changed
native:
    game/native/macos_windows/build.sh

# Run the shell without activating it (LaunchServices, background); `just stop` quits it cleanly
dev *args: native
    VIBENATURE_SCENE=1 game/tools/dev.sh "{{godot}}" {{args}}

# Quit the shell `just dev` started (by its pid file, cleanly)
stop:
    game/tools/stop.sh

# Open the project in the Godot editor
edit:
    "{{godot}}" --path game --editor

# Start the shell headless on throwaway files with no scene package: it must say "no scene installed" and quit cleanly
check:
    #!/bin/sh
    set -eu
    "{{godot}}" --headless --path game --import >/dev/null 2>&1
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    out="$(VIBENATURE_SETTINGS="$tmp/settings.json" VIBENATURE_SAVE="$tmp/save.json" VIBENATURE_FRESH=1 \
        VIBENATURE_NO_WELCOME=1 VIBENATURE_NO_MIGRATE=1 VIBENATURE_SCENE=1 VIBENATURE_HOOK_HOME="$tmp" \
        VIBENATURE_NO_BEACON=1 VIBENATURE_NO_LOGIN_ITEM=1 \
        "{{godot}}" --headless --path game --quit-after 120 2>&1)"
    printf '%s\n' "$out" | grep '^VibeNature: ' || true
    printf '%s\n' "$out" | grep -q 'VibeNature: no scene installed' || { echo "check: FAILED, no 'no scene installed' line"; exit 1; }
    if printf '%s\n' "$out" | grep -q -E 'SCRIPT ERROR|Parse Error'; then printf '%s\n' "$out" | tail -40; echo "check: FAILED, a script error"; exit 1; fi
    echo "check: ok"

# The tests: the window extension's checks, the hook and its installer
test: native
    game/native/macos_windows/test.sh
    python3 game/tools/test_hook.py

# Open every package in game/packages/ as the shell does and print what passed the loader's gate
package-check *args:
    "{{godot}}" --headless --path game --import
    "{{godot}}" --headless --path game --script res://tools/package_check.gd -- {{args}}

# Connect the installed agents (Claude Code: ~/.claude/settings.json; Codex: ~/.codex/hooks.json). --dry-run shows what it would do
hook-install *args:
    python3 game/tools/hook_install.py install {{args}}

# Disconnect: removes exactly VibeNature's hook entries from every agent's file (backed up first)
hook-uninstall *args:
    python3 game/tools/hook_install.py uninstall {{args}}

# Which agents are installed and connected
hook-status *args:
    python3 game/tools/hook_install.py status {{args}}
