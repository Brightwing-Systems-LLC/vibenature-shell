// Checks open at login's pure parts (issue 196) without
// registering anything: only the release app's bundle ids may become a Login Item, and each SMAppService status
// reads as the word the game expects. Run by test.sh.
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static int failures = 0;

static void check(int condition, const char *message) {
	if (!condition) {
		fprintf(stderr, "FAIL native: %s\n", message);
		failures++;
	}
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: test_login_item <dylib>\n");
		return 2;
	}
	void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (lib == NULL) {
		fprintf(stderr, "FAIL native: cannot load %s: %s\n", argv[1], dlerror());
		return 1;
	}
	int (*ours)(const char *) = (int (*)(const char *))dlsym(lib, "vibenature_login_item_bundle_is_ours");
	const char *(*name)(long, int) = (const char *(*)(long, int))dlsym(lib, "vibenature_login_item_state_name");
	check(ours != NULL && name != NULL, "the extension exports its login item checks");
	if (ours == NULL || name == NULL) {
		return 1;
	}
	check(ours("dev.vibenature.app"), "the release app may open at login");
	check(ours("dev.vibenature.app.demo"), "the demo may open at login");
	check(!ours("org.godotengine.godot"), "Godot's own app (a dev run) never becomes a Login Item");
	check(!ours("dev.vibenature.application"), "a look-alike id is not ours");
	check(!ours(NULL) && !ours(""), "no bundle id: not ours");
	check(strcmp(name(1, 1), "enabled") == 0, "Enabled reads enabled");
	check(strcmp(name(0, 1), "off") == 0, "NotRegistered reads off");
	check(strcmp(name(3, 1), "off") == 0, "NotFound reads off");
	check(strcmp(name(2, 1), "approval") == 0, "RequiresApproval reads approval");
	check(strcmp(name(1, 0), "unavailable") == 0, "not the release app: unavailable whatever the status");
	check(strcmp(name(-1, 1), "unavailable") == 0, "an unknown status: unavailable");
	if (failures == 0) {
		printf("native login item: ok\n");
	}
	return failures == 0 ? 0 : 1;
}
