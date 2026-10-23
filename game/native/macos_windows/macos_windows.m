// VibeNature's macOS window behaviour, which Godot has no flag for:
//  - clicking a window never activates the app, and nothing in the app ever changes which
//    app is active, its own or another's (SPEC §2.1, issue 50);
//  - SIGTERM quits cleanly, like the Dock menu's Quit;
//  - every window joins all Spaces; it shows over other apps' full-screen Spaces only when
//    the player turns that on (display.show_over_full_screen, off by default, issue 50);
//  - the Mac's sleep, wake, lock and unlock, as counts only, for the daily rhythm (issue 198);
//  - the seconds since the last input, that one number only, for the start of the day (issue 431);
//  - open at login (issue 196): the app's own Login Item through SMAppService, in the release app only;
//  - it never asks for attention, so nothing bounces in the Dock (a launch at login stays quiet).
// It applies itself to every window Godot creates; there is nothing to call.
// Public API only (AppKit and the Objective-C runtime), so it is App Store safe.
//
// Snapshot mode (VIBENATURE_SNAPSHOT=1 or the argument --vibenature-snapshot, `just snap`): agents run the real game on the
// player's Mac while they play something full screen, so nothing may show or take input.
// The activation policy is Prohibited from the start (no Dock icon, no activation, no
// window ordered on screen), every window is transparent, ignores the mouse and is created
// far off screen, and the Spaces / full-screen behaviour is not applied.
//
// Built WITHOUT ARC (-fno-objc-arc). The replacement allocWithZone: and initWithContentRect:
// must hand back exactly what they get (+1, as alloc/init promise); ARC would treat a
// block's result as +0 and release a window AppKit still uses, which crashes when the
// first window created after launch (the tool rack) is freed under it.

#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#include <objc/runtime.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// The slice of Godot's gdextension_interface.h this library needs.
typedef uint8_t GDExtensionBool;
typedef void *GDExtensionClassLibraryPtr;
typedef void (*GDExtensionInterfaceFunctionPtr)(void);
typedef GDExtensionInterfaceFunctionPtr (*GDExtensionInterfaceGetProcAddress)(const char *p_function_name);
typedef enum {
	GDEXTENSION_INITIALIZATION_CORE = 0,
	GDEXTENSION_INITIALIZATION_SERVERS = 1,
	GDEXTENSION_INITIALIZATION_SCENE = 2,
} GDExtensionInitializationLevel;
typedef struct {
	GDExtensionInitializationLevel minimum_initialization_level;
	void *userdata;
	void (*initialize)(void *p_userdata, GDExtensionInitializationLevel p_level);
	void (*deinitialize)(void *p_userdata, GDExtensionInitializationLevel p_level);
} GDExtensionInitialization;

// The bits this library owns on every window.
static const NSWindowCollectionBehavior kManaged = NSWindowCollectionBehaviorCanJoinAllSpaces |
		NSWindowCollectionBehaviorFullScreenAuxiliary | NSWindowCollectionBehaviorStationary |
		NSWindowCollectionBehaviorIgnoresCycle | NSWindowCollectionBehaviorMoveToActiveSpace;

// A window over another app's full-screen Space sits on top of that app (a game, say) and
// takes its mouse wherever the window's click shape is: Godot turns click-through off while
// the cursor is over an island, so clicks, drags and cursor updates go to VibeNature instead
// (Skypatch issue 50). So FullScreenAuxiliary is
// only added when the game says the player asked for it, through this variable ("1").
static const char *kShowOverFullScreenEnv = "VIBENATURE_SHOW_OVER_FULL_SCREEN";

__attribute__((visibility("default"))) int vibenature_show_over_full_screen(void) {
	const char *value = getenv(kShowOverFullScreenEnv);
	return value != NULL && strcmp(value, "1") == 0;
}

// The collection behaviour every window gets, exported so a test can check the flags for
// each setting without a window.
__attribute__((visibility("default"))) unsigned long vibenature_collection_behaviour(int over_full_screen) {
	NSWindowCollectionBehavior behaviour = NSWindowCollectionBehaviorCanJoinAllSpaces |
			NSWindowCollectionBehaviorStationary | NSWindowCollectionBehaviorIgnoresCycle;
	if (over_full_screen) {
		behaviour |= NSWindowCollectionBehaviorFullScreenAuxiliary;
	}
	return (unsigned long)behaviour;
}

