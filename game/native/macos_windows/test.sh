#!/bin/sh
# Checks the built extension without a window or anything on screen: the window flags, that
# nothing in it changes the active app, and that SIGTERM quits cleanly.
set -e
cd "$(dirname "$0")"
[ "$(uname)" = "Darwin" ] || exit 0
lib=bin/libvibenature_macos_windows.dylib
mkdir -p bin
clang -O0 -Wall -o bin/test_behaviour test_behaviour.c
overlay_title=$(sed -n 's/^const OVERLAY_TITLE := "\(.*\)"$/\1/p' ../../scripts/transit_window.gd)
bin/test_behaviour "$lib" "$overlay_title"
clang -O0 -Wall -fno-objc-arc -framework Cocoa -o bin/test_activation test_activation.m
bin/test_activation "$lib"
# The old focus hand-back re-activated the player's app whenever VibeNature became active
# (issue 50). Nothing may watch activations to answer them again.
if nm -u "$lib" | grep -q -E "_NSWorkspaceDidActivateApplicationNotification|_NSApplicationDidBecomeActiveNotification"; then
	echo "FAIL native: the extension watches app activations again (issue 50)" >&2
	exit 1
fi
# The daily rhythm's Mac signals (issue 198): counts only.
clang -O0 -Wall -o bin/test_day_signals test_day_signals.c
bin/test_day_signals "$lib"
# Presence for the start of the day (issue 431): the idle seconds only. Nothing that reads keys, characters,
# windows, apps or the screen may be linked or called.
clang -O0 -Wall -o bin/test_presence test_presence.c
bin/test_presence "$lib"
if nm -u "$lib" | grep -q -E "_CGEventTapCreate|_CGEventKeyboardGetUnicodeString|_CGEventGetIntegerValueField|_CGWindowListCopyWindowInfo|_CGWindowListCreateImage|_CGDisplayCreateImage|_IOHIDManagerCreate|_CGEventSourceKeyState|_CGEventSourceButtonState"; then
	echo "FAIL native: the extension links something that reads input, windows, apps or the screen (issue 431)" >&2
	exit 1
fi
if grep -q -E "addGlobalMonitorForEvents|addLocalMonitorForEvents|frontmostApplication|runningApplications|CGEventTap|kCGEventKeyDown|CGWindowList" macos_windows.m; then
	echo "FAIL native: the extension reads input, windows or apps (issue 431)" >&2
	exit 1
fi
# Open at login (issue 196): only the release app, and the system's states as the game's words.
clang -O0 -Wall -o bin/test_login_item test_login_item.c
bin/test_login_item "$lib"
