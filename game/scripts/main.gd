class_name Game
extends Node

## The desktop garden. Home (root window): a bench where the avatar starts and rests, a
## mailbox where results land, a gear sign that opens Config. One window per island, each
## with its mechanic, its tool squares and a ✕ that puts it away; visiting birds; the day's
## weather; the economy, journal and save. The first run opens Config on the Avatar tab.
## The loop: click an island → the avatar poofs there with its default tool →
## pick another tool from the squares if needed → click the spot → the avatar does the job
## → whatever that yields flies to the mailbox.

## Read by the native extension (native/macos_windows): "1" lets windows join other apps'
## full-screen Spaces.
const FULL_SCREEN_ENV := "VIBENATURE_SHOW_OVER_FULL_SCREEN"
## Where `just dev` wants this run's process id, so `just stop` can quit exactly this run.
const PID_FILE_ENV := "VIBENATURE_PID_FILE"
## Written by the native extension: "<sleeps> <wakes> <locks> <unlocks>" (issue 198). Counts only.
const MAC_SIGNALS_ENV := "VIBENATURE_MAC_SIGNALS"
## Written by the native extension: whole seconds since the last keyboard or mouse input, that one number (issue 431).
const IDLE_ENV := "VIBENATURE_IDLE_SEC"

var balance: Balance
var content: Content
var settings: Settings
var clock: GameClock
var signals: WorldSignals
var weather: Weather
var rhythm: Rhythm
## When the van brings you and takes you away (issue 198): fed the busy edges and the Mac's signals.
var day_rhythm: DailyRhythm
## The Mac's day signals as the native extension publishes them (counts: sleep, wake, lock, unlock);
## tests set it to fake them.
var mac_signals_source: Callable = func() -> String: return OS.get_environment(MAC_SIGNALS_ENV)
var _mac_seen: Array = []
## Seconds since the last input as the native extension publishes them (issue 431); "" when there is none. Tests
## fake it. Only ever a number: no key, character, window or app is read anywhere.
var presence_source: Callable = func() -> String: return OS.get_environment(IDLE_ENV)
## The system's open-at-login state as the native extension publishes it (`LoginItem`, issue 196); tests fake it.
var login_item_source: Callable = func() -> String: return OS.get_environment(LoginItem.STATE_ENV)
var _day_poll_at := 0.0
var _day_poll_timer := Timer.new()
## Agent activity in (contract §2): the event server and the sessions it tracks.
var bridge: AgentBridge
## The busy edge just brought the van, so the hand-off that follows it has the arrival as its moment.
var _van_turn := false
var economy: Economy
var journal: Journal
var collection := Collection.new()
var save_game: SaveGame
var rng := RandomNumberGenerator.new()
var scale_px := 2
var idle_fps_max := 4.0
var patches: Array[PatchWindow] = []
## Island packs by id (contract §5): the built-in ones, then any installed and accepted.
var packs: Dictionary = {}
var island_loader: IslandLoader
## Every patch's saved state, including patches not out today: rotating never loses one.
var _states: Dictionary = {}
var home: HomeView
## The living scene in the screen's bottom-right corner (contract §7).
var scene: LivingScene
## Shown instead of everything else when no scene package is installed (issue 487); null otherwise.
var no_scene: NoSceneView
## The scene on its own, with no islands and no home on screen: what `just dev` runs (VIBENATURE_SCENE=1).
var scene_mode := false
var config: ConfigWindow
## Scene mode's own config (issue 169), opened by the strip's ⚙; null in the island game.
var scene_config: SceneConfigWindow
## The book (issue 177), opened by the strip's 📖; null in the island game.
var book: SceneBookWindow
## The person's photos (issue 177; taken by issue 176).
var album: PhotoAlbum
## The last photo taken (its album id), and what reads the scene's render for one (tests set it).
var last_photo := ""
var photo_render: Callable
## Every species seen in the scene, for the book's field guide (kept in the save).
var sightings := SceneSightings.new()
## The elder's letters (issue 213; kept in the save as `letters`).
var letters: ElderLetters
## The first-run welcome (issue 199): pending from launch until it is done or skipped; its window once open.
var welcome_pending := false
var welcome: SceneWelcomeWindow
var _portraits := {}
## Tests turn this off so the strip's ✕ saves without ending the test run.
var exit_on_quit := true
## The Config tab to open again after the scene reloads (a scale change from Config), or -1.
static var _reopen_config := -1
var avatar: Avatar
var _idle_timer := Timer.new()
var courier: Courier
var birds: BirdVisits
var debug_panel: DebugPanel
## The shelf-island prototype, in place of today's islands (VIBENATURE_SHELF_DEMO=1).
var shelf_demo: ShelfDemo


## The demo path that saves screenshots without the screen (`just snap`).
var snapshot: Snapshot
var _textures := {}
var _day_timer := Timer.new()
## The connected screens, for the scene's screen (issue 174): the display server's, or a test's fakes.
var screens_source: Callable = SceneScreens.from_display
var _screen_timer := Timer.new()
var _screens_seen := ""
var _save_timer := Timer.new()
var _quitting := false
## Written into the save only when closing up: the day, and whether it was before dusk.
var _close_up: Dictionary = {}


## Window units per scene point for the living scene: the screen's own scale (a Retina screen
## shows the kit at one art pixel per physical pixel). Snapshots render as a 2x screen does, so a
## clip is the scene at real size.
##
## Half size (issue 169) halves it: on a Retina screen 1 (one device pixel per point, two art px per
## device pixel); on a 1× screen ½, four art px per device pixel. Either way each device pixel shows a
## whole number of art px, so pixel art stays on its grid (sampled nearest, never smeared).
static func scene_point_scale(snapshot: bool, screen_scale: float, percent: int = 100) -> float:
	var full := 2.0 if snapshot else float(maxi(1, roundi(screen_scale)))
	return full * float(percent) / 100.0


## Units per point the scene is drawn at (issue 222): at a pixel-exact size (`exact`: 100% and 50%)
## the size's own, nearest; at the sizes between, the full size's, then shrunk smoothly
## (`SharpShrink`), so no size scales the art nearest by an uneven amount.
static func scene_render_scale(snapshot: bool, screen_scale: float, percent: int, exact: Array) -> float:
	if exact.has(percent) or exact.has(float(percent)):
		return Game.scene_point_scale(snapshot, screen_scale, percent)
	return Game.scene_point_scale(snapshot, screen_scale, 100)


## Window units per point for the scene's controls and config: the screen's scale, at either size.
static func ui_scale(snapshot: bool, screen_scale: float) -> float:
	return Game.scene_point_scale(snapshot, screen_scale)


