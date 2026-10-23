// Checks the Spaces / full-screen flags the extension gives every window, for each value of
// display.show_over_full_screen, without making a window
// (Skypatch issue 50). Run by test.sh.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

// AppKit's values (NSWindow.h); a change there would show up here as a failure.
enum {
	kCanJoinAllSpaces = 1 << 0,
	kMoveToActiveSpace = 1 << 1,
	kStationary = 1 << 4,
	kIgnoresCycle = 1 << 6,
	kFullScreenAuxiliary = 1 << 8,
};

// AppKit's window levels (NSWindow.h / CGWindowLevel.h).
enum {
	kNormalLevel = 0,
	kFloatingLevel = 3,
	kMainMenuLevel = 24,
};

static int failures = 0;

static void check(int condition, const char *message) {
	if (!condition) {
		fprintf(stderr, "FAIL native: %s\n", message);
		failures++;
	}
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: test_behaviour <dylib>\n");
		return 2;
	}
	void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (lib == NULL) {
		fprintf(stderr, "FAIL native: cannot load %s: %s\n", argv[1], dlerror());
		return 1;
	}
	unsigned long (*behaviour)(int) = (unsigned long (*)(int))dlsym(lib, "vibenature_collection_behaviour");
	int (*show_over)(void) = (int (*)(void))dlsym(lib, "vibenature_show_over_full_screen");
	check(behaviour != NULL && show_over != NULL, "the extension exports its full-screen query");
	if (behaviour == NULL || show_over == NULL) {
		return 1;
	}

	unsigned long off = behaviour(0);
	unsigned long on = behaviour(1);
	check(!(off & kFullScreenAuxiliary), "off: windows stay out of other apps' full-screen Spaces");
	check(on & kFullScreenAuxiliary, "on: windows show over full-screen apps");
	unsigned long both = kCanJoinAllSpaces | kStationary | kIgnoresCycle;
	check((off & both) == both && (on & both) == both, "either way: every Space, stationary, out of the window cycle");
	check(!(off & kMoveToActiveSpace) && !(on & kMoveToActiveSpace), "never moves to the active Space");

	unsetenv("VIBENATURE_SHOW_OVER_FULL_SCREEN");
	check(!show_over(), "no setting given: off (the default)");
	setenv("VIBENATURE_SHOW_OVER_FULL_SCREEN", "0", 1);
	check(!show_over(), "\"0\": off");
	setenv("VIBENATURE_SHOW_OVER_FULL_SCREEN", "", 1);
	check(!show_over(), "empty: off");
	setenv("VIBENATURE_SHOW_OVER_FULL_SCREEN", "1", 1);
	check(show_over(), "\"1\": on");

	// The flight window's level (issue 235):
	// the extension knows it by the exact title GDScript gives it (argv[2], read by test.sh from
	// TransitWindow.OVERLAY_TITLE), and lifts it over normal and on-top windows, under the menu bar.
	int (*is_overlay)(const char *) = (int (*)(const char *))dlsym(lib, "vibenature_is_overlay_title");
	long (*overlay_level)(void) = (long (*)(void))dlsym(lib, "vibenature_overlay_level");
	check(is_overlay != NULL && overlay_level != NULL, "the extension exports its overlay query");
	if (is_overlay == NULL || overlay_level == NULL) {
		return 1;
	}
	check(argc >= 3 && argv[2][0] != '\0', "test.sh found TransitWindow.OVERLAY_TITLE");
	if (argc >= 3) {
		check(is_overlay(argv[2]), "the GDScript overlay title is the extension's overlay title");
	}
	check(!is_overlay("VibeNature"), "the scene is not an overlay");
	check(!is_overlay("VibeNature \xc2\xb7 settings"), "settings is not an overlay");
	check(!is_overlay("VibeNature \xc2\xb7 flight"), "the old flight title is not matched");
	check(!is_overlay("VibeNature \xc2\xb7 transit"), "nor the old transit title (suffix match is gone)");
	check(!is_overlay(NULL), "no title: not an overlay");
	long level = overlay_level();
	check(level > kNormalLevel, "overlay: above normal windows");
	check(level > kFloatingLevel, "overlay: above patches that are on top");
	check(level < kMainMenuLevel, "overlay: under the menu bar");

	if (failures == 0) {
		printf("native: full-screen flags and overlay level ok\n");
	}
	return failures == 0 ? 0 : 1;
}