static id window_observer = nil;
static id space_observer = nil;
static BOOL snapshot_mode = NO;
static id snapshot_activity = nil;
// Far outside every screen, in points.
static const CGFloat kSnapshotOrigin = -20000.0;

// `just snap` looks for this symbol before it launches anything: a library built before
// snapshot mode existed would put windows on the player's screen.
__attribute__((visibility("default"))) int vibenature_snapshot_mode_supported(void) {
	return 1;
}

// A non-activating NSPanel is the public way to take clicks without activating the
// app, and AppKit only honours it for a window *created* as one. Godot creates
// GodotWindows (NSWindow subclasses), so this builds an NSPanel subclass with
// GodotWindow's instance variables at the same offsets and its methods, and makes
// allocating a GodotWindow allocate one of those instead. If the layout ever stops
// matching, nothing is changed and clicks fall back to activating the app.
// The windows that carry flying things (birds crossing the desktop) float above every
// normal window, and above the patches when those are on top (NSFloatingWindowLevel), but
// under the menu bar (issue 235).
// Godot has no window levels, so they are recognised by one exact title: the same string
// as TransitWindow.OVERLAY_TITLE in game/scripts/transit_window.gd (test.sh checks both).
static NSString *const kOverlayTitle = @"VibeNature · overlay";
static const NSWindowLevel kOverlayLevel = NSFloatingWindowLevel + 1;

__attribute__((visibility("default"))) int vibenature_is_overlay_title(const char *title) {
	return title != NULL && [[NSString stringWithUTF8String:title] isEqualToString:kOverlayTitle];
}

__attribute__((visibility("default"))) long vibenature_overlay_level(void) {
	return (long)kOverlayLevel;
}

static BOOL is_overlay(NSWindow *window) {
	return [window.title isEqualToString:kOverlayTitle];
}

// Every VibeNature window is borderless and non-activating. Godot gives a window that
// was hidden and is shown again a title bar (the held tool, the tool rack), so the
// frame bits are taken out whenever the style is set.
static NSWindowStyleMask vibenature_style(NSWindowStyleMask mask) {
	NSWindowStyleMask frame = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
			NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
	return (mask & ~frame) | NSWindowStyleMaskNonactivatingPanel;
}