func _ready() -> void:
	# The open shell has no scene of its own: with no scene package it says so and starts nothing else.
	if ScenePackages.scene() == null:
		_show_no_scene()
		return
	# Skypatch was renamed VibeNature (issue 211): bring the player's files along before anything
	# reads them. Never in a snapshot, a fresh run or the tests (VIBENATURE_NO_MIGRATE).
	if not Snapshot.on() and _env_string("VIBENATURE_FRESH", "") == "" and _env_string("VIBENATURE_NO_MIGRATE", "") == "":
		for line in DataHome.migrate_default():
			print("VibeNature: " + line)
	scene_mode = Game.wants_scene(_env_string("VIBENATURE_SCENE", ""), OS.has_feature("template"),
			Snapshot.on() and Snapshot.path_name() in Snapshot.SCENE_PATHS)
	balance = Balance.load_default()
	if Snapshot.on():
		Snapshot.prepare(get_window(), balance.data["snapshot"])
	content = Content.load_default()
	_load_islands()
	# In the tree before anything can ask for a save.
	_save_timer.one_shot = true
	_save_timer.timeout.connect(save_now)
	add_child(_save_timer)
	_day_timer.timeout.connect(_check_day)
	add_child(_day_timer)
	_screen_timer.timeout.connect(check_screens)
	add_child(_screen_timer)
	var display: Dictionary = balance.data["display"]
	Pace.configure(int(display["loop_sleep_usec_idle"]), int(display["loop_sleep_usec_moving"]))
	idle_fps_max = float(display["idle_fps_max"])
	settings = Settings.load_or_default(balance, _user_path("VIBENATURE_SETTINGS", "settings.json", Settings.DEFAULT_PATH))
	# macOS window coordinates are points × the largest screen scale attached, on
	# every screen, so this keeps art_scale points per art pixel everywhere.
	scale_px = Settings.device_scale(settings.art_scale(display["art_scales"]))
	rng.randomize()
	clock = GameClock.new(_env_float("VIBENATURE_CLOCK_SPEED", 1.0))
	if Snapshot.on():
		rng.seed = int(balance.data["snapshot"]["rng_seed"])
		Snapshot.pin_clock(clock, balance.data["snapshot"])
	save_game = SaveGame.new(_user_path("VIBENATURE_SAVE", "save.json", SaveGame.DEFAULT_PATH))
	var fresh := _env_string("VIBENATURE_FRESH", "") != "" or Snapshot.on()
	var saved: Dictionary = {} if fresh else save_game.read()
	IslandMigration.rename(_renames(), saved, settings)

	signals = WorldSignals.new()
	add_child(signals)
	signals.setup(clock, dawn_minutes(), balance.data["daily_ceilings"])
	weather = Weather.new()
	add_child(weather)
	weather.setup(clock, signals, int(balance.data["rain_clouds_threshold"]), float(balance.data["weather"]["rain_minutes"]),
			float(balance.data["weather"]["sun_minutes"]))
	weather.from_dict(saved.get("weather", {}))
	economy = Economy.starting(balance.data["starting_inventory"])
	if saved.has("economy"):
		economy.from_dict(saved["economy"])
	journal = Journal.new()
	journal.from_dict(saved.get("journal", {}))
	collection.from_dict(saved.get("collection", {}))
	for visitor in NightVisitors.arrivals(saved.get("close_up", {}), day_key(), balance.data["night_visitors"], rng):
		journal.record("night", visitor, day_key())
		print("VibeNature: in the night, while the shed was closed: %s" % visitor)
	# A pack installed since the last run (bought on the website) is the player's at once.
	for id in packs:
		if packs[id].source == "installed" and not collection.owned.has(id):
			collection.owned[id] = {"since": day_key(), "how": "installed"}
	for id in collection.update(content.catalogue(), day_key()):
		print("VibeNature: a new patch turned up: %s" % id)

	home = HomeView.new()
	add_child(home)
	home.setup(get_window(), scale_px, balance, idle_fps_max)
	home.bench_clicked.connect(_on_bench_clicked)
	home.mailbox_clicked.connect(_on_mailbox_clicked)
	home.sign_clicked.connect(_on_sign_clicked)
	home.right_clicked.connect(func() -> void: set_all_on_top(not get_window().always_on_top))
	home.alt_clicked.connect(_open_debug_panel)
	home.set_bucks(economy.bucks)
	if not shelf_demo_on() and not scene_mode:
		_build_patches(saved)
	sightings.from_dict(saved.get("sightings", {}))
	sightings.changed.connect(request_save)
	welcome_pending = _wants_welcome()
	letters = ElderLetters.new(balance.data["elder"], settings.day_phases())
	letters.from_dict(saved.get("letters", {}))
	letters.changed.connect(request_save)
	_make_scene(saved.get("scene", {}))
	_lay_out(saved.get("layout", {}))
	if scene_mode:
		get_window().position = Vector2i(-10000, -10000)
		get_window().mouse_passthrough = true
	if bool(settings.data["on_top"]):
		set_all_on_top(true)
	apply_full_screen_setting()

	avatar = Avatar.new()
	avatar.setup(self)
	add_child(avatar)
	avatar.sit_at_home()
	_idle_timer.one_shot = true
	_idle_timer.timeout.connect(_on_idle)
	add_child(_idle_timer)
	courier = Courier.new()
	add_child(courier)
	courier.setup(scale_px, balance.data["courier"])
	birds = BirdVisits.new()
	add_child(birds)
	birds.setup(self)
	rhythm = Rhythm.new()
	add_child(rhythm)
	rhythm.setup(clock, settings, signals, balance.data["rhythm"])
	weather.rain_started.connect(_on_rain)
	bridge = AgentBridge.new()
	add_child(bridge)
	bridge.setup(clock, signals, balance.data["bridge"], float(balance.data["long_stretch_hours"]), event_port())
	# The day's rhythm takes the busy edges; the scene takes every session's hand-off and turn end
	# (issue 308), so a pond kept busy all morning by parallel sessions still answers each prompt.
	bridge.busy_changed.connect(func(busy: bool) -> void:
		var day_events := day_rhythm.turn(busy)
		_play_day(day_events)
		_van_turn = busy and day_events.has("arrive")
		if not busy:
			scene.behaviour.agents_idle())
	bridge.hand_off.connect(func(edge: bool) -> void:
		# The turn that brings the van has its arrival as the moment (issue 239).
		scene.behaviour.turn_started(edge and _van_turn)
		_van_turn = false)
	bridge.turn_finished.connect(func(others_busy: bool) -> void:
		scene.behaviour.turn_ended(others_busy))
	for patch in patches:
		SkyOverlay.attach(patch, weather, signals, balance.data["sky"])
	scene.start()
	# Letters are written while you are away: the night before this launch counts (issue 213).
	if scene_mode:
		_letters_overnight()
	_start_day_rhythm()
	sync_login_item()
	signals.world_signal.connect(_on_world_signal)

	_day_timer.start(clock.real_seconds(float(balance.data["clock"]["check_sec"])))

	var windows: Array[Window] = [get_window()]
	windows.append_array(patches)
	for window in windows:
		WindowChrome.draw_on_demand(window)
	config = ConfigWindow.new()
	config.setup(self)
	add_child(config)
	if scene_mode:
		scene_config = SceneConfigWindow.new()
		scene_config.setup(self)
		add_child(scene_config)
		album = PhotoAlbum.new(PhotoAlbum.default_dir())
		book = SceneBookWindow.new()
		book.setup(self, album, sightings)
		add_child(book)
		# Screens plugged in or out while running (issue 174): checked on a slow timer, no per-frame work.
		_screens_seen = SceneScreens.signature(screens_source.call())
		_screen_timer.start(float(balance.data["display"]["screen_check_sec"]))
	if settings.is_first_run():
		# With the welcome (issue 199) the first run ends when it is done or skipped.
		if not welcome_pending:
			settings.mark_first_run_done()
		if not scene_mode:
			open_config(ConfigWindow.AVATAR)
	elif _reopen_config >= 0:
		open_config(_reopen_config)
	_reopen_config = -1
	_check_day()
	if shelf_demo_on():
		shelf_demo = ShelfDemo.new()
		add_child(shelf_demo)
		shelf_demo.setup(self)
	if _env_string("VIBENATURE_SELF_TEST", "") != "":
		var self_test := SelfTest.new()
		add_child(self_test)
		self_test.run(self)
	if Snapshot.on():
		snapshot = Snapshot.new()
		add_child(snapshot)
		snapshot.run(self)
	write_pid_file(OS.get_environment(PID_FILE_ENV))
	# The last three words are for the release's smoke check (issue 196): the native extension loaded (it publishes the
	# day signals), the scene or the islands, and which build.
	print("VibeNature: up, scale x%d, %d patches, %d bucks, %d in the bin, native %s, %s, %s" % [
			scale_px, patches.size(), economy.bucks, economy.bin.size(),
			"on" if OS.get_environment(MAC_SIGNALS_ENV) != "" else "off", "scene" if scene_mode else "islands",
			"demo" if Edition.is_demo() else "full"])
	# The release's smoke check reads this too (issue 442): the official packages and every code body that runs.
	print(ScenePackages.summary())
	# And this (issue 452): the packages' files where the shell reads them, and the kit drawn from them.
	print("VibeNature: package files %s; kit %s" % [ScenePackages.files_summary(),
			"none" if scene == null else ("placeholder" if scene.kit.is_placeholder else scene.kit.root)])


func _show_no_scene() -> void:
	no_scene = NoSceneView.new()
	no_scene.quit_requested.connect(quit)
	no_scene.show_in(get_window())
	add_child(no_scene)
	print(NoSceneView.status_line())
	write_pid_file(OS.get_environment(PID_FILE_ENV))


## Built-in island packs, then installed ones (user://islands, or VIBENATURE_ISLANDS), each
## added to the catalogue. Refused packs are logged with the reason and left alone.
func _load_islands() -> void:
	island_loader = IslandLoader.for_game(balance.data["shelf"], _user_path("VIBENATURE_ISLANDS", "islands", IslandLoader.INSTALLED))
	island_loader.load_all()
	packs = island_loader.packs
	for id in packs:
		content.add_pack(packs[id])
	for refusal in island_loader.refused:
		print("VibeNature: island pack %s refused: %s" % [String(refusal["file"]).get_file(), refusal["why"]])


## Old island id -> pack id, from each pack's `formerly`.
func _renames() -> Dictionary:
	var out := {}
	for id in packs:
		for old in packs[id].formerly:
			out[String(old)] = String(id)
	return out


func _build_patches(saved: Dictionary) -> void:
	_states = saved.get("patches", {}).duplicate(true)
	for id in collection.out_today(content.catalogue(), settings.data["roster"], day_key()):
		_add_patch(String(id))


## One island's window and mechanic, from its pack (or, for an island that is not a pack yet,
## from its delivery under assets/patches).
func _add_patch(id: String) -> PatchWindow:
	var display: Dictionary = balance.data["display"]
	var def: PatchDef
	var sky := int(display["patch_sky_px"])
	var pack: IslandPack = packs.get(id)
	if pack != null:
		def = pack.patch_def(balance.data["shelf"])
		sky = island_sky(def)
	else:
		def = PatchDef.load_patch(id, AssetLibrary.vec2i(balance.data["placeholders"]["patch_island"]))
	var patch := PatchWindow.new()
	patch.setup(def, sky, scale_px, float(display["click_shape_epsilon"]), float(balance.data["input"]["drag_threshold_px"]),
			content.patch_tools(id), content.default_tool(id), icon_for, balance.data["tool_row"])
	# A dismissed island is built (its mechanic keeps running and saving) but hidden.
	patch.visible = not settings.is_dismissed(id)
	add_child(patch)
	patches.append(patch)
	patch.clicked.connect(_on_patch_clicked)
	patch.moved_by_player.connect(func(_patch: PatchWindow) -> void: request_save())
	var mechanic := pack.make_mechanic() if pack != null else _make_mechanic(content.mechanic_for(id))
	if mechanic != null:
		patch.attach_mechanic(mechanic)
		mechanic.setup(patch, self)
		if _states.has(id):
			mechanic.load_state(_states[id])
	return patch


## Sky above a pack island: the usual, or more, so the avatar's head stays in the window
## wherever on the island it stands (the highest of its non-perch spots).
func island_sky(def: PatchDef) -> int:
	var display: Dictionary = balance.data["display"]
	var highest := INF
	for spot_name in def.spots:
		if def.spots[spot_name]["kind"] != "perch":
			highest = minf(highest, float(def.spots[spot_name]["at"].y))
	if highest == INF:
		return int(display["patch_sky_px"])
	var figure := int(balance.data["placeholders"]["avatar_figure"][1])
	return maxi(int(display["patch_sky_px"]), figure + int(display["avatar_headroom_px"]) - int(highest))


