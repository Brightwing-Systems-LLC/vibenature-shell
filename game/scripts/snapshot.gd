class_name Snapshot
extends Node

## Snapshot mode (`just snap`, VIBENATURE_SNAPSHOT=1): the real game, driven from inside by the
## same handlers a click calls, saving a PNG of every window at each step of the demo path and
## one combined image. Nothing reaches the player's screens or mouse: every Window is embedded
## in the root window, the root is placed far off screen, and the native extension keeps the
## app Prohibited and its windows invisible. The player's files are never read or written: a
## snapshot keeps its own beside its images. The clock and the dice are pinned (balance.json
## `snapshot`), so two runs draw the same pictures.
##
## Writes `<out>/<step>__<window>.png`, `<out>/<step>__all.png`, `<out>/<step>__layout.png` (the
## islands where they sit on the screen, so overlaps show) and `<out>/report.json`
## (each step, what was checked, and `ok`). Quits 0 when every check held, else 1.

signal finished(ok: bool)

const OUT_ENV := "VIBENATURE_SNAPSHOT_OUT"
const DEFAULT_OUT := "user://snapshot"
const ARG := "--vibenature-snapshot"
const OUT_ARG := "--snapshot-out="
const PATH_ENV := "VIBENATURE_SNAPSHOT_PATH"
const PATH_ARG := "--snapshot-path="
## The paths a run can take: the demo, every tool on every island (issue 68), agent weather (issue 81),
## the living scene's stills (`scene`), a recorded clip of it (`clip`, issue 98), its controls (`controls`, issue 169), the book (`book`, issue 177), or taking a photo (`photo`, issue 176).
const PATHS: Array[String] = ["demo", "activity", "weather", "scene", "clip", "controls", "book", "photo", "avatar", "rhythm", "letters", "welcome", "demo_card", "corner", "rain_corner"]
## The paths that run the living scene on its own.
const SCENE_PATHS: Array[String] = ["scene", "clip", "controls", "book", "photo", "avatar", "rhythm", "letters", "welcome", "demo_card", "corner", "rain_corner"]

var game: Game
var tuning: Dictionary = {}
var out_dir := ""
## Tests run the path inside their own tree and keep it running afterwards.
var quit_at_end := true
var steps: Array = []
var _checks: Array = []
var _failures := 0
var _done := false
var _rendered := true


## VIBENATURE_SNAPSHOT=1, or `-- --vibenature-snapshot` (what `just snap` passes; the native
## extension reads the same argument).
static func on() -> bool:
	var value := OS.get_environment("VIBENATURE_SNAPSHOT")
	return (value != "" and value != "0") or OS.get_cmdline_user_args().has(ARG)


## Where the images and the report go (absolute, or a user:// path): VIBENATURE_SNAPSHOT_OUT,
## or `--snapshot-out=<dir>` after `--`.
static func out_path() -> String:
	var value := OS.get_environment(OUT_ENV)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(OUT_ARG):
			value = arg.trim_prefix(OUT_ARG)
	return value if value != "" else DEFAULT_OUT


## Which path to run: VIBENATURE_SNAPSHOT_PATH, or `--snapshot-path=<name>` after `--`; "demo"
## unless it names another of PATHS.
static func path_name() -> String:
	var value := OS.get_environment(PATH_ENV)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with(PATH_ARG):
			value = arg.trim_prefix(PATH_ARG)
	return value if PATHS.has(value) else "demo"


## The run's own settings, save and installed islands.
static func user_dir() -> String:
	return out_path().path_join("user")


## Before any other window exists: every Window is drawn inside the root, the root sits far
## outside every screen, and it renders to its own texture so it can be read back. The run's
## own user folder is made.
static func prepare(root: Window, snapshot_tuning: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(user_dir()))
	root.gui_embed_subwindows = true
	root.always_on_top = false
	root.unfocusable = true
	root.position = AssetLibrary.vec2i(snapshot_tuning["offscreen_px"])
	RenderingServer.viewport_set_render_direct_to_screen(root.get_viewport_rid(), false)


