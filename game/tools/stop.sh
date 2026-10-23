#!/bin/sh
# `just stop`: quits the game `just dev` started, by the process id it wrote
# (build/dev/godot.pid), never by name. SIGTERM first: the native extension turns it into the
# Dock menu's Quit (the game saves, the app exits normally, no crash report). If that has not
# worked after 15 s, SIGINT (Godot's own clean stop). Nothing harsher.
set -eu

root="${1:-$(cd "$(dirname "$0")/../.." && pwd)}"
pidfile="$root/build/dev/godot.pid"

if [ ! -f "$pidfile" ]; then
	echo "stop: nothing to stop (no $pidfile)"
	exit 0
fi
pid="$(cat "$pidfile")"
case "$pid" in
	'' | *[!0-9]*)
		echo "stop: $pidfile does not hold a process id" >&2
		exit 1
		;;
esac
if ! ps -p "$pid" -o comm= 2>/dev/null | grep -q -i godot; then
	echo "stop: pid $pid is not running Godot; removing the stale $pidfile"
	rm -f "$pidfile"
	exit 0
fi

gone_within() {
	n=0
	while [ "$n" -lt "$1" ]; do
		kill -0 "$pid" 2>/dev/null || return 0
		sleep 0.2
		n=$((n + 1))
	done
	! kill -0 "$pid" 2>/dev/null
}

kill -TERM "$pid"
if gone_within 75; then
	rm -f "$pidfile"
	echo "stop: quit (pid $pid)"
	exit 0
fi
kill -INT "$pid" 2>/dev/null || true
if gone_within 25; then
	rm -f "$pidfile"
	echo "stop: quit after SIGINT (pid $pid)"
	exit 0
fi
echo "stop: pid $pid is still running; quit it from its Dock icon" >&2
exit 1