## Installs the island pack at `pck_path` (its signature beside it as `<pck>.sig`): checked,
## copied into the installed folder, mounted, added to the catalogue and the collection, and
## put out at once so the player meets it. Returns "" or why it was refused.
func install_island(pck_path: String) -> String:
	var pack := island_loader.install(pck_path)
	if pack == null:
		return String(island_loader.refused[-1]["why"])
	packs[pack.id] = pack
	content.add_pack(pack)
	if not collection.owned.has(pack.id):
		collection.owned[pack.id] = {"since": day_key(), "how": "installed"}
	var patch := _add_patch(pack.id)
	WindowChrome.draw_on_demand(patch)
	var taken := _fixed()
	for other in patches:
		if other != patch:
			taken.append(footprint(other))
	var unplaced: Array[Window] = [patch]
	_place(unplaced, taken)
	request_save()
	if config != null and config.visible:
		config.refresh()
	print("VibeNature: installed island %s %s (%s)" % [pack.id, pack.version, pack.source])
	return ""


func patch_ids_out() -> Array:
	var ids: Array = []
	for patch in patches:
		ids.append(patch.def.id)
	return ids


## Mechanics of islands that are not packs yet.
func _make_mechanic(mechanic_name: String) -> PatchMechanic:
	match mechanic_name:
		"beehive":
			return Beehive.new()
	return null


## Home where it was (else the bottom-left corner; the bottom-right is the scene's, issue 89). Each patch where the player dragged it,
## if it is still on a screen; each patch the game put out where it was, if its grown
## footprint is still clear of everything placed before it; the rest turn up in random places
## across every screen, each reserving its grown size so no two islands ever overlap, grown or
## not, and none overlaps home or the scene's corner (issue 66). Anything that cannot fit lines up beside home.
func _lay_out(layout: Dictionary) -> void:
	var display: Dictionary = balance.data["display"]
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var margin := int(display["screen_margin_px"]) * scale_px
	var shed_window := get_window()
	# The scene holds the bottom-right corner, flush to it.
	scene.position = _scene_position()
	# A snapshot run's root stays far off screen; its windows are drawn inside it.
	if not Snapshot.on():
		shed_window.position = Placer.home_corner(usable, shed_window.size, margin, scene_on_left())
		_restore(shed_window, layout, [])
	var taken := _fixed()
	var unplaced: Array[Window] = []
	# The player's own places first: they hold whatever is around them.
	for by_player in [true, false]:
		for patch in patches:
			if _dragged_in(layout, patch) != by_player:
				continue
			if _restore(patch, layout, taken):
				taken.append(footprint(patch))
			else:
				unplaced.append(patch)
	_place(unplaced, taken)


## Flush to the bottom-right corner of the scene's screen (its usable rect), at either size.
func _scene_position() -> Vector2i:
	if not scene_mode:
		var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
		return SceneScreens.corner(usable, scene.size, scene_on_left(), 0, scene_on_top())
	return SceneScreens.corner(scene_usable(), scene.size, scene_on_left(), scene_lift_units(), scene_on_top())


## The screen corner the scene holds (issue 424; one of `display.scene_corners`, else the bottom-right).
func scene_corner() -> String:
	var name := SceneScreens.corner_name(settings.data.get("scene_corner", ""))
	return name if (balance.data["display"]["scene_corners"] as Array).has(name) else "bottom_right"


## Whether the scene holds a left corner (issue 422; the bottom-right is the default).
func scene_on_left() -> bool:
	return SceneScreens.is_left(scene_corner())


## Whether the scene holds a top corner (issue 424): flush under the menu bar, never lifted.
func scene_on_top() -> bool:
	return SceneScreens.is_top(scene_corner())


## Config's "Mirror the scene" (issue 424): the picture drawn the other way round, in any corner.
func scene_mirror() -> bool:
	return bool(settings.data.get("scene_mirror", false))


## The scene's lift off the bottom edge (points, one of `display.scene_lifts_pt`; issue 422).
func scene_lift_pt() -> int:
	var steps: Array = balance.data["display"]["scene_lifts_pt"]
	var wanted := int(settings.data.get("scene_lift", 0))
	return wanted if steps.has(wanted) or steps.has(float(wanted)) else 0


## The lift in screen units (the screen's scale, whatever the scene's size).
func scene_lift_units() -> int:
	return roundi(scene_lift_pt() * Game.ui_scale(Snapshot.on(), DisplayServer.screen_get_max_scale()))


## Config's corner choice (issues 422, 424): the scene moves at once, its edges against the screen straight and
## its open edges fading, never mirrored by the corner (that is `set_scene_mirror`), and the choice is saved.
func set_scene_corner(corner_name: String) -> void:
	settings.data["scene_corner"] = SceneScreens.corner_name(corner_name)
	settings.save()
	if scene == null:
		return
	scene.set_corner(scene_corner(), scene_mirror())
	scene.position = _scene_position()
	if scene_config != null and scene_config.visible:
		scene_config.refresh()
	print("VibeNature: the scene in the %s corner" % String(settings.data["scene_corner"]).replace("_", "-"))


## Config's "Mirror the scene" (issue 424): applied at once in the same corner, and saved.
func set_scene_mirror(on: bool) -> void:
	settings.data["scene_mirror"] = on
	settings.save()
	if scene == null:
		return
	scene.set_corner(scene_corner(), on)
	scene.position = _scene_position()
	if scene_config != null and scene_config.visible:
		scene_config.refresh()
	print("VibeNature: the scene %s" % ("mirrored" if on else "as made"))


## Config's lift (issue 422): the scene moves up off the bottom edge at once, and the choice is saved.
func set_scene_lift(lift_pt: int) -> void:
	settings.data["scene_lift"] = lift_pt
	settings.save()
	if scene == null:
		return
	scene.position = _scene_position()
	if scene_config != null and scene_config.visible:
		scene_config.refresh()


## The mouse clear's size, points across (issue 438): the saved one if it is a step, else the default.
func mouse_clear_pt() -> int:
	var tuning: Dictionary = balance.data["scene"]["mouse_clear"]
	var wanted := int(settings.data.get("mouse_clear_size", 0))
	var steps: Array = tuning["diameters_pt"]
	return wanted if steps.has(wanted) or steps.has(float(wanted)) else int(tuning["diameter_pt"])


## Config's mouse clear size (issue 438): applies at once and is saved.
func set_mouse_clear_size(points: int) -> void:
	settings.data["mouse_clear_size"] = points
	settings.save()
	if scene != null and scene.mouse_clear != null:
		scene.mouse_clear.set_size(mouse_clear_pt())
	if scene_config != null and scene_config.visible:
		scene_config.refresh()


## The screen the scene is on (issue 174): the saved one if it is still connected, else the main one.
func scene_screen() -> int:
	return SceneScreens.resolve(screens_source.call(), settings.data["scene_screen"])


## The usable rect (Dock and menu bar left out) of the scene's screen.
func scene_usable() -> Rect2i:
	var screens: Array = screens_source.call()
	if screens.is_empty():
		return Rect2i()
	return screens[SceneScreens.resolve(screens, settings.data["scene_screen"])]["usable"]


## Config's screen picker: the scene moves at once to that screen's bottom-right corner, and the
## choice is saved for the next start.
func move_scene_to_screen(index: int) -> void:
	var screens: Array = screens_source.call()
	if index < 0 or index >= screens.size():
		return
	settings.data["scene_screen"] = SceneScreens.key(screens[index])
	settings.save()
	scene.position = _scene_position()
	print("VibeNature: the scene on screen %d" % (index + 1))


## Screens plugged in or out: the scene stays on its screen if that is still here, else goes to the
## main one (the saved choice is kept, so it comes back when its screen does); Config's picker follows.
func check_screens() -> void:
	var seen := SceneScreens.signature(screens_source.call())
	if seen == _screens_seen:
		return
	_screens_seen = seen
	if scene != null:
		scene.position = _scene_position()
	if scene_config != null and scene_config.visible:
		scene_config.refresh()