## Today (or tomorrow) at `start_local`, so the run is in daylight and draws the same each time.
static func pin_clock(clock: GameClock, snapshot_tuning: Dictionary) -> void:
	clock.set_now(clock.next_local_time(DayPhases.minutes(String(snapshot_tuning["start_local"]))))


func run(owner_game: Game) -> void:
	game = owner_game
	tuning = game.balance.data["snapshot"]
	out_dir = ProjectSettings.globalize_path(out_path())
	DirAccess.make_dir_recursive_absolute(out_dir)
	_rendered = DisplayServer.get_name() != "headless"
	_write("godot.pid", str(OS.get_process_id()))
	var path := Snapshot.path_name()
	var limit := float(tuning["max_run_sec"])
	if path == "activity":
		limit = float(tuning["activity_max_run_sec"])
	elif path in SCENE_PATHS:
		limit = float(tuning["clip_max_run_sec"])
	var watchdog := get_tree().create_timer(limit)
	watchdog.timeout.connect(func() -> void:
		if not _done:
			_expect(false, "the %s path finished within %s s" % [path, limit])
			_finish())
	await _settle()
	if path == "controls":
		await SnapshotControls.new(self).run()
		_finish()
		return
	if path == "corner":
		await SnapshotControls.new(self).run_corners()
		_finish()
		return
	if path == "rain_corner":
		await SnapshotControls.new(self).run_rain_corners()
		_finish()
		return
	if path == "book":
		await SnapshotBook.new(self).run()
		_finish()
		return
	if path == "photo":
		await SnapshotPhoto.new(self).run()
		_finish()
		return
	if path == "avatar":
		await SnapshotAvatar.new(self).run()
		_finish()
		return
	if path == "rhythm":
		await SnapshotRhythm.new(self).run()
		_finish()
		return
	if path == "letters":
		await SnapshotLetters.new(self).run()
		_finish()
		return
	if path == "welcome":
		await SnapshotWelcome.new(self).run()
		_finish()
		return
	if path == "demo_card":
		await SnapshotDemoCard.new(self).run()
		_finish()
		return
	if path in SCENE_PATHS:
		await SnapshotScene.new(self).run(path)
		_finish()
		return

	_expect(game.config.visible and game.config.tabs.current_tab == ConfigWindow.AVATAR,
			"the first launch shows Config on the Avatar tab")
	await _capture("01_first_launch")

	# The six whole avatars are no longer chosen here (issue 202): the worn one is shown.
	var worn := AvatarLook.island_avatar_id(game.settings.data["avatar"], game.balance.data["avatar_looks"])
	_expect(game.avatar.avatar_id == worn, "the avatar for the look's body (%s) is worn (got %s)" % [worn, game.avatar.avatar_id])
	_expect(game.config.find_child("worn_avatar", true, false) != null, "the Avatar tab shows the avatar worn, not a choice")
	await _capture("02_avatar_picked")

	game.config.close_config()
	await _settle()
	_expect(not game.config.visible, "Config is closed")
	_expect(game.patches.size() == 3, "three islands are out (got %d)" % game.patches.size())
	_expect(game.avatar.is_home(), "the avatar sits at home")
	await _capture("03_home")

	if path == "activity":
		await SnapshotActivity.new(self).run()
		_finish()
		return
	if path == "weather":
		await SnapshotWeather.new(self).run()
		_finish()
		return

	var index := 4
	for patch in game.patches:
		await _visit(patch)
		var stand := _stand_point(patch)
		_expect(game.avatar.patch == patch and game.avatar.art_position() == stand,
				"the avatar stands on %s's stand spot %s (at %s)" % [patch.def.id, stand, game.avatar.art_position()])
		await _capture("%02d_island_%s" % [index, patch.def.id])
		index += 1

	game.debug_advance(float(tuning["skip_minutes"]) * 60.0)
	var wanted := int(tuning["birds"])
	for i in wanted:
		game.birds.spawn()
	var perched := await _until(func() -> bool: return _perched().size() >= wanted)
	_expect(perched, "%d birds sit on perches (%s)" % [wanted, ", ".join(_perched())])
	await _capture("%02d_birds" % index)
	index += 1

	var pond := _patch_with("fishing_hole")
	_expect(pond != null, "the fishing hole is out")
	if pond != null:
		if game.avatar.patch != pond:
			await _visit(pond)
		var water: Vector2 = pond.mechanic.get("_water")
		game._on_patch_clicked(pond, MOUSE_BUTTON_LEFT, water)
		var bobber: CreatureSprite = pond.mechanic.get("_bobber")
		var cast := await _until(func() -> bool: return bobber.visible and not game.avatar.busy)
		await _settle()
		_expect(cast and bobber.position == water, "the bobber floats on the water spot %s (at %s, shown %s)" % [water, bobber.position, bobber.visible])
		await _capture("%02d_fishing" % index)
		index += 1

	game._on_bench_clicked()
	var home := await _until(func() -> bool: return game.avatar.is_home() and not game.avatar.busy)
	await _settle()
	_expect(home, "the bench click brings the avatar home")
	await _capture("%02d_back_home" % index)
	_finish()


