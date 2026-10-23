#!/bin/sh
# `just dev [args]`: runs the game for real, without ever activating it
# (Skypatch issue 50).
#
# The player may be in a game that holds the mouse. Started from a shell, Godot runs its
# "unbundled activation hack" (activate SystemUIServer, then itself), and every activation
# change reaches the player's app. So the game is launched through LaunchServices in the
# background (open -g): not activated, a proper app bundle, so Godot skips the hack (the native
# extension also turns it off). Its process id goes to build/dev/godot.pid; `just stop`, or
# Ctrl-C here, quits it cleanly (SIGTERM: Godot's close request, the game saves).
#
# The game runs from its own copy, build/dev/game, made fresh at every start
# (issue 469). Godot reads art lazily, so a
# pull into the checkout while the game ran moved the van out from under it. The copy keeps its own
# .godot import cache; a restart picks up the latest pull.
#
# LaunchServices does not pass this shell's environment on, so every VIBENATURE_* variable is
# forwarded with --env.
set -eu

godot="$1"
shift
root="$(cd "$(dirname "$0")/../.." && pwd)"
run="$root/build/dev"
game="$run/game"
pidfile="$run/godot.pid"
mkdir -p "$run"

"$root/game/native/macos_windows/build.sh"

if [ -f "$pidfile" ]; then
	pid="$(cat "$pidfile")"
	if [ -n "$pid" ] && ps -p "$pid" -o comm= 2>/dev/null | grep -q -i godot; then
		echo "dev: already running (pid $pid); \`just stop\` quits it" >&2
		exit 1
	fi
fi
rsync -a --delete --exclude '/.godot/' "$root/game/" "$game/"

# A pull that adds a class_name leaves Godot's class cache stale, and the run then fails with
# "Could not find type" (Skypatch issue 180). Only an
# import rebuilds it, so import whenever a script is newer than the cache. Headless, so it never
# shows or activates anything.
cache="$game/.godot/global_script_class_cache.cfg"
if [ ! -f "$cache" ] || [ -n "$(find "$game" -name '*.gd' -newer "$cache" -not -path '*/.godot/*' -print -quit)" ]; then
	echo "dev: scripts changed since the last import; importing" >&2
	"$godot" --headless --path "$game" --import >"$run.import.log" 2>&1 || {
		echo "dev: the headless import failed; see $run.import.log" >&2
		exit 2
	}
	touch "$cache"
fi

bin="$(realpath "$godot")"
app="${bin%/Contents/MacOS/*}"
case "$app" in
	*.app) [ -d "$app" ] || { echo "dev: no app bundle at $app" >&2; exit 2; } ;;
	*) echo "dev: Godot is not inside an .app bundle ($bin)" >&2; exit 2 ;;
esac

rm -f "$pidfile" "$run/godot.out" "$run/godot.err"
: >"$run/godot.out"
: >"$run/godot.err"

set -- --path "$game" "$@"
envs=""
for name in $(env | sed -n 's/^\(VIBENATURE_[A-Z0-9_]*\)=.*/\1/p'); do
	[ "$name" = "VIBENATURE_PID_FILE" ] && continue
	envs="$envs $name"
done

launch() {
	set -- --stdout "$run/godot.out" --stderr "$run/godot.err" --args "$@"
	for name in $envs; do
		eval "value=\${$name}"
		set -- --env "$name=$value" "$@"
	done
	open -n -g -W -a "$app" --env "VIBENATURE_PID_FILE=$pidfile" "$@"
}

launch "$@" &
opener=$!
tail -n +1 -f "$run/godot.out" "$run/godot.err" &
tailer=$!

stop_it() {
	"$game/tools/stop.sh" "$root" || true
}
trap 'stop_it' INT TERM
wait "$opener" || wait "$opener" || true
kill "$tailer" 2>/dev/null || true
rm -f "$pidfile"