## The living scene at the player's size. In scene mode it carries the control strip.
func _make_scene(director_state: Dictionary) -> void:
	scene = LivingScene.new()
	scene.sitter.composed = avatar_sheet()
	scene.van.at_door.connect(open_welcome)
	scene.avatar_look = avatar_look()
	scene.van.paint = van_paint()
	var scene_tuning: Dictionary = balance.data["scene"]
	var screen_scale := DisplayServer.screen_get_max_scale()
	var percent := scene_percent() if scene_mode else 100
	scene.setup(scene_tuning, settings.day_phases(), Game.scene_point_scale(Snapshot.on(), screen_scale, percent),
			Avatar.resolve_id(String(settings.data["avatar_id"]), Avatar.choices(balance.data["placeholders"])),
			int(scene_tuning["seed"]) if Snapshot.on() else rng.randi(),
			Game.scene_render_scale(Snapshot.on(), screen_scale, percent, balance.data["display"]["scene_sizes_exact"]))
	scene.clock_minute = scene_minute
	scene.behaviour.unix_clock = clock.now
	scene.behaviour.director.from_dict(director_state)
	scene.behaviour.sightings = sightings
	scene.manual = Snapshot.on() and Snapshot.path_name() in Snapshot.SCENE_PATHS
	scene.flights.set_enabled(bool(settings.data["desktop_flights"]))
	if scene_mode:
		scene.set_corner(scene_corner(), scene_mirror())
	if scene_mode:
		# Flights cross the scene's own screen (issue 174).
		scene.flights.desktop_rect = func() -> Rect2: return Rect2(scene_usable())
	# Tests that run the scene mode set VIBENATURE_NO_BEACON, so they never write the real beacon.
	if scene_mode and not Snapshot.on() and _env_string("VIBENATURE_NO_BEACON", "") == "":
		scene.beacon = CalmLabBeacon.new(CalmLabBeacon.default_path(), float(scene_tuning["calm_lab_every_sec"]))
	add_child(scene)
	# Off by default (SPEC §2.1); never in a snapshot run, which is reviewed by eye.
	scene.set_sound(bool(settings.data["sound"]) and not Snapshot.on())
	if scene_mode:
		var steps: Array = balance.data["display"]["scene_sizes"]
		var controls := scene.add_controls(scene_tuning["controls"], Game.ui_scale(Snapshot.on(), screen_scale),
				Settings.step_from(steps, percent, -1) == percent, Settings.step_from(steps, percent, 1) == percent)
		if Snapshot.on():
			# Off screen, the real pointer means nothing: the snapshot opens the strip itself.
			controls.pointer_source = func() -> Variant: return null
		controls.photo_requested.connect(_on_photo_requested)
		controls.book_requested.connect(_on_book_requested)
		controls.zoom_requested.connect(step_scene_size)
		controls.settings_requested.connect(toggle_scene_config)
		controls.quit_requested.connect(quit)
		var finder := scene.add_viewfinder(scene_tuning["photo"])
		if Snapshot.on():
			finder.pointer_source = func() -> Variant: return null
		finder.shot.connect(_on_shot)
		if Edition.is_demo():
			var card := scene.add_demo_card(balance.data["demo_card"], Game.ui_scale(Snapshot.on(), screen_scale))
			if Snapshot.on():
				card.pointer_source = func() -> Variant: return null
		var letter_card := scene.add_letter_card(balance.data["letter_card"], Game.ui_scale(Snapshot.on(), screen_scale))
		var clear := scene.add_mouse_clear(scene_tuning["mouse_clear"], Game.ui_scale(Snapshot.on(), screen_scale))
		clear.set_size(mouse_clear_pt())
		if Snapshot.on():
			clear.cursor_source = func() -> Variant: return null
		letter_card.journal_requested.connect(open_letters)
		scene.letter_clicked.connect(open_letters)
		scene.letter_started.connect(_on_letter_started)
		_letter_due_update()


## The scene's size in percent of full (one of `display.scene_sizes`).
func scene_percent() -> int:
	return settings.scene_percent(balance.data["display"]["scene_sizes"])


## The strip's magnifiers: one size smaller (−1) or larger (+1), held at the ends.
func step_scene_size(delta: int) -> void:
	set_scene_size(Settings.step_from(balance.data["display"]["scene_sizes"], scene_percent(), delta))


## A scene size (the strip's − and +, or Config): saved, then the same scene is resized in place in
## the same corner (issue 307): every animal, the sitter, the van and the weather go on where they
## are, in their beat. Never rebuilt: a rebuild emptied the pond and left the old strip taking input.
func set_scene_size(percent: int) -> void:
	percent = Settings.nearest_step(balance.data["display"]["scene_sizes"], float(percent))
	if percent == scene_percent():
		return
	settings.data["scene_size"] = percent
	settings.save()
	if scene == null or not scene_mode:
		return
	var screen_scale := DisplayServer.screen_get_max_scale()
	var steps: Array = balance.data["display"]["scene_sizes"]
	scene.rescale(Game.scene_point_scale(Snapshot.on(), screen_scale, percent),
			Game.scene_render_scale(Snapshot.on(), screen_scale, percent, balance.data["display"]["scene_sizes_exact"]),
			Settings.step_from(steps, percent, -1) == percent, Settings.step_from(steps, percent, 1) == percent)
	scene.position = _scene_position()
	if scene_config != null and scene_config.visible:
		scene_config.refresh()
	print("VibeNature: the scene at %d%%" % percent)


## The strip's 📷 (issue 176): opens the viewfinder at the pointer, or closes it again.
func _on_photo_requested() -> void:
	var finder := scene.viewfinder if scene != null else null
	if finder == null:
		return
	if finder.is_open:
		finder.cancel()
		return
	var at: Variant = null
	if finder.pointer_source.is_valid():
		at = finder.pointer_source.call()
	else:
		at = Vector2(DisplayServer.mouse_get_position() - scene.position)
	finder.open((at as Vector2) / scene.scale_px if at is Vector2 else null)


## A click in the viewfinder: the framed part of the scene's own render goes to the album with the
## time, the weather and the species inside the frame. `photo_render` stands in for the render in tests.
func _on_shot(rect_pt: Rect2) -> void:
	if album == null:
		return
	var species := ScenePhoto.species_in(scene.behaviour, rect_pt, float(scene.viewfinder.tuning["species_share"]))
	var weather := PhotoAlbum.weather_word(scene.behaviour.weather(), balance.data["scene_book"]["weather_words"])
	var full := ScenePhoto.grab(scene, photo_render)
	var image := ScenePhoto.take(scene, rect_pt, bool(settings.data["photo_mark"]), scene.viewfinder.tuning, full)
	if image == null:
		push_warning("VibeNature: the scene could not be rendered for a photo")
		return
	last_photo = album.add(image, {"unix": clock.now(), "weather": weather, "species": species})


## The strip's 📖: opens the book (issue 177), or closes it. One of the book and Config at a time.
func _on_book_requested() -> void:
	if book == null:
		return
	if book.visible:
		book.close_book()
	else:
		if letters != null and not letters.waiting().is_empty():
			open_letters()
			return
		if scene_config != null:
			scene_config.close_config()
		book.open(SceneBookWindow.PHOTOS)


## A click on you reading the letter on the log, or opening the journal while a letter waits: the journal opens at the letter,
## and it is read.
func open_letters() -> void:
	if book == null:
		return
	if scene_config != null:
		scene_config.close_config()
	if scene != null and scene.letter_card != null:
		scene.letter_card.dismiss()
	book.open(SceneBookWindow.LETTERS)
	letters.mark_read()
	_letter_due_update()
	book.refresh()


## Sends a photo to the elder (one click, never undone; issue 213).
func send_photo(id: String) -> bool:
	if letters == null or album == null:
		return false
	for photo in album.photos():
		if String(photo["id"]) == id:
			return letters.send(photo, clock.now(), day_key(), String(balance.data["elder"]["place"]))
	return false


## The home folder whose `.claude` and `.codex` the connect step reads and writes (issue 199): VIBENATURE_HOOK_HOME,
## else a folder of the run's own in a snapshot or a headless run (tests), else "" (the person's own home). A test
## or a snapshot never touches the real ~/.claude or ~/.codex.
func hook_home() -> String:
	var given := _env_string("VIBENATURE_HOOK_HOME", "")
	if given != "":
		return given
	if Snapshot.on():
		return ProjectSettings.globalize_path(Snapshot.user_dir().path_join("home"))
	if DisplayServer.get_name() == "headless":
		return ProjectSettings.globalize_path("user://test_hook_home")
	return ""


## The elder's portrait (issue 241) in the player's skin tone (issue 199), or null while the bench has not
## delivered it. `elder_id` "" is the chosen elder. Baked once per elder and skin.
func elder_portrait(elder_id: String = "") -> Texture2D:
	if letters == null:
		return null
	var who := elder_id if elder_id != "" else String(elder_choice()["who"])
	var skin := String(avatar_look().get("skin", ""))
	var key := "%s|%s" % [who, skin]
	if not _portraits.has(key):
		var image := AvatarLook.portrait_image(letters.portrait_path({"who": who}), skin)
		_portraits[key] = ImageTexture.create_from_image(image) if image != null else null
	return _portraits[key]


## Config, General, and the welcome's last step. The release app adds itself to Login Items or leaves them
## (issue 196: the native extension, through `LoginItem`); a dev run only keeps the choice.
func set_open_at_login(on: bool) -> void:
	settings.data["open_at_login"] = on
	settings.save()
	_ask_login_item()


## Open at login (issue 196): the system's state is read at launch and on every day poll. A change the person made
## in System Settings (even while VibeNature was closed) becomes the setting, and Config shows it; otherwise the
## setting is asked for. Nothing is asked while the first run's welcome is still to answer.
func sync_login_item() -> void:
	if Snapshot.on():
		return
	var state := String(login_item_source.call())
	var last := String(settings.data["login_item_seen"])
	var before := bool(settings.data["open_at_login"])
	var now := LoginItem.reconcile(before, state, last)
	var seen := LoginItem.seen(state, last)
	if now != before or seen != last:
		settings.data["open_at_login"] = now
		settings.data["login_item_seen"] = seen
		settings.save()
	if now != before:
		print("VibeNature: open at login %s in System Settings" % ("turned on" if now else "turned off"))
		for window in [scene_config, welcome]:
			if window != null and is_instance_valid(window):
				window.open_at_login.set_pressed_no_signal(now)
	_ask_login_item()


func _ask_login_item() -> void:
	if Snapshot.on() or welcome_pending:
		return
	var want := LoginItem.want(bool(settings.data["open_at_login"]), String(login_item_source.call()))
	if want != "":
		OS.set_environment(LoginItem.WANT_ENV, want)


## Whether this launch shows the first-run welcome: scene mode, the first run, and not a snapshot of another path
## or a test that turns it off (VIBENATURE_NO_WELCOME).
func _wants_welcome() -> bool:
	if not scene_mode or not settings.is_first_run() or _env_string("VIBENATURE_NO_WELCOME", "") != "":
		return false
	return not Snapshot.on() or Snapshot.path_name() == "welcome"


## You stepped out of the van (or, at night, the launch settled): the welcome opens, this one time taking focus.
func open_welcome() -> void:
	if not welcome_pending or (welcome != null and welcome.visible):
		return
	if welcome == null:
		welcome = SceneWelcomeWindow.new()
		welcome.setup(self)
		welcome.finished.connect(finish_welcome)
		add_child(welcome)
	if scene_config != null:
		scene_config.close_config()
	if book != null:
		book.close_book()
	welcome.open_welcome()