static Class build_panel_class(Class window_class) {
	if (class_getSuperclass(window_class) != [NSWindow class] ||
			class_getInstanceSize([NSPanel class]) != class_getInstanceSize([NSWindow class])) {
		return Nil;
	}
	NSString *name = [NSString stringWithFormat:@"VibeNature%sPanel", class_getName(window_class)];
	Class panel = objc_allocateClassPair([NSPanel class], name.UTF8String, 0);
	if (panel == Nil) {
		return Nil;
	}
	unsigned count = 0;
	Ivar *ivars = class_copyIvarList(window_class, &count);
	for (unsigned i = 0; i < count; i++) {
		NSUInteger size = 0, alignment = 0;
		NSGetSizeAndAlignment(ivar_getTypeEncoding(ivars[i]), &size, &alignment);
		// The compiler starts a subclass's ivars on an 8-byte boundary after
		// NSWindow's; the runtime would pack the first one tighter.
		if (i == 0) {
			alignment = MAX(alignment, 8);
		}
		class_addIvar(panel, ivar_getName(ivars[i]), size, (uint8_t)log2(alignment), ivar_getTypeEncoding(ivars[i]));
	}
	objc_registerClassPair(panel);
	BOOL same_layout = class_getInstanceSize(panel) == class_getInstanceSize(window_class);
	for (unsigned i = 0; i < count && same_layout; i++) {
		Ivar copy = class_getInstanceVariable(panel, ivar_getName(ivars[i]));
		same_layout = copy != NULL && ivar_getOffset(copy) == ivar_getOffset(ivars[i]);
	}
	free(ivars);
	if (!same_layout) {
		fprintf(stderr, "VibeNature native: %s layout differs from NSPanel's; clicks will activate the app\n",
				class_getName(window_class));
		return Nil;
	}

	Method *methods = class_copyMethodList(window_class, &count);
	for (unsigned i = 0; i < count; i++) {
		class_addMethod(panel, method_getName(methods[i]), method_getImplementation(methods[i]),
				method_getTypeEncoding(methods[i]));
	}
	free(methods);

	// Created non-activating, and kept that way when Godot changes the style mask.
	SEL init_sel = @selector(initWithContentRect:styleMask:backing:defer:);
	typedef id (*InitIMP)(id, SEL, NSRect, NSWindowStyleMask, NSBackingStoreType, BOOL);
	InitIMP panel_init = (InitIMP)class_getMethodImplementation([NSPanel class], init_sel);
	class_addMethod(panel, init_sel,
			imp_implementationWithBlock(^id(id self, NSRect rect, NSWindowStyleMask mask, NSBackingStoreType backing, BOOL defer) {
				if (snapshot_mode) {
					rect.origin = NSMakePoint(kSnapshotOrigin, kSnapshotOrigin);
				}
				id window = panel_init(self, init_sel, rect, vibenature_style(mask), backing, defer);
				if (snapshot_mode && window != nil) {
					[(NSWindow *)window setAlphaValue:0.0];
					[(NSWindow *)window setIgnoresMouseEvents:YES];
				}
				return window;
			}),
			method_getTypeEncoding(class_getInstanceMethod([NSPanel class], init_sel)));
	// Whatever level Godot asks for (it sets one when showing an on-top window), the
	// overlay windows keep exactly the overlay level.
	SEL level_sel = @selector(setLevel:);
	typedef void (*LevelIMP)(id, SEL, NSWindowLevel);
	LevelIMP panel_set_level = (LevelIMP)class_getMethodImplementation([NSPanel class], level_sel);
	class_addMethod(panel, level_sel,
			imp_implementationWithBlock(^(id self, NSWindowLevel level) {
				if (is_overlay(self)) {
					level = kOverlayLevel;
				}
				panel_set_level(self, level_sel, level);
			}),
			method_getTypeEncoding(class_getInstanceMethod([NSPanel class], level_sel)));
	SEL mask_sel = @selector(setStyleMask:);
	typedef void (*MaskIMP)(id, SEL, NSWindowStyleMask);
	MaskIMP panel_set_mask = (MaskIMP)class_getMethodImplementation([NSPanel class], mask_sel);
	class_addMethod(panel, mask_sel,
			imp_implementationWithBlock(^(id self, NSWindowStyleMask mask) {
				panel_set_mask(self, mask_sel, vibenature_style(mask));
			}),
			method_getTypeEncoding(class_getInstanceMethod([NSPanel class], mask_sel)));
	if (snapshot_mode) {
		// Godot sets these for transparency and click-through; in snapshot mode a window
		// stays invisible and never takes a click, whatever it asks for.
		SEL alpha_sel = @selector(setAlphaValue:);
		typedef void (*AlphaIMP)(id, SEL, CGFloat);
		AlphaIMP panel_set_alpha = (AlphaIMP)class_getMethodImplementation([NSPanel class], alpha_sel);
		class_addMethod(panel, alpha_sel,
				imp_implementationWithBlock(^(id self, CGFloat alpha) {
					panel_set_alpha(self, alpha_sel, 0.0);
				}),
				method_getTypeEncoding(class_getInstanceMethod([NSPanel class], alpha_sel)));
		SEL ignores_sel = @selector(setIgnoresMouseEvents:);
		typedef void (*IgnoresIMP)(id, SEL, BOOL);
		IgnoresIMP panel_set_ignores = (IgnoresIMP)class_getMethodImplementation([NSPanel class], ignores_sel);
		class_addMethod(panel, ignores_sel,
				imp_implementationWithBlock(^(id self, BOOL ignores) {
					panel_set_ignores(self, ignores_sel, YES);
				}),
				method_getTypeEncoding(class_getInstanceMethod([NSPanel class], ignores_sel)));
	}
	return panel;
}

