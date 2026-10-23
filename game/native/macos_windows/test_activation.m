// Checks that the extension never changes which app is active and that SIGTERM quits
// cleanly (Skypatch issue 50). No window, no
// NSApplication, and nothing is ever activated: the replaced methods are called directly on
// nil or on a stand-in GodotApplication. Run by test.sh.
#import <Cocoa/Cocoa.h>
#include <dlfcn.h>
#include <objc/runtime.h>
#include <signal.h>
#include <stdio.h>
#include <unistd.h>

static int failures = 0;
static int godot_activations = 0;
static int quits = 0;

static void check(int condition, const char *message) {
	if (!condition) {
		fprintf(stderr, "FAIL native: %s\n", message);
		failures++;
	}
}

// Stands in for Godot's own class: the extension replaces these methods by name.
@interface GodotApplication : NSObject
- (void)activateApplication;
- (void)forceUnbundledWindowActivationHackStep1;
- (void)forceUnbundledWindowActivationHackStep2;
- (void)forceUnbundledWindowActivationHackStep3;
@end

@implementation GodotApplication
- (void)activateApplication {
	godot_activations++;
}
- (void)forceUnbundledWindowActivationHackStep1 {
	godot_activations++;
}
- (void)forceUnbundledWindowActivationHackStep2 {
	godot_activations++;
}
- (void)forceUnbundledWindowActivationHackStep3 {
	godot_activations++;
}
@end

static void quit(void) {
	quits++;
}

int main(int argc, char **argv) {
	if (argc < 2) {
		fprintf(stderr, "usage: test_activation <dylib>\n");
		return 2;
	}
	@autoreleasepool {
		SEL run_activate = @selector(activateWithOptions:);
		SEL app_activate = @selector(activateIgnoringOtherApps:);
		IMP run_before = class_getMethodImplementation([NSRunningApplication class], run_activate);
		IMP app_before = class_getMethodImplementation([NSApplication class], app_activate);
		IMP attention_before = class_getMethodImplementation([NSApplication class], @selector(requestUserAttention:));

		void *lib = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
		if (lib == NULL) {
			fprintf(stderr, "FAIL native: cannot load %s: %s\n", argv[1], dlerror());
			return 1;
		}
		void (*never_activate)(void) = (void (*)(void))dlsym(lib, "vibenature_never_activate");
		void (*quit_on_sigterm)(void (*)(void)) = (void (*)(void (*)(void)))dlsym(lib, "vibenature_quit_on_sigterm");
		int (*sigterm_is_ours)(void) = (int (*)(void))dlsym(lib, "vibenature_sigterm_is_ours");
		check(never_activate != NULL && quit_on_sigterm != NULL && sigterm_is_ours != NULL,
				"the extension exports its activation and SIGTERM hooks");
		if (never_activate == NULL || quit_on_sigterm == NULL || sigterm_is_ours == NULL) {
			return 1;
		}

		never_activate();
		GodotApplication *godot = [[GodotApplication alloc] init];
		[godot activateApplication];
		[godot forceUnbundledWindowActivationHackStep1];
		[godot forceUnbundledWindowActivationHackStep2];
		[godot forceUnbundledWindowActivationHackStep3];
		check(godot_activations == 0,
				"Godot's activateApplication and its unbundled activation hack (SystemUIServer, then itself) do nothing");
		[godot release];

		IMP run_after = class_getMethodImplementation([NSRunningApplication class], run_activate);
		IMP app_after = class_getMethodImplementation([NSApplication class], app_activate);
		check(run_after != run_before, "NSRunningApplication activateWithOptions: is replaced");
		check(app_after != app_before, "NSApplication activateIgnoringOtherApps: is replaced");
		// Called on nil: the replacement never looks at its receiver, so nothing can activate.
		BOOL activated = ((BOOL(*)(id, SEL, NSApplicationActivationOptions))run_after)(nil, run_activate, 0);
		check(!activated, "activating any app from inside VibeNature does nothing");
		// Issue 196: a launch at login is quiet; nothing ever bounces in the Dock.
		SEL attention = @selector(requestUserAttention:);
		IMP attention_after = class_getMethodImplementation([NSApplication class], attention);
		check(attention_after != attention_before, "NSApplication requestUserAttention: is replaced");
		NSInteger request = ((NSInteger(*)(id, SEL, NSRequestUserAttentionType))attention_after)(nil, attention,
				NSCriticalRequest);
		check(request == 0, "asking for attention does nothing (no Dock bounce)");

		quit_on_sigterm(quit);
		check(sigterm_is_ours(), "SIGTERM is taken by the extension");
		kill(getpid(), SIGTERM);
		for (int i = 0; i < 100 && quits == 0; i++) {
			CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, true);
		}
		check(quits == 1, "SIGTERM asks the app to quit (the process is still here to do it)");
	}
	if (failures == 0) {
		printf("native: never activates, SIGTERM quits cleanly\n");
	}
	return failures == 0 ? 0 : 1;
}