## The welcome is done or skipped: the first run is over, you walk from the van to the log and sit, and the
## elder's first letter waits (issue 213), from the elder just chosen, to be read on the log once you sit (issue 270).
func finish_welcome() -> void:
	if not welcome_pending:
		return
	welcome_pending = false
	settings.mark_first_run_done()
	if scene != null:
		scene.release_first()
	if letters != null and not letters.first_given:
		letters.give_first(clock.now(), day_key(), elder_choice())
		letters.decided_day = day_key()
	_letter_due_update()
	_ask_login_item()
	print("VibeNature: welcome done")


## The elder who writes (Config's Elder tab and the welcome, issue 199).
func elder_choice() -> Dictionary:
	return letters.sanitize(settings.data["elder"]) if letters != null else settings.data["elder"]


func set_elder(choice: Dictionary) -> void:
	settings.data["elder"] = letters.sanitize(choice) if letters != null else choice
	settings.save()
	# A letter already written keeps its signature; the first one is written from the choice at the welcome's end.
	if book != null and book.visible:
		book.refresh()


## The first letter waits after the welcome (issue 199; on the first launch when there is none); then, once a
## game day while you are not at the log, the overnight decision.
func _letters_overnight() -> void:
	if letters == null or welcome_pending:
		return
	if not letters.first_given:
		letters.give_first(clock.now(), day_key(), elder_choice())
		letters.decided_day = day_key()
	elif day_rhythm == null or not day_rhythm.here:
		var letter := letters.overnight(clock.now(), day_key(), elder_choice(), rng)
		if not letter.is_empty():
			print("VibeNature: a letter came overnight")
	_letter_due_update()


## A waiting letter not yet read on the log is due there (issue 270): the sitter reads it at the end of the first
## rest once you sit at the log. Never during the welcome.
func _letter_due_update() -> void:
	if scene != null and letters != null:
		if scene.sitter != null:
			scene.sitter.letter_words = SceneSitter.letter_word_count(letters.waiting())
		scene.letter_due = not welcome_pending and letters.due_on_log()


func _on_letter_started() -> void:
	if letters != null:
		var letter := letters.waiting()
		if scene != null and scene.letter_card != null:
			scene.letter_card.set_letter(letter, elder_portrait(String(letter.get("elder", ""))) if not letter.is_empty() else null)
		letters.mark_on_log()
	_letter_due_update()


func toggle_scene_config() -> void:
	if scene_config == null:
		return
	if scene_config.visible:
		scene_config.close_config()
	else:
		if book != null:
			book.close_book()
		scene_config.open(SceneConfigWindow.GENERAL)


func set_sound(on: bool) -> void:
	settings.data["sound"] = on
	settings.save()
	if scene != null:
		scene.set_sound(on and not Snapshot.on())


func set_photo_mark(on: bool) -> void:
	settings.data["photo_mark"] = on
	settings.save()


## The player's avatar (issue 202): always a whole, valid look.
func avatar_look() -> Dictionary:
	return settings.data["avatar"]


## The player's look, swapped, for the sitter on the log.
func avatar_sheet() -> Dictionary:
	return AvatarLook.sheet(avatar_look())


## A new look from the picker: saved, and sat on the log at once (the live preview on the log). The old
## island game's avatar_id follows as the whole avatar for that body.
func set_avatar_look(look: Dictionary) -> void:
	var cfg: Dictionary = balance.data["avatar_looks"]
	var clean := AvatarLook.sanitize(look, cfg)
	if AvatarLook.key(clean) == AvatarLook.key(avatar_look()):
		return
	settings.data["avatar"] = clean
	settings.data["avatar_id"] = AvatarLook.island_avatar_id(clean, cfg)
	settings.save()
	if scene != null:
		scene.sitter.use_sheet(avatar_sheet())
		scene.use_look(clean)
		# Never WindowChrome.redraw(scene): that leaves the scene drawing once, frozen on that frame (and at
		# the in-between sizes, on the frame before the change). resume_drawing hands back to every frame.
		scene.resume_drawing()


## The van's meta.json (the bench's sheet, issue 197): its paint ramps are what the picker offers.
func van_meta() -> Dictionary:
	return VanPaint.meta(SceneVan.file(balance.data["scene"]["day"]["van"], "meta"))


## The van's paint (issue 279): always a whole, valid choice.
func van_paint() -> Dictionary:
	return VanPaint.sanitize(settings.data.get("van", {}), van_meta())


## A new paint from the picker: saved, and the van on the bank repainted at once (every frame, lit ones too).
func set_van_paint(choice: Dictionary) -> void:
	var clean := VanPaint.sanitize(choice, van_meta())
	if VanPaint.key(clean) == VanPaint.key(van_paint()):
		return
	settings.data["van"] = clean
	settings.save()
	if scene != null:
		scene.van.use_paint(clean)
		scene.resume_drawing()


## Random free places across every screen for `unplaced`, each reserving its grown footprint
## clear of `taken`; anything that cannot fit lines up beside home, short of the scene's corner.
func _place(unplaced: Array[Window], taken: Array) -> void:
	var display: Dictionary = balance.data["display"]
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var gap := int(display["window_gap_px"]) * scale_px
	var margin := int(display["screen_margin_px"]) * scale_px
	var shed_window := get_window()
	var sizes: Array = []
	for w in unplaced:
		sizes.append(footprint(w).size)
	var placement: Dictionary = balance.data["placement"]
	var spots := Placer.place(sizes, _screens(), taken, int(placement["margin_px"]) * scale_px, rng, int(placement["attempts"]))
	var leftovers: Array[Window] = []
	for i in unplaced.size():
		var patch := unplaced[i] as PatchWindow
		if patch != null:
			patch.placed_by_player = false
		if spots[i] != Vector2i(-1, -1):
			unplaced[i].position = Placer.inside(Rect2i(spots[i], sizes[i]), unplaced[i].size)
		else:
			leftovers.append(unplaced[i])
	if scene_on_left():
		_line_up(leftovers, usable, _scene_corner().end.x + gap, shed_window.position.x - gap, margin, gap)
	else:
		_line_up(leftovers, usable, shed_window.position.x + shed_window.size.x + gap, _scene_corner().position.x - gap, margin, gap)


## What never moves for an island: home where it is, and the scene's corner.
func _fixed() -> Array:
	return [Rect2i(get_window().position, get_window().size), _scene_corner()]


## The bottom-right corner of the main screen kept for the living scene (contract §7): the
## scene's own window once it is out, else the corner reserved for it.
func _scene_corner() -> Rect2i:
	if scene != null:
		return Rect2i(scene.position, scene.size)
	var display: Dictionary = balance.data["display"]
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	return Placer.scene_corner(usable, AssetLibrary.vec2i(display["scene_corner_px"]) * scale_px, int(display["screen_margin_px"]) * scale_px, scene_on_left())


func _screens() -> Array:
	var screens: Array = []
	for screen in DisplayServer.get_screen_count():
		screens.append(DisplayServer.screen_get_usable_rect(screen))
	return screens


## What `window` takes on screen at its largest: a patch grown as the island the avatar is on
## (`_active_scale`, about its bottom centre), home as it is.
func footprint(window: Window) -> Rect2i:
	var rect := Rect2i(window.position, window.size)
	var patch := window as PatchWindow
	if patch == null or patch.scale_px >= _active_scale():
		return rect
	return Placer.grown(rect, float(_active_scale()) / float(patch.scale_px))


## A saved layout entry is `[x, y]`, or `[x, y, true]` when the player dragged it there.
static func _dragged_in(layout: Dictionary, window: Window) -> bool:
	var patch := window as PatchWindow
	var entry = layout.get(patch.def.id if patch != null else "home")
	return entry is Array and (entry as Array).size() > 2 and bool(entry[2])


## Puts `window` where `layout` saved it, if it is still on a screen and, for a patch the game
## placed, its grown footprint is on a screen and clear of `taken`.
func _restore(window: Window, layout: Dictionary, taken: Array) -> bool:
	var key := _layout_key(window)
	if not layout.has(key):
		return false
	var at := AssetLibrary.vec2i(layout[key])
	var patch := window as PatchWindow
	if patch == null:
		if not _on_a_screen(Rect2i(at, window.size)):
			return false
		window.position = at
		return true
	var by_player := _dragged_in(layout, patch)
	var rect := Rect2i(at, patch.size)
	var grown := rect if patch.scale_px >= _active_scale() else Placer.grown(rect, float(_active_scale()) / float(patch.scale_px))
	if not Placer.keep_saved(rect, grown, by_player, _screens(), taken, int(balance.data["placement"]["margin_px"]) * scale_px):
		return false
	patch.position = at
	patch.placed_by_player = by_player
	return true


## The island the avatar is on has grown: any island the game placed that it now overlaps
## moves aside, or the grown island does, whichever is the smaller move that clears everything
## and stays on a screen. Islands the player dragged are left where the player put them.
func _clear_growth(grown: PatchWindow) -> void:
	var margin := int(balance.data["placement"]["margin_px"]) * scale_px
	var screens := _screens()
	for other in patches:
		if other == grown or not other.visible or other.placed_by_player:
			continue
		var grown_rect := Rect2i(grown.position, grown.size)
		if not Rect2i(other.position, other.size).intersects(grown_rect):
			continue
		var around_other: Array = _fixed() + [grown_rect]
		var around_grown: Array = _fixed()
		for third in patches:
			if third == grown or not third.visible:
				continue
			around_grown.append(Rect2i(third.position, third.size))
			if third != other:
				around_other.append(footprint(third))
		var other_rect := footprint(other)
		var other_to := Placer.nudge(other_rect, screens, around_other, margin)
		var grown_to := Vector2i(-1, -1) if grown.placed_by_player else Placer.nudge(grown_rect, screens, around_grown, margin)
		var other_move := INF if other_to == Vector2i(-1, -1) else Vector2(other_to - other_rect.position).length()
		var grown_move := INF if grown_to == Vector2i(-1, -1) else Vector2(grown_to - grown_rect.position).length()
		if other_move == INF and grown_move == INF:
			continue
		if other_move <= grown_move:
			other.position = Placer.inside(Rect2i(other_to, other_rect.size), other.size)
		else:
			grown.position = grown_to
	request_save()