// Snapshot mode: Prohibited from now on, whatever Godot asks for. A Prohibited app has no
// Dock icon, cannot become active and never orders a window on screen. App Nap would slow
// the timers of an app with no visible window, so the run holds an activity.
static void snapshot_never_shows(void) {
	SEL policy_sel = @selector(setActivationPolicy:);
	Method method = class_getInstanceMethod([NSApplication class], policy_sel);
	typedef BOOL (*PolicyIMP)(id, SEL, NSApplicationActivationPolicy);
	PolicyIMP original = (PolicyIMP)method_getImplementation(method);
	method_setImplementation(method, imp_implementationWithBlock(^BOOL(id self, NSApplicationActivationPolicy policy) {
		return original(self, policy_sel, NSApplicationActivationPolicyProhibited);
	}));
	[[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyProhibited];
	snapshot_activity = [[[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
			reason:@"VibeNature snapshot run"] retain];
	fprintf(stderr, "VibeNature native: snapshot mode: no window is shown, nothing activates\n");
}

static void allocate_godot_windows_as_panels(void) {
	Class godot_window = NSClassFromString(@"GodotWindow");
	if (godot_window == Nil) {
		fprintf(stderr, "VibeNature native: no GodotWindow class; clicks will activate the app\n");
		return;
	}
	Class panel = build_panel_class(godot_window);
	if (panel == Nil) {
		return;
	}
	SEL alloc_sel = @selector(allocWithZone:);
	Method original = class_getClassMethod(godot_window, alloc_sel);
	IMP original_alloc = method_getImplementation(original);
	class_addMethod(object_getClass(godot_window), alloc_sel,
			imp_implementationWithBlock(^id(Class cls, NSZone *zone) {
				if (cls == godot_window) {
					return [panel allocWithZone:zone];
				}
				return ((id(*)(Class, SEL, NSZone *))original_alloc)(cls, alloc_sel, zone);
			}),
			method_getTypeEncoding(original));
}

// VibeNature never changes which app is active: not its own, not anyone else's
// (Skypatch issue 50). It has nothing to type into,
// and every activation change reaches the player's app: a game that holds the mouse (World
// of Warcraft, for one) lets go of it on deactivation and can come back without it.
//
// Godot activates the app whenever the root window is shown (-[GodotApplication
// activateApplication]). Started from a shell, as `godot --path game` is, that also runs
// Godot's "unbundled activation hack" 20, 40 and 60 ms later: it activates SystemUIServer,
// then TransformProcessType, then activates the app again, all through NSRunningApplication,
// which the old NSApplication-only block did not cover. The extension used to answer that
// last activation by activating the previous app again: three activation changes in the
// player's game within about 60 ms, at every launch. Now none of them happen:
//  - NSApplication's activate / activateIgnoringOtherApps: do nothing;
//  - GodotApplication's activateApplication and the three hack steps do nothing;
//  - NSRunningApplication's activateWithOptions: / activateFromApplication:options: do
//    nothing for any app (nothing in VibeNature has a reason to switch apps).
// The system can still activate VibeNature (a Dock click, Cmd-Tab, a Finder launch): the
// player asked for it, and nothing is handed anywhere afterwards.
static void neuter(Class cls, SEL sel, id block) {
	if (cls == Nil) {
		return;
	}
	Method method = class_getInstanceMethod(cls, sel);
	if (method == NULL) {
		return;
	}
	// Only methods the class itself defines, so an inherited one is never replaced on the
	// superclass by accident.
	if (!class_addMethod(cls, sel, imp_implementationWithBlock(block), method_getTypeEncoding(method))) {
		method_setImplementation(method, imp_implementationWithBlock(block));
	}
}

static BOOL never_activates = NO;

__attribute__((visibility("default"))) void vibenature_never_activate(void) {
	if (never_activates) {
		return;
	}
	never_activates = YES;
	neuter([NSApplication class], @selector(activateIgnoringOtherApps:), ^(id self, BOOL flag) {
	});
	neuter([NSApplication class], NSSelectorFromString(@"activate"), ^(id self) {
	});
	Class godot_app = NSClassFromString(@"GodotApplication");
	for (NSString *name in @[ @"activateApplication", @"forceUnbundledWindowActivationHackStep1",
				 @"forceUnbundledWindowActivationHackStep2", @"forceUnbundledWindowActivationHackStep3" ]) {
		neuter(godot_app, NSSelectorFromString(name), ^(id self) {
		});
	}
	// Nothing bounces in the Dock or asks to be looked at: not at launch (a launch at login is quiet), not ever.
	neuter([NSApplication class], @selector(requestUserAttention:), ^NSInteger(id self, NSRequestUserAttentionType type) {
		return 0;
	});
	neuter([NSApplication class], @selector(cancelUserAttentionRequest:), ^(id self, NSInteger request) {
	});
	neuter([NSRunningApplication class], @selector(activateWithOptions:),
			^BOOL(id self, NSApplicationActivationOptions options) {
				return NO;
			});
	neuter([NSRunningApplication class], NSSelectorFromString(@"activateFromApplication:options:"),
			^BOOL(id self, id from, NSApplicationActivationOptions options) {
				return NO;
			});
}

// SIGTERM (`kill`, `just stop`, a timeout) quits like the Dock menu's Quit: Godot gets a
// close request, the game saves, and the app exits normally. Without this the .NET runtime
// in Godot's mono build handles SIGTERM by exiting from another thread while the main thread
// still runs the engine, which crashed and left a "Problem Report for godot" dialog on the
// player's screen (issue 50). A second SIGTERM, or one before the app can take a close
// request (headless), ends the process the default way.
static dispatch_source_t sigterm_source = nil;
static void (*sigterm_quit)(void) = NULL;
static int sigterm_count = 0;

static void default_sigterm(void) {
	signal(SIGTERM, SIG_DFL);
	raise(SIGTERM);
}

__attribute__((visibility("default"))) void vibenature_quit_on_sigterm(void (*quit)(void)) {
	sigterm_quit = quit;
	signal(SIGTERM, SIG_IGN);
	if (sigterm_source != nil) {
		return;
	}
	sigterm_source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGTERM, 0, dispatch_get_main_queue());
	dispatch_source_set_event_handler(sigterm_source, ^{
		sigterm_count += (int)dispatch_source_get_data(sigterm_source);
		if (sigterm_count > 1 || sigterm_quit == NULL) {
			default_sigterm();
			return;
		}
		sigterm_quit();
	});
	dispatch_resume(sigterm_source);
}

// Whether SIGTERM is still VibeNature's (ignored by the default handler, taken by the dispatch
// source); something loaded later, such as the .NET runtime, may install its own.
__attribute__((visibility("default"))) int vibenature_sigterm_is_ours(void) {
	struct sigaction current;
	return sigterm_source != nil && sigaction(SIGTERM, NULL, &current) == 0 && current.sa_handler == SIG_IGN;
}

static void quit_like_the_dock(void) {
	NSApplication *app = NSApp;
	if (app != nil && [app.delegate respondsToSelector:@selector(applicationShouldTerminate:)]) {
		fprintf(stderr, "VibeNature native: SIGTERM: quitting cleanly\n");
		[app terminate:nil];
		return;
	}
	default_sigterm();
}

static void keep_sigterm(const char *when) {
	if (!vibenature_sigterm_is_ours()) {
		vibenature_quit_on_sigterm(quit_like_the_dock);
		fprintf(stderr, "VibeNature native: took SIGTERM back (%s) from a handler installed after launch\n", when);
	}
}

static void apply_to_window(NSWindow *window) {
	if (is_overlay(window) && window.level != kOverlayLevel) {
		window.level = kOverlayLevel;
	}
	int over_full_screen = vibenature_show_over_full_screen();
	NSWindowCollectionBehavior wanted = vibenature_collection_behaviour(over_full_screen);
	if ((window.collectionBehavior & kManaged) != wanted) {
		window.collectionBehavior = (window.collectionBehavior & ~kManaged) | wanted;
		window.hidesOnDeactivate = NO;
		fprintf(stderr, "VibeNature native: \"%s\" joins all Spaces, %s full screen%s\n",
				window.title.UTF8String, over_full_screen ? "shows over" : "stays off other apps'",
				(window.styleMask & NSWindowStyleMaskNonactivatingPanel) ? ", never activates" : "");
	}
}

static void apply_to_app(void) {
	for (NSWindow *window in NSApp.windows) {
		apply_to_window(window);
	}
}

// The Mac's day signals for the daily rhythm (issue 198):
// that it slept, woke, locked or unlocked, and nothing else. No time, no app, no user, no
// screen content is read; the notifications carry nothing more and their payloads are never
// looked at. Each kind is a running count, published as one environment variable the game
// polls ("<sleeps> <wakes> <locks> <unlocks>"): a count rather than an event, so a poll that
// comes after both a sleep and a wake still sees both.
static const char *kDaySignalsEnv = "VIBENATURE_MAC_SIGNALS";
static unsigned long day_signal_counts[4] = {0, 0, 0, 0};
static id day_sleep_observer = nil;
static id day_wake_observer = nil;
static id day_lock_observer = nil;
static id day_unlock_observer = nil;

// 0 sleep, 1 wake, 2 lock, 3 unlock. Exported so a test can drive it without a Mac to lock.
__attribute__((visibility("default"))) void vibenature_day_signal(int kind) {
	if (kind < 0 || kind > 3) {
		return;
	}
	day_signal_counts[kind]++;
	char value[96];
	snprintf(value, sizeof(value), "%lu %lu %lu %lu", day_signal_counts[0], day_signal_counts[1],
			day_signal_counts[2], day_signal_counts[3]);
	setenv(kDaySignalsEnv, value, 1);
}

static id observe_day_signal(NSNotificationCenter *center, NSString *name, int kind) {
	return [[center addObserverForName:name
								object:nil
								 queue:[NSOperationQueue mainQueue]
							usingBlock:^(NSNotification *note) {
								vibenature_day_signal(kind);
							}] retain];
}

static void start_day_signals(void) {
	setenv(kDaySignalsEnv, "0 0 0 0", 1);
	NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
	day_sleep_observer = observe_day_signal(workspace, NSWorkspaceWillSleepNotification, 0);
	day_wake_observer = observe_day_signal(workspace, NSWorkspaceDidWakeNotification, 1);
	// The screen lock has no public AppKit name; these distributed notifications are what the
	// system posts on locking and unlocking, with no payload read.
	NSDistributedNotificationCenter *distributed = [NSDistributedNotificationCenter defaultCenter];
	day_lock_observer = observe_day_signal(distributed, @"com.apple.screenIsLocked", 2);
	day_unlock_observer = observe_day_signal(distributed, @"com.apple.screenIsUnlocked", 3);
}

static void forget_day_signal(NSNotificationCenter *center, id *observer) {
	if (*observer != nil) {
		[center removeObserver:*observer];
		[*observer release];
		*observer = nil;
	}
}

static void stop_day_signals(void) {
	NSNotificationCenter *workspace = NSWorkspace.sharedWorkspace.notificationCenter;
	NSDistributedNotificationCenter *distributed = [NSDistributedNotificationCenter defaultCenter];
	forget_day_signal(workspace, &day_sleep_observer);
	forget_day_signal(workspace, &day_wake_observer);
	forget_day_signal(distributed, &day_lock_observer);
	forget_day_signal(distributed, &day_unlock_observer);
}

// Presence for the start of the day (issue 431): whether
// someone is at this Mac, as the system's own seconds since the last keyboard or mouse input, and nothing else.
// No key, character, button, position, window or app is read, and there is no event tap: the call returns one
// number, published as whole seconds in one environment variable the game polls (VIBENATURE_IDLE_SEC).
static const char *kIdleEnv = "VIBENATURE_IDLE_SEC";
static const uint64_t kIdlePollSec = 2;
static dispatch_source_t idle_timer = nil;

// Whole seconds since the last input of any kind, or -1 when the system cannot say. Exported for the test.
__attribute__((visibility("default"))) long vibenature_idle_seconds(void) {
	CFTimeInterval seconds = CGEventSourceSecondsSinceLastEventType(kCGEventSourceStateCombinedSessionState, kCGAnyInputEventType);
	if (!(seconds >= 0.0)) {
		return -1;
	}
	return seconds > 1.0e9 ? 1000000000L : (long)seconds;
}

__attribute__((visibility("default"))) void vibenature_publish_idle(void) {
	char value[24];
	snprintf(value, sizeof(value), "%ld", vibenature_idle_seconds());
	setenv(kIdleEnv, value, 1);
}

static void start_idle(void) {
	vibenature_publish_idle();
	idle_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	dispatch_source_set_timer(idle_timer, dispatch_time(DISPATCH_TIME_NOW, kIdlePollSec * NSEC_PER_SEC),
			kIdlePollSec * NSEC_PER_SEC, NSEC_PER_SEC / 2);
	dispatch_source_set_event_handler(idle_timer, ^{
		vibenature_publish_idle();
	});
	dispatch_resume(idle_timer);
}

static void stop_idle(void) {
	if (idle_timer != nil) {
		dispatch_source_cancel(idle_timer);
		dispatch_release(idle_timer);
		idle_timer = nil;
	}
}

// Open at login (issue 196): the app registers itself as
// its own Login Item (SMAppService.mainApp, macOS 13 and later). Only the release app does, recognised by its
// bundle id: a dev run is Godot's own app, which must never become a Login Item. The game asks through one
// environment variable (VIBENATURE_LOGIN_ITEM_WANT, "on" or "off", from Config's General switch and the welcome)
// and reads the system's state from another (VIBENATURE_LOGIN_ITEM: "enabled", "off", "approval" or
// "unavailable"), refreshed every few seconds, so a change made in System Settings shows in Config.
static const char *kLoginItemEnv = "VIBENATURE_LOGIN_ITEM";
static const char *kLoginItemWantEnv = "VIBENATURE_LOGIN_ITEM_WANT";
static NSString *const kReleaseBundleId = @"dev.vibenature.app";
static const uint64_t kLoginItemPollSec = 3;
static const int kLoginItemRefreshTicks = 4;
static dispatch_source_t login_item_timer = nil;
static char login_item_applied[8] = "";
static int login_item_ticks = 0;

// The release app (dev.vibenature.app) and its demo (dev.vibenature.app.demo); nothing else.
__attribute__((visibility("default"))) int vibenature_login_item_bundle_is_ours(const char *bundle_id) {
	if (bundle_id == NULL) {
		return 0;
	}
	NSString *id_ = [NSString stringWithUTF8String:bundle_id];
	return [id_ isEqualToString:kReleaseBundleId] ||
			[id_ hasPrefix:[kReleaseBundleId stringByAppendingString:@"."]];
}

// SMAppServiceStatus as the game's word for it. Exported so a test can check every value without registering.
__attribute__((visibility("default"))) const char *vibenature_login_item_state_name(long status, int ours) {
	if (!ours) {
		return "unavailable";
	}
	switch (status) {
		case 1: // SMAppServiceStatusEnabled
			return "enabled";
		case 2: // SMAppServiceStatusRequiresApproval: switched off in System Settings, or waiting for the person
			return "approval";
		case 0: // SMAppServiceStatusNotRegistered
		case 3: // SMAppServiceStatusNotFound
			return "off";
		default:
			return "unavailable";
	}
}

// A headless run (the release smoke check, a test) or VIBENATURE_NO_LOGIN_ITEM never touches the person's Login Items.
static const char *kNoLoginItemEnv = "VIBENATURE_NO_LOGIN_ITEM";

static int login_item_available(void) {
	const char *off = getenv(kNoLoginItemEnv);
	if ((off != NULL && off[0] != '\0' && strcmp(off, "0") != 0) ||
			[[[NSProcessInfo processInfo] arguments] containsObject:@"--headless"]) {
		return 0;
	}
	if (@available(macOS 13.0, *)) {
		return vibenature_login_item_bundle_is_ours(NSBundle.mainBundle.bundleIdentifier.UTF8String);
	}
	return 0;
}

static void publish_login_item(void) {
	long status = -1;
	int ours = login_item_available();
	if (ours) {
		if (@available(macOS 13.0, *)) {
			status = (long)SMAppService.mainAppService.status;
		}
	}
	setenv(kLoginItemEnv, vibenature_login_item_state_name(status, ours), 1);
}

static void apply_login_item(const char *want) {
	if (@available(macOS 13.0, *)) {
		NSError *error = nil;
		BOOL on = strcmp(want, "on") == 0;
		SMAppService *service = SMAppService.mainAppService;
		BOOL done = on ? [service registerAndReturnError:&error] : [service unregisterAndReturnError:&error];
		if (!done) {
			// Unregistering what was never registered is not worth a line.
			if (on || service.status != SMAppServiceStatusNotRegistered) {
				fprintf(stderr, "VibeNature native: open at login %s failed (%ld)\n", on ? "on" : "off",
						(long)error.code);
			}
		} else {
			fprintf(stderr, "VibeNature native: open at login %s\n", on ? "on" : "off");
		}
	}
}

static void login_item_tick(void) {
	const char *want = getenv(kLoginItemWantEnv);
	BOOL asked = want != NULL && (strcmp(want, "on") == 0 || strcmp(want, "off") == 0);
	if (asked && strcmp(want, login_item_applied) != 0 && login_item_available()) {
		snprintf(login_item_applied, sizeof(login_item_applied), "%s", want);
		apply_login_item(want);
		login_item_ticks = 0;
	}
	if (login_item_ticks++ % kLoginItemRefreshTicks == 0) {
		publish_login_item();
	}
}

static void start_login_item(void) {
	publish_login_item();
	if (!login_item_available()) {
		return;
	}
	login_item_timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
	dispatch_source_set_timer(login_item_timer, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC),
			kLoginItemPollSec * NSEC_PER_SEC, NSEC_PER_SEC);
	dispatch_source_set_event_handler(login_item_timer, ^{
		login_item_tick();
	});
	dispatch_resume(login_item_timer);
}

