// Checks the presence reading for the start of the day
// (issue 431): the call returns only a number (whole seconds
// since the last input, or -1), and what is published in VIBENATURE_IDLE_SEC is that number and nothing else.
// Run by test.sh.
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

static int only_a_number(const char *value) {
	if (value == NULL || value[0] == '\0' || strlen(value) > 11) {
		return 0;
	}
	const char *c = value[0] == '-' ? value + 1 : value;
	if (*c == '\0') {
		return 0;
	}
	for (; *c != '\0'; c++) {
		if (*c < '0' || *c > '9') {
			return 0;
		}
	}
	return 1;
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: test_presence <dylib>\n");
		return 2;
	}
	void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (lib == NULL) {
		fprintf(stderr, "FAIL native: cannot load %s: %s\n", argv[1], dlerror());
		return 1;
	}
	long (*idle)(void) = (long (*)(void))dlsym(lib, "vibenature_idle_seconds");
	void (*publish)(void) = (void (*)(void))dlsym(lib, "vibenature_publish_idle");
	check(idle != NULL && publish != NULL, "the extension exports its presence reading");
	if (idle == NULL || publish == NULL) {
		return 1;
	}
	long seconds = idle();
	check(seconds >= -1 && seconds <= 1000000000L, "the idle reading is whole seconds, or -1");
	unsetenv("VIBENATURE_IDLE_SEC");
	publish();
	const char *value = getenv("VIBENATURE_IDLE_SEC");
	check(only_a_number(value), "what is published is a number and nothing else");
	if (value != NULL) {
		check(labs(atol(value) - idle()) <= 5, "and it is the idle reading");
	}
	if (failures == 0) {
		printf("native presence: ok (%s s idle)\n", value != NULL ? value : "?");
	}
	return failures == 0 ? 0 : 1;
}