## Left-aligned to `left_edge` along the bottom, no further right than `right_edge`, wrapping
## into rows upward, each window spaced by its grown footprint so islands stay apart when they grow.
func _line_up(windows: Array[Window], usable: Rect2i, left_edge: int, right_edge: int, margin: int, gap: int) -> void:
	var max_width := mini(right_edge, usable.end.x - margin) - left_edge
	var rows: Array = [[]]
	var row_width := 0
	for w in windows:
		var row: Array = rows[-1]
		var w_size := footprint(w).size
		var needed := w_size.x if row.is_empty() else row_width + gap + w_size.x
		if not row.is_empty() and needed > max_width:
			rows.append([w])
			row_width = w_size.x
		else:
			row.append(w)
			row_width = needed
	var bottom := usable.end.y - margin
	for row: Array in rows:
		var height := 0
		for w: Window in row:
			height = maxi(height, footprint(w).size.y)
		var x := left_edge
		for w: Window in row:
			var w_size := footprint(w).size
			w.position = Placer.inside(Rect2i(Vector2i(x, bottom - w_size.y), w_size), w.size)
			x += w_size.x + gap
		bottom -= height + gap


func _layout_key(window: Window) -> String:
	var patch := window as PatchWindow
	return patch.def.id if patch != null else "home"


func _on_a_screen(rect: Rect2i) -> bool:
	var center := rect.get_center()
	for screen in DisplayServer.get_screen_count():
		if DisplayServer.screen_get_usable_rect(screen).has_point(center):
			return true
	return false


func _on_bench_clicked() -> void:
	_touch()
	if not avatar.is_home() and not avatar.busy:
		go_home()


## Opening the mailbox clears its glow. (A view of what is inside comes with the UI pass.)
func _on_mailbox_clicked() -> void:
	_touch()
	home.set_bin_full(false)
	print("VibeNature: the mailbox holds %d things, worth %d bucks at dawn" % [economy.bin.size(), economy.bin_total()])


func _on_sign_clicked() -> void:
	_touch()
	if config.visible:
		config.close_config()
	else:
		open_config(ConfigWindow.GENERAL)


## Config on `tab`. It takes keyboard focus: the player asked for it (or it is the first run).
func open_config(tab: int) -> void:
	config.open(tab)


## The ✕ (or Config's Islands tab): the island goes away, with everything on it kept, until
## it is turned back on. An avatar standing on it poofs home first.
func dismiss_patch(patch: PatchWindow) -> void:
	settings.set_dismissed(patch.def.id, true)
	if avatar.patch == patch:
		await go_home()
	patch.hide()
	request_save()
	if config.visible:
		config.refresh()
	print("VibeNature: %s put away (Config, Islands, brings it back)" % patch.def.id)


func restore_patch(patch: PatchWindow) -> void:
	settings.set_dismissed(patch.def.id, false)
	if not patch.visible:
		patch.show()
		WindowChrome.wake(patch)
	print("VibeNature: %s is back" % patch.def.id)


## Config's Islands switch for `id`. An island not out today just remembers the choice.
func set_island_dismissed(id: String, dismissed: bool) -> void:
	for patch in patches:
		if patch.def.id == id:
			if dismissed:
				dismiss_patch(patch)
			else:
				restore_patch(patch)
			return
	settings.set_dismissed(id, dismissed)


## Home and every patch above other windows, or back behind them (the default,
## §2.9). Right-click home. A patch can still be toggled alone with a right-click.
func set_all_on_top(on_top: bool) -> void:
	get_window().always_on_top = on_top
	scene.always_on_top = on_top
	if scene.mouse_clear != null:
		scene.mouse_clear.set_on(on_top)
	for patch in patches:
		patch.always_on_top = on_top
	settings.data["on_top"] = on_top
	settings.save()
	print("VibeNature: everything %s" % ("on top" if on_top else "behind other windows"))


## Whether VibeNature's windows show over other apps' full-screen Spaces (a game, a video).
## Off by default: a window there sits on the app and takes its mouse wherever an island is
## (Skypatch issue 50). The native extension reads
## the variable whenever the player changes Space or a window is shown.
func set_show_over_full_screen(on: bool) -> void:
	settings.data["show_over_full_screen"] = on
	settings.save()
	apply_full_screen_setting()


## Now and then a songbird flies out of the scene over the desktop
## (Skypatch issue 120). On by default; off stops a
## flight under way and no more come.
func set_desktop_flights(on: bool) -> void:
	settings.data["desktop_flights"] = on
	settings.save()
	scene.flights.set_enabled(on)


func apply_full_screen_setting() -> void:
	var on := bool(settings.data["show_over_full_screen"]) and not Snapshot.on()
	OS.set_environment(FULL_SCREEN_ENV, "1" if on else "0")


## A patch takes every click in its window while the avatar is on it (so a click on the
## sky sends the avatar home) or a mini-game runs; otherwise only its island and tools do.
func refresh_capture(patch: PatchWindow) -> void:
	var mini_game := patch.mechanic != null and patch.mechanic.wants_all_clicks()
	patch.set_capture_all(avatar.patch == patch or mini_game)


func _on_patch_clicked(patch: PatchWindow, button: int, art_point: Vector2) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		WindowChrome.toggle_on_top(patch)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	_touch()
	if patch.mechanic != null and patch.mechanic.wants_all_clicks():
		patch.mechanic.on_click(art_point)
		return
	if avatar.busy:
		return
	if patch.close_at(art_point):
		dismiss_patch(patch)
		return
	var tool_id := patch.tool_at(art_point)
	if avatar.patch != patch:
		go_to_patch(patch, tool_id if tool_id != "" else patch.default_tool)
		return
	if tool_id != "":
		_select_tool(patch, tool_id)
		return
	# A bird perched above the island's outline (on the feeder roof) sits on the sky: with the
	# camera, a click on it is a photo, not "go home" (issue 68).
	var on_bird := avatar.tool_id == "camera" and not birds.find_at(patch, art_point).is_empty()
	if not patch.on_island(art_point) and not on_bird:
		go_home()
		return
	_use_tool(patch, avatar.tool_id, art_point)


## The avatar puffs out wherever it is and in on `patch`, holding `tool_id`. The island
## grows to the large size while the avatar is on it.
func go_to_patch(patch: PatchWindow, tool_id: String) -> void:
	var previous := avatar.patch
	patch.rescale(_active_scale())
	_clear_growth(patch)
	await avatar.poof_to_patch(patch, patch.arrival_point())
	refresh_capture(patch)
	_select_tool(patch, tool_id)
	if patch.mechanic != null:
		patch.mechanic.on_avatar_arrived()
	if previous != null:
		_left(previous)


func go_home() -> void:
	var previous := avatar.patch
	if previous == null:
		return
	await avatar.poof_home()
	if previous != null:
		_left(previous)


func _left(patch: PatchWindow) -> void:
	patch.select_tool("")
	patch.rescale(scale_px)
	refresh_capture(patch)
	if patch.mechanic != null:
		patch.mechanic.on_avatar_left()


## The island the avatar is on grows by `active_growth`, in whole device pixels and always larger.
func _active_scale() -> int:
	return maxi(scale_px + 1, roundi(scale_px * float(balance.data["display"]["active_growth"])))


func _select_tool(patch: PatchWindow, tool_id: String) -> void:
	avatar.tool_id = tool_id
	patch.select_tool(tool_id)


## The avatar does the job: the camera photographs a bird where it stands; other tools
## walk to the spot the island says, act, then the island's rules apply.
func _use_tool(patch: PatchWindow, tool_id: String, art_point: Vector2) -> void:
	avatar.busy = true
	var pack: IslandPack = packs.get(patch.def.id)
	var action := pack.tool_action(tool_id) if pack != null else ""
	if action == "":
		action = tool_id
	if tool_id == "camera":
		var visitor := birds.find_at(patch, art_point)
		if not visitor.is_empty():
			await _take_photo(patch, visitor, art_point)
		avatar.busy = false
		return
	if patch.mechanic == null:
		avatar.busy = false
		return
	await avatar.walk_to(patch.mechanic.stand_point(tool_id, art_point))
	if not patch.mechanic.animates_avatar(tool_id):
		await avatar.act(action, patch.mechanic.faces_into_island(tool_id, art_point))
	if not patch.mechanic.use_tool(tool_id, art_point):
		patch.mechanic.on_click(art_point)
	avatar.busy = false


## The avatar raises the camera to its face (its `photo` animation when the art has one),
## the shutter flashes the island, and the polaroid flies to the bin (issue 77).
func _take_photo(patch: PatchWindow, visitor: Dictionary, art_point: Vector2) -> void:
	var tuning: Dictionary = balance.data["photo"]
	avatar.show_doing("photo")
	var held := _held_camera(float(tuning["camera_height"]))
	await get_tree().create_timer(float(tuning["raise_sec"])).timeout
	_flash(patch, float(tuning["flash_peak"]), float(tuning["flash_sec"]))
	if held != null:
		_glint(held, int(tuning["glint_px"]), float(tuning["flash_sec"]))
	_photograph(patch, visitor, art_point)
	await get_tree().create_timer(float(tuning["hold_sec"])).timeout
	if held != null:
		held.queue_free()
		avatar.sprite.mark_changed()
	avatar.show_doing("idle")