static void stop_login_item(void) {
	if (login_item_timer != nil) {
		dispatch_source_cancel(login_item_timer);
		dispatch_release(login_item_timer);
		login_item_timer = nil;
	}
}

static void initialize(void *userdata, GDExtensionInitializationLevel level) {
	if (level == GDEXTENSION_INITIALIZATION_CORE) {
		// Before Godot creates its first window or activates itself.
		const char *snapshot = getenv("VIBENATURE_SNAPSHOT");
		snapshot_mode = (snapshot != NULL && snapshot[0] != '\0' && strcmp(snapshot, "0") != 0) ||
				[[[NSProcessInfo processInfo] arguments] containsObject:@"--vibenature-snapshot"];
		if (snapshot_mode) {
			snapshot_never_shows();
		}
		allocate_godot_windows_as_panels();
		vibenature_never_activate();
		vibenature_quit_on_sigterm(quit_like_the_dock);
		return;
	}
	// Snapshot mode leaves out Spaces and full-screen behaviour: no window may join the
	// player's full-screen Space.
	if (level == GDEXTENSION_INITIALIZATION_SCENE) {
		// The .NET runtime in Godot's mono build starts after the core level and may take
		// SIGTERM; checked now and again once the game is running.
		keep_sigterm("scene level");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			keep_sigterm("5 s in");
		});
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
			keep_sigterm("60 s in");
		});
	}
	if (level != GDEXTENSION_INITIALIZATION_SCENE || snapshot_mode) {
		return;
	}
	start_day_signals();
	start_idle();
	start_login_item();
	window_observer = [[[NSNotificationCenter defaultCenter]
			addObserverForName:NSWindowDidChangeOcclusionStateNotification
						object:nil
						 queue:nil
					usingBlock:^(NSNotification *note) {
						apply_to_app();
					}] retain];
	// The setting can change while running; it is read again whenever the player changes
	// Space (entering a full-screen app is one) and whenever a window is shown or hidden.
	space_observer = [[NSWorkspace.sharedWorkspace.notificationCenter
			addObserverForName:NSWorkspaceActiveSpaceDidChangeNotification
						object:nil
						 queue:nil
					usingBlock:^(NSNotification *note) {
						apply_to_app();
					}] retain];
	dispatch_async(dispatch_get_main_queue(), ^{
		apply_to_app();
	});
}