## Extra facts for the report (the activity path puts the journal here).
var notes: Dictionary = {}


func _visit(patch: PatchWindow) -> void:
	game._on_patch_clicked(patch, MOUSE_BUTTON_LEFT, patch.arrival_point())
	await _until(func() -> bool: return game.avatar.patch == patch and not game.avatar.busy)
	await _settle()


## The island's `stand` spot (where the avatar appears), else where the game puts it.
func _stand_point(patch: PatchWindow) -> Vector2:
	var stands := patch.def.spots_of_kind("stand")
	return patch.spot_point(stands[0]) if not stands.is_empty() else patch.arrival_point()


## "island/spot" for each bird sitting still on its perch.
func _perched() -> Array[String]:
	var out: Array[String] = []
	for visitor in game.birds.visitors:
		var creature: Creature = visitor["creature"]
		var patch: PatchWindow = visitor["patch"]
		var spot := String(visitor["spot"])
		if creature.host_window() == patch and creature.art_position() == patch.spot_point(spot) and creature.sprite.anim == "idle":
			out.append("%s/%s" % [patch.def.id, spot])
	return out


func _patch_with(kind: String) -> PatchWindow:
	for patch in game.patches:
		if patch.mechanic != null and patch.mechanic.kind() == kind:
			return patch
	return null


## Every window the player would see: home, Config if open, each island out.
func _windows() -> Dictionary:
	var out := {"home": game.get_window()}
	if game.scene != null and game.scene.visible:
		out["scene"] = game.scene
	if game.config.visible:
		out["config"] = game.config
	for patch in game.patches:
		if patch.visible:
			out[patch.def.id] = patch
	# What is in the air between windows: a bouquet, fish or polaroid flying to the bin, a bird
	# crossing.
	var flying := 0
	for parent: Node in [game.courier, game.birds]:
		if parent == null:
			continue
		for child in parent.get_children():
			if child is TransitWindow and (child as Window).visible:
				out["flying_%d" % flying] = child
				flying += 1
	return out


## Draws every window once, now, and saves each and all of them side by side.
func _capture(step: String) -> void:
	var windows := _windows()
	var files: Array[String] = []
	var islands: Array = []
	for patch in game.patches:
		if patch.visible:
			islands.append(patch)
	for i in islands.size():
		for j in range(i + 1, islands.size()):
			var a: PatchWindow = islands[i]
			var b: PatchWindow = islands[j]
			_expect(a.placed_by_player or b.placed_by_player or not Rect2i(a.position, a.size).intersects(Rect2i(b.position, b.size)),
					"%s: %s and %s do not overlap" % [step, a.def.id, b.def.id])
	if _rendered:
		for key in windows:
			WindowChrome.redraw(windows[key])
		# Hidden and Prohibited, the app may never get a frame of its own; draw without presenting.
		RenderingServer.force_draw(false)
		var images: Array[Image] = []
		for key in windows:
			var image: Image = (windows[key] as Window).get_texture().get_image()
			if image == null or image.is_empty():
				_expect(false, "%s: the %s window rendered" % [step, key])
				continue
			image.convert(Image.FORMAT_RGBA8)
			var file := "%s__%s.png" % [step, key]
			image.save_png(out_dir.path_join(file))
			files.append(file)
			images.append(image)
		if not images.is_empty():
			var file := "%s__all.png" % step
			_combined(images).save_png(out_dir.path_join(file))
			files.append(file)
		var placed: Array[Window] = []
		for patch: PatchWindow in islands:
			placed.append(patch)
		if not placed.is_empty():
			var file := "%s__layout.png" % step
			_layout(placed).save_png(out_dir.path_join(file))
			files.append(file)
	steps.append({"step": step, "windows": windows.keys(), "files": files, "checks": _checks.duplicate()})
	_checks.clear()
	print("VibeNature snapshot: %s (%d files)" % [step, files.size()])