## The camera held up before the avatar's face, sized to the depth it stands at; none when
## the avatar's own art has a `photo` pose.
func _held_camera(height: float) -> Sprite2D:
	var sprite := avatar.sprite
	if sprite.def.has_animation(sprite.layer, "photo"):
		return null
	var sheet: Dictionary = sprite.def.layers[sprite.layer]
	var front: Dictionary = avatar.def.layers.get(sprite.layer, sheet)
	var size_k := float((sheet["frame_size"] as Vector2i).y) / float((front["frame_size"] as Vector2i).y)
	var held := Sprite2D.new()
	held.name = "HeldCamera"
	held.texture = icon_for("camera")
	held.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	held.scale = Vector2.ONE * size_k
	held.position = Vector2(0, -float((sheet["frame_size"] as Vector2i).y) * height).round()
	sprite.add_child(held)
	sprite.mark_changed()
	return held


## The flash bulb itself: a white spot on the held camera, gone after `seconds`. A
## placeholder until the bench delivers `fx/camera_flash`.
func _glint(held: Sprite2D, size_px: int, seconds: float) -> void:
	var glint := Sprite2D.new()
	glint.name = "Glint"
	glint.texture = AssetLibrary.blob_texture(Vector2i(size_px, size_px), Color.WHITE)
	glint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	glint.position = (held.texture.get_size() * Vector2(-0.2, -0.3)).round()
	held.add_child(glint)
	avatar.sprite.mark_changed()
	get_tree().create_timer(seconds).timeout.connect(func() -> void:
		if is_instance_valid(glint):
			glint.queue_free()
			avatar.sprite.mark_changed())


## A short camera flash: the island lit up, fading back over `seconds`.
func _flash(patch: PatchWindow, peak: float, seconds: float) -> void:
	Pace.start_moving()
	patch.set_brightness(peak)
	var tween := create_tween()
	tween.tween_method(patch.set_brightness, peak, 1.0, seconds)
	tween.finished.connect(func() -> void:
		patch.set_brightness(1.0)
		Pace.stop_moving())


func _photograph(patch: PatchWindow, visitor: Dictionary, art_point: Vector2) -> bool:
	var item := birds.photograph(visitor)
	if item.is_empty():
		return false
	var first := journal.record("birds", String(item["id"]), day_key())
	print("VibeNature: polaroid of a %s%s" % [item["id"], " (new to the life list)" if first else ""])
	send_to_bin(item, patch.art_to_screen(art_point))
	return true


## Any click keeps the avatar out; a while with nothing happening sends it home.
func _touch() -> void:
	_idle_timer.start(float(balance.data["avatar"]["idle_return_sec"]))


func _on_idle() -> void:
	if avatar.busy or avatar.is_home():
		return
	var patch := avatar.patch
	if patch.mechanic != null and patch.mechanic.wants_all_clicks():
		_touch()
		return
	go_home()


## Puts `item` in the bin now (so nothing is lost if the game closes) and flies its
## picture there from `from_screen`.
func send_to_bin(item: Dictionary, from_screen: Vector2) -> void:
	economy.deposit(item)
	request_save()
	print("VibeNature: bin + %s %s (%d)" % [item["kind"], item["id"], int(item["value"])])
	courier.send(item_texture(item), from_screen, home.bin_screen_point, func() -> void: home.set_bin_full(true))


func item_texture(item: Dictionary) -> Texture2D:
	var kind := String(item["kind"])
	var id := String(item["id"])
	var key := "%s/%s" % [kind, id]
	if _textures.has(key):
		return _textures[key]
	var texture: Texture2D = null
	var item_size := AssetLibrary.vec2i(balance.data["placeholders"]["item"])
	match kind:
		"polaroid":
			texture = Polaroid.compose(AssetLibrary.load_texture("items", "polaroid", "polaroid"), birds.def_for(id),
					balance.data["polaroid"])
		"bouquet":
			texture = AssetLibrary.load_texture("items", "bouquet", "bouquet")
			if texture == null:
				texture = AssetLibrary.solid_texture(item_size, content.color_of("flowers", id))
		"honey":
			texture = AssetLibrary.load_texture("items", "honey_jar", "honey_jar")
			if texture == null:
				texture = AssetLibrary.solid_texture(item_size, Color("f9c22b"))
		"fish":
			var asset := content.asset_of("fish", id)
			texture = AssetLibrary.load_texture("fauna", asset, asset)
			if texture == null:
				texture = AssetLibrary.solid_texture(AssetLibrary.vec2i(balance.data["placeholders"]["fish"]) / 2,
						content.color_of("fish", id))
	if texture == null:
		texture = AssetLibrary.solid_texture(item_size, Color.WHITE)
	_textures[key] = texture
	return texture


## A tool's icon: its island pack's, else the game's delivery, else a square in the tool's
## colour until the art lands.
func icon_for(entry: String) -> Texture2D:
	var key := "icon/" + entry
	if not _textures.has(key):
		var item_size := AssetLibrary.vec2i(balance.data["placeholders"]["item"])
		var texture := AssetLibrary.image_texture(content.tool_icon_path(entry))
		_textures[key] = texture if texture != null else AssetLibrary.tool_icon(entry, item_size, content.tool_color(entry))
	return _textures[key]


func _on_world_signal(kind: String, _source: String) -> void:
	for patch in patches:
		if patch.mechanic != null:
			patch.mechanic.on_world_signal(kind)


func _on_rain() -> void:
	for patch in patches:
		if patch.mechanic != null:
			patch.mechanic.on_rain()


## At the first check of a new game day (dawn): the bin converts, the stipend arrives.
func _check_day() -> void:
	var before := economy.day_key
	var today := day_key()
	var added := economy.roll_over(today, int(balance.data["daily_stipend"]),
			int(balance.data["economy"]["stipend_catchup_days_max"]))
	if before == today:
		return
	if before != "":
		print("VibeNature: a new day, + %d bucks (%d in all)" % [added, economy.bucks])
		home.set_bin_full(false)
		home.set_bucks(economy.bucks)
		weather.new_day()
		journal.prune(int(balance.data["journal"]["days_kept"]))
		for patch in patches:
			if patch.mechanic != null:
				patch.mechanic.on_new_day()
		for id in collection.update(content.catalogue(), today):
			print("VibeNature: a new patch turned up: %s" % id)
		if not shelf_demo_on() and collection.out_today(content.catalogue(), settings.data["roster"], today) != patch_ids_out():
			_rebuild("a new set of patches for the day")
			return
	request_save()


## Flowers in bloom across every flower bed (the beehive works faster with them).
func blooming_flowers() -> int:
	var count := 0
	for patch in patches:
		if patch.mechanic != null:
			count += patch.mechanic.count_blooming(clock.now())
	return count


func dawn_minutes() -> int:
	return maxi(settings.day_phases().start_of("dawn"), 0)


func day_key() -> String:
	return clock.game_day_key(dawn_minutes())


## The daily rhythm (issue 198): the van brings you at the first sign of the day. Starting the app is one.
func _start_day_rhythm() -> void:
	day_rhythm = DailyRhythm.new(clock, settings.day_phases(), balance.data["daily_rhythm"], settings.wrap_up_minutes())
	day_rhythm.start_minutes = settings.start_of_day_minutes()
	day_rhythm.idle_sec = DailyRhythm.parse_idle(String(presence_source.call()))
	_mac_seen = DailyRhythm.parse_counts(String(mac_signals_source.call()))
	_day_poll_at = clock.now()
	var events := day_rhythm.launched(String(settings.data["van_day"]))
	if welcome_pending:
		# The first run (issue 199): the van drives in and you wait at its door while the welcome is open. With no
		# arrival now (night) it opens by itself after a moment.
		if events.has("arrive_now"):
			events = events.map(func(e: String) -> String: return "arrive_first" if e == "arrive_now" else e)
		else:
			get_tree().create_timer(float(balance.data["welcome"]["night_open_sec"])).timeout.connect(open_welcome)
	_play_day(events)
	if not day_rhythm.here:
		scene.day("leave_now")
	_day_poll_timer.timeout.connect(poll_day)
	add_child(_day_poll_timer)
	_day_poll_timer.start(float(balance.data["daily_rhythm"]["poll_sec"]))


## Reads the Mac's signals since the last look and lets the clock move the rhythm on. A sleep is
## only seen after the wake (the game is asleep too): it began about when the last poll ran.
func poll_day() -> void:
	if day_rhythm == null:
		return
	day_rhythm.idle_sec = DailyRhythm.parse_idle(String(presence_source.call()))
	var counts := DailyRhythm.parse_counts(String(mac_signals_source.call()))
	for kind in DailyRhythm.new_edges(_mac_seen, counts):
		_play_day(day_rhythm.mac(kind, _day_poll_at if kind in ["sleep", "lock"] else -1.0))
	_mac_seen = counts
	_play_day(day_rhythm.tick())
	_day_poll_at = clock.now()
	sync_login_item()
	if scene_mode and letters != null and letters.decided_day != day_key():
		_letters_overnight()


func _play_day(events: Array) -> void:
	for what in events:
		scene.day(String(what))
		_morning_card(String(what))
		if String(what).begins_with("arrive") and String(settings.data["van_day"]) != day_key():
			settings.data["van_day"] = day_key()
			settings.save()


## The demo's morning card (issue 268): on the day's first arrival only, never on the first run's welcome.
func _morning_card(what: String) -> void:
	if scene.demo_card == null or welcome_pending:
		return
	if not Edition.morning_card_due(Edition.is_demo(), what, day_key(), String(settings.data["demo_card_day"])):
		return
	settings.data["demo_card_day"] = day_key()
	settings.save()
	scene.demo_card.show_card()