static void deinitialize(void *userdata, GDExtensionInitializationLevel level) {
	if (level == GDEXTENSION_INITIALIZATION_SCENE) {
		stop_day_signals();
		stop_idle();
		stop_login_item();
	}
	if (level == GDEXTENSION_INITIALIZATION_SCENE && window_observer != nil) {
		[[NSNotificationCenter defaultCenter] removeObserver:window_observer];
		[window_observer release];
		window_observer = nil;
	}
	if (level == GDEXTENSION_INITIALIZATION_SCENE && space_observer != nil) {
		[NSWorkspace.sharedWorkspace.notificationCenter removeObserver:space_observer];
		[space_observer release];
		space_observer = nil;
	}
	if (level == GDEXTENSION_INITIALIZATION_CORE) {
		if (snapshot_activity != nil) {
			[[NSProcessInfo processInfo] endActivity:snapshot_activity];
			[snapshot_activity release];
			snapshot_activity = nil;
		}
	}
}

__attribute__((visibility("default"))) GDExtensionBool vibenature_macos_windows_init(
		GDExtensionInterfaceGetProcAddress get_proc_address, GDExtensionClassLibraryPtr library,
		GDExtensionInitialization *r_initialization) {
	r_initialization->minimum_initialization_level = GDEXTENSION_INITIALIZATION_CORE;
	r_initialization->userdata = NULL;
	r_initialization->initialize = initialize;
	r_initialization->deinitialize = deinitialize;
	return 1;
}