## The windows in a row, bottom-aligned, on the sky colour.
func _combined(images: Array[Image]) -> Image:
	var gap := int(tuning["combined_gap_px"])
	var width := gap
	var height := 0
	for image in images:
		width += image.get_width() + gap
		height = maxi(height, image.get_height())
	var out := Image.create_empty(width, height + gap * 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(String(tuning["combined_background"])))
	var x := gap
	for image in images:
		out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(x, gap + height - image.get_height()))
		x += image.get_width() + gap
	return out


## The islands where they sit, relative to each other, at `layout_scale`, each window's
## outline drawn so an overlap of windows shows even where their sky is clear.
func _layout(windows: Array[Window]) -> Image:
	var k := float(tuning["layout_scale"])
	var gap := int(tuning["combined_gap_px"])
	var bounds := Rect2i(windows[0].position, windows[0].size)
	for w in windows:
		bounds = bounds.merge(Rect2i(w.position, w.size))
	var out := Image.create_empty(int(bounds.size.x * k) + gap * 2, int(bounds.size.y * k) + gap * 2, false, Image.FORMAT_RGBA8)
	out.fill(Color(String(tuning["combined_background"])))
	for w in windows:
		var image: Image = w.get_texture().get_image()
		if image == null or image.is_empty():
			continue
		image.convert(Image.FORMAT_RGBA8)
		image.resize(maxi(1, int(image.get_width() * k)), maxi(1, int(image.get_height() * k)), Image.INTERPOLATE_NEAREST)
		var at := Vector2i(Vector2(w.position - bounds.position) * k) + Vector2i(gap, gap)
		out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), at)
		var edge := Color(0, 0, 0, 0.5)
		var r := Rect2i(at, image.get_size())
		out.fill_rect(Rect2i(r.position.x, r.position.y, r.size.x, 1), edge)
		out.fill_rect(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), edge)
		out.fill_rect(Rect2i(r.position.x, r.position.y, 1, r.size.y), edge)
		out.fill_rect(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), edge)
	return out


func _expect(condition: bool, what: String) -> void:
	_checks.append({"what": what, "ok": condition})
	if not condition:
		_failures += 1
		printerr("VibeNature snapshot: FAILED: " + what)


func _finish() -> void:
	if _done:
		return
	_done = true
	if not _checks.is_empty():
		steps.append({"step": "end", "windows": [], "files": [], "checks": _checks.duplicate()})
	var ok := _failures == 0
	_write("report.json", JSON.stringify({"ok": ok, "rendered": _rendered, "failures": _failures, "path": Snapshot.path_name(), "notes": notes, "steps": steps}, "  "))
	print("VibeNature snapshot: %s, %d step(s), images in %s" % ["passed" if ok else "FAILED", steps.size(), out_dir])
	finished.emit(ok)
	if not quit_at_end:
		return
	if ok:
		game.quit()
	else:
		get_tree().quit(1)


func _write(file_name: String, text: String) -> void:
	var file := FileAccess.open(out_dir.path_join(file_name), FileAccess.WRITE)
	if file != null:
		file.store_string(text)


func _settle() -> Signal:
	return get_tree().create_timer(float(tuning["settle_sec"])).timeout


## Waits (polling) until `condition` holds or the step times out; true if it held.
func _until(condition: Callable) -> bool:
	var left := float(tuning["step_timeout_sec"])
	while not condition.call():
		if left <= 0.0 or _done:
			return false
		await get_tree().create_timer(0.05).timeout
		left -= 0.05
	return true