## Config, General: the optional start-of-day time ("HH:MM", or "" for off; issue 431).
func set_start_of_day(at: String) -> void:
	settings.data["start_of_day"] = at
	settings.save()
	if day_rhythm != null:
		day_rhythm.start_minutes = settings.start_of_day_minutes()


## Config, General: the optional wrap-up time ("HH:MM", or "" for off).
func set_wrap_up(at: String) -> void:
	settings.data["wrap_up"] = at
	settings.save()
	if day_rhythm != null:
		day_rhythm.wrap_minutes = settings.wrap_up_minutes()


## The local minute of the day with its fraction, for the living scene's light.
func scene_minute() -> float:
	var now := clock.now()
	return float(clock.local_minutes()) + fposmod(now, 60.0) / 60.0


func is_night() -> bool:
	return settings.day_phases().is_night(clock.local_minutes())


## The light's phase: a step toward dusk after a long stretch of agent work (G4 tints by it).
func light_phase() -> String:
	return AgentBridge.light_phase(settings.day_phases(), clock.local_minutes(), bridge != null and bridge.long_stretch())


## Where agents reach the game: `bridge.port` (VIBENATURE_EVENT_PORT overrides); any free port
## in snapshots and headless tests, so they never take the real one.
func event_port() -> int:
	if Snapshot.on() or DisplayServer.get_name() == "headless":
		return 0
	var value := OS.get_environment("VIBENATURE_EVENT_PORT")
	return int(value) if value.is_valid_int() else int(balance.data["bridge"]["port"])


func rare_multiplier() -> float:
	return float(balance.data["golden_window_rare_multiplier"]) if signals.is_golden() else 1.0


func request_save() -> void:
	_save_timer.start(float(balance.data["save"]["debounce_sec"]))


## Option-click home: the debug panel, in development runs only (`just dev`),
## never in an exported build.
func _open_debug_panel() -> void:
	if not OS.is_debug_build():
		return
	if debug_panel == null:
		debug_panel = DebugPanel.new()
		debug_panel.setup(self)
		add_child(debug_panel)
		WindowChrome.draw_on_demand(debug_panel)
	if debug_panel.visible:
		debug_panel.hide_panel()
	else:
		debug_panel.open_near(get_window())


## Debug: move the game clock forward; everything that waits on time catches up.
func debug_advance(seconds: float) -> void:
	clock.advance(seconds)
	print("VibeNature debug: clock +%d min" % roundi(seconds / 60.0))
	for patch in patches:
		if patch.mechanic != null:
			patch.mechanic.on_time_jump()
	rhythm.on_time_jump()
	_check_day()


func debug_new_day() -> void:
	debug_advance(clock.next_local_time(dawn_minutes()) - clock.now() + 60.0)


## Debug: the van's whole arrival ("arrive") or departure ("leave") now, the rhythm agreeing (issue 431).
func debug_van(what: String) -> void:
	if scene == null or day_rhythm == null:
		return
	for e in day_rhythm.debug_play(what):
		scene.day(String(e))
	print("VibeNature debug: van %s" % what)


## What an agent finishing a turn will send once the bridge exists (G3).
func debug_agent_turn() -> void:
	for kind in ["sunlight", "bird_roll", "fish_roll"]:
		signals.send(kind, "debug")


func debug_rain() -> void:
	var threshold := int(balance.data["rain_clouds_threshold"])
	for i in threshold:
		signals.send("cloud", "debug")


func debug_toggle_golden() -> void:
	signals.set_golden("debug", not signals.is_golden())


func debug_bucks(amount: int) -> void:
	economy.bucks += amount
	home.set_bucks(economy.bucks)
	request_save()


## The next catalogue patch that would arrive on its own turns up now.
func debug_next_patch() -> void:
	for id in content.catalogue():
		var entry: Dictionary = content.catalogue()[id]
		if not collection.owned.has(id) and not entry.has("season"):
			collection.owned[id] = {"since": day_key(), "how": "arrived"}
			_rebuild("debug: %s arrived" % id)
			return
	print("VibeNature debug: every patch is already in the collection")


## Buys a patch early with patch bucks (the store, once the sign has one). It comes
## out at once, so the player meets it.
func buy_patch(id: String) -> bool:
	if not collection.buy(id, content.catalogue(), economy, day_key()):
		return false
	home.set_bucks(economy.bucks)
	_rebuild("bought %s" % id)
	return true


## Steps the patches' art scale through `display.art_scales` (smaller, default, large) and
## rebuilds every window at the new size. Each window keeps its bottom centre, so a
## patch grows up from where it sits. Birds mid-visit simply leave.
func change_scale(step: int) -> void:
	var allowed: Array = balance.data["display"]["art_scales"]
	var current := settings.art_scale(allowed)
	var index := -1
	for i in allowed.size():
		if is_equal_approx(float(allowed[i]), current):
			index = i
	var next := float(allowed[clampi(index + step, 0, allowed.size() - 1)])
	if is_equal_approx(next, current):
		return
	settings.data["art_scale"] = next
	settings.save()
	var before := Settings.device_scale(current)
	var after := Settings.device_scale(next)
	if after == before:
		return  # ½ on a 1× screen draws the same as default: nothing to rebuild
	if config != null and config.visible:
		_reopen_config = config.tabs.current_tab
	_rebuild("patches at %s" % scale_name(next), float(after) / float(before))


func scale_name(art: float) -> String:
	var display: Dictionary = balance.data["display"]
	var allowed: Array = display["art_scales"]
	for i in allowed.size():
		if is_equal_approx(float(allowed[i]), art):
			return String(display["scale_names"][i])
	return "x%s" % art


## Saves, then rebuilds every window: for a new scale, or a new day's patches (the
## ones not out keep their state in the save; new ones turn up in random places).
func _rebuild(reason: String, resize: float = 1.0) -> void:
	print("VibeNature: " + reason)
	save_now(resize)
	_quitting = true
	get_tree().reload_current_scene.call_deferred()


## `resize` (> 1 larger, < 1 smaller) saves each window's position for its size
## after a scale change, keeping its bottom centre where it is.
func save_now(resize: float = 1.0) -> void:
	# The shelf demo has no patches out; saving would forget where they were.
	if shelf_demo_on():
		return
	var states := _states.duplicate(true)
	var layout := {"home": _saved_position(get_window(), resize)}
	var ids: Array = []
	for patch in patches:
		if patch.mechanic != null:
			states[patch.def.id] = patch.mechanic.save_state()
		layout[patch.def.id] = _saved_position(patch, resize)
		ids.append(patch.def.id)
	save_game.write({
		"economy": economy.to_dict(),
		"journal": journal.to_dict(),
		"collection": collection.to_dict(),
		"weather": weather.to_dict(),
		"patch_ids": ids,
		"patches": states,
		"layout": layout,
		"scene": scene.behaviour.director.to_dict() if scene != null and scene.behaviour.director != null else {},
		"sightings": sightings.to_dict(),
		"letters": letters.to_dict() if letters != null else {},
	}.merged({"close_up": _close_up} if not _close_up.is_empty() else {}))


## A grown island (the avatar is on it) is saved at its usual size, about the same bottom centre.
func _saved_position(window: Window, resize: float) -> Array:
	var size := Vector2(window.size)
	var bottom_centre := Vector2(window.position) + Vector2(size.x / 2.0, size.y)
	var patch := window as PatchWindow
	if patch != null and patch.scale_px != scale_px:
		resize *= float(scale_px) / float(patch.scale_px)
	var at := (bottom_centre - Vector2(size.x * resize / 2.0, size.y * resize)).round()
	if patch != null and patch.placed_by_player:
		return [int(at.x), int(at.y), true]
	return [int(at.x), int(at.y)]


## Close up: save and quit. Config's General tab has this; so does the Dock icon.
func quit() -> void:
	if _quitting:
		return
	if no_scene != null:
		_quitting = true
		print("VibeNature: closed up")
		if exit_on_quit:
			get_tree().quit()
		return
	_quitting = true
	_close_up = _closing()
	save_now()
	settings.save()
	print("VibeNature: closed up")
	if exit_on_quit:
		get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and not _quitting and no_scene == null:
		_quitting = true
		_close_up = _closing()
		save_now()


## Closing up now: today, and whether it is before `dusk_close_threshold` (night visitors).
func _closing() -> Dictionary:
	return NightVisitors.closing(day_key(), clock.local_minutes(),
			DayPhases.minutes(String(balance.data["dusk_close_threshold"])), dawn_minutes())


## Writes this process's id to `path` (nothing when empty). Returns whether it did.
static func write_pid_file(path: String) -> bool:
	if path == "":
		return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("VibeNature: cannot write the pid file %s" % path)
		return false
	file.store_string(str(OS.get_process_id()))
	return true


static func shelf_demo_on() -> bool:
	return _env_string("VIBENATURE_SHELF_DEMO", "") == "1"


static func _env_string(name: String, fallback: String) -> String:
	var value := OS.get_environment(name)
	return value if value != "" else fallback


## One of the player's files: from its env override, else user://. A snapshot run keeps its
## own beside its images and never touches the player's.
## The living scene is the game: an exported app (the `template` feature, issue 196) always plays it. A dev run plays
## it with VIBENATURE_SCENE=1 (`just dev`), else the old island game (`just dev-islands`); snapshots by their path.
static func wants_scene(env_scene: String, exported: bool, snapshot_scene: bool) -> bool:
	return exported or env_scene == "1" or snapshot_scene


static func _user_path(env: String, file: String, fallback: String) -> String:
	if Snapshot.on():
		return Snapshot.user_dir().path_join(file)
	return _env_string(env, fallback)


static func _env_float(name: String, fallback: float) -> float:
	var value := OS.get_environment(name)
	return float(value) if value.is_valid_float() else fallback
