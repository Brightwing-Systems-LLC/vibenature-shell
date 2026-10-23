// Checks the day signals the extension publishes for the daily rhythm
// (issue 198): one count per kind (sleep,
// wake, lock, unlock) in VIBENATURE_MAC_SIGNALS, and nothing else. Run by test.sh.
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
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
		fprintf(stderr, "usage: test_day_signals <dylib>\n");
		return 2;
	}
	void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (lib == NULL) {
		fprintf(stderr, "FAIL native: cannot load %s: %s\n", argv[1], dlerror());
		return 1;
	}
	void (*signal_)(int) = (void (*)(int))dlsym(lib, "vibenature_day_signal");
	check(signal_ != NULL, "the extension exports its day signal");
	if (signal_ == NULL) {
		return 1;
	}
	signal_(0);
	signal_(1);
	signal_(1);
	signal_(2);
	signal_(9);
	signal_(-1);
	const char *value = getenv("VIBENATURE_MAC_SIGNALS");
	check(value != NULL && strcmp(value, "1 2 1 0") == 0, "counts: one sleep, two wakes, one lock, no unlock; unknown kinds ignored");
	signal_(3);
	value = getenv("VIBENATURE_MAC_SIGNALS");
	check(value != NULL && strcmp(value, "1 2 1 1") == 0, "an unlock counts");
	if (failures == 0) {
		printf("native day signals: ok\n");
	}
	return failures == 0 ? 0 : 1;
}
