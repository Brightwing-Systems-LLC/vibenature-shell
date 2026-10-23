class_name SnapshotWelcome
extends RefCounted

## The first run (issue 199), off screen: the van drives in, you
## step out in the plain look and the welcome opens; each step as a still (the window at 1:1, the window beside
## the scene, and a phone-sized copy); Done, you walk to the log and sit, and the first letter waits in the journal (no envelope: issue 270 reads it on the log). Every frame of
## that run is also drawn as the desktop would show it (the welcome to the left of the scene, bottom edges level)
## into `<out>/frames/%05d.png` at half size, for `ffmpeg` to make the clip; the stretch out of sight behind the near
## bank is cut short. The connect step runs the installer only on the snapshot's own home (`<out>/user/home`).
## `game/tools/snap.sh <godot> <out> welcome`.

const PHONE_WIDTH := 1170
const DESKTOP := "3a3f44"
const GAP := 16

var s: Snapshot
var game: Game
var clips: Dictionary
var _frame := 0
var _fps := 30.0
var _every := 2


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	clips = game.balance.data["scene"]["clips"]
	_fps = float(clips["fps"])


func run() -> void:
	Pace.start_moving()
	DirAccess.make_dir_recursive_absolute(s.out_dir.path_join("frames"))
	var scene := game.scene
	s._expect(game.welcome_pending, "the first launch has the welcome to come")
	s._expect(game.letters.waiting().is_empty(), "no letter before the welcome")
	SnapshotScene.apply(scene, clips["presets"]["van_arrive"], clips)
	scene.set_random_visits(false)
	scene.day("arrive_first")
	var dt := 1.0 / _fps
	for i in int(60.0 * _fps):
		if game.welcome != null and game.welcome.visible:
			break
		scene.advance(dt, scene.minute)
		await _record(false)
	var w := game.welcome
	s._expect(w != null and w.visible and scene.van.waiting_at_door(), "you stepped out at the van's door and the welcome opened")
	if w == null:
		Pace.stop_moving()
		return
	s._expect(not scene.van.far.is_empty() or not scene.van.walks(), "you stand on the far bank by the van")
	await _hold(0.8)
	await _still("welcome_1_you")
	w.avatar_picker.choose("look", "look03")
	await _hold(0.6)
	w.avatar_picker.choose("skin", "s4_warm")
	await _hold(0.4)
	w.avatar_picker.choose("van_body", "forest_green")
	w.avatar_picker.choose("van_accent", "cream")
	s._expect(VanPaint.key(game.van_paint()) == "forest_green|cream" and VanPaint.key(scene.van.paint) == "forest_green|cream",
			"the welcome's van colours are saved and on the van at the bank")
	await _hold(0.8)
	await _still("welcome_1_you_chosen")
	w.go_next()
	await _hold(0.8)
	await _still("welcome_2_elder")
	(w.find_child("Elder_walt", true, false) as Button).pressed.emit()
	await _hold(0.8)
	await _still("welcome_2_elder_walt")
	(w.find_child("Elder_june", true, false) as Button).pressed.emit()
	w.go_next()
	await _hold(1.0)
	await _still("welcome_3_wrap_up")
	(w.find_child("NoThanks", true, false) as Button).pressed.emit()
	await _hold(0.6)
	await _still("welcome_4_connect")
	(w.find_child("ConnectPlan", true, false) as Button).pressed.emit()
	s._expect(w.connector.home.begins_with(ProjectSettings.globalize_path(Snapshot.user_dir())), "the connect step reads only the snapshot's own home")
	s._expect(w.connect_words.get_child_count() > 0, "Connect… shows the dry run in plain words")
	await _hold(1.6)
	await _still("welcome_4_connect_plan")
	(w.find_child("ConnectNow", true, false) as Button).pressed.emit()
	s._expect(w.claude_status.text.begins_with("Hook installed"), "Connect connects (the snapshot's home)")
	await _hold(0.8)
	await _still("welcome_4_connect_done")
	w.go_next()
	await _hold(1.0)
	await _still("welcome_5_open_at_login")
	w.go_next()
	s._expect(not w.visible and not game.welcome_pending, "Done closes the welcome")
	var first := game.letters.waiting()
	s._expect(String(first.get("id", "")) == "first", "the first letter waits after the welcome")
	await _still("welcome_6_walk_on", false)
	var hidden := 0
	for i in int(80.0 * _fps):
		scene.advance(dt, scene.minute)
		var van := scene.van
		var out_of_sight := van.state == "arriving" and van.far.is_empty() and not bool(van.near.get("show", false)) and van.sitter_alpha == 0.0
		if out_of_sight:
			hidden += 1
			# The 20 s out of sight behind the near bank, cut to about a second in the clip.
			if hidden > int(_fps):
				continue
		await _record(false)
		if van.state == "parked" and not scene.sitter.standing():
			break
	s._expect(scene.van.state == "parked" and not scene.sitter.standing(), "you sit on the log")
	await _hold(3.5, false)
	s._expect(String(game.letters.waiting().get("id", "")) == "first", "seated, the first letter waits in the journal")
	await _still("welcome_7_seated", false)
	game.toggle_scene_config()
	game.scene_config.tabs.current_tab = SceneConfigWindow.ELDER
	await _frames()
	_save(_grab(game.scene_config), "welcome_8_config_elder")
	game.scene_config.tabs.current_tab = SceneConfigWindow.GENERAL
	await _frames()
	_save(_grab(game.scene_config), "welcome_8_config_general")
	game.scene_config.close_config()
	s.notes["welcome_frames"] = _frame
	s.notes["welcome_fps"] = _fps / float(_every)
	Pace.stop_moving()


## Runs the scene on for `seconds`, recording, with the welcome where it is.
func _hold(seconds: float, with_welcome: bool = true) -> void:
	# A step change lays out on the next frames: never record the page before its content is there.
	await _frames()
	for i in int(seconds * _fps):
		game.scene.advance(1.0 / _fps, game.scene.minute)
		await _record(with_welcome)


var _tick := 0


func _record(with_welcome: bool) -> void:
	_tick += 1
	if _tick % _every != 0 or DisplayServer.get_name() == "headless":
		if _tick % 10 == 0:
			await game.get_tree().process_frame
		return
	var desk := _desktop(with_welcome)
	if desk == null:
		return
	desk.resize(desk.get_width() / 2, desk.get_height() / 2, Image.INTERPOLATE_LANCZOS)
	_frame += 1
	desk.save_png(s.out_dir.path_join("frames/%05d.png" % _frame))


## The scene and (if shown) the welcome as on the desktop: the welcome left of the scene, bottom edges level.
func _desktop(with_welcome: bool) -> Image:
	var scene := _grab(game.scene)
	if scene == null:
		return null
	var w := game.welcome
	var welcome_size := w.size if w != null else Vector2i.ZERO
	var width := welcome_size.x + GAP + scene.get_width()
	var height := maxi(welcome_size.y, scene.get_height())
	width += width % 4
	height += height % 4
	var out := Image.create_empty(width, height, false, Image.FORMAT_RGBA8)
	out.fill(Color(DESKTOP))
	out.blend_rect(scene, Rect2i(Vector2i.ZERO, scene.get_size()), Vector2i(width - scene.get_width(), height - scene.get_height()))
	if with_welcome and w != null and w.visible:
		var image := _grab(w)
		if image != null:
			out.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(0, height - image.get_height()))
	return out


## A still of this moment: the welcome at 1:1, the desktop (1:1) and a phone-sized copy of it.
func _still(step: String, with_welcome: bool = true) -> void:
	await _frames()
	var files: Array = []
	if with_welcome and game.welcome != null and game.welcome.visible:
		_save(_grab(game.welcome), step + "__welcome_1x")
		files.append(step + "__welcome_1x.png")
	var desk := _desktop(with_welcome)
	if desk != null:
		_save(desk, step + "__desktop_1x")
		var phone := desk.duplicate() as Image
		phone.resize(PHONE_WIDTH, int(round(float(desk.get_height()) * PHONE_WIDTH / desk.get_width())), Image.INTERPOLATE_LANCZOS)
		_save(phone, step + "__phone")
	print("VibeNature snapshot: %s" % step)


func _save(image: Image, step: String) -> void:
	if image == null:
		return
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(DESKTOP))
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	flat.save_png(s.out_dir.path_join("%s.png" % step))
	s.steps.append({"step": step, "windows": [], "files": ["%s.png" % step], "checks": []})


func _frames() -> void:
	await game.get_tree().process_frame
	await game.get_tree().process_frame


func _grab(window: Window) -> Image:
	if DisplayServer.get_name() == "headless" or window == null:
		return null
	WindowChrome.redraw(window)
	RenderingServer.force_draw(false)
	var image: Image = window.get_texture().get_image()
	if image == null or image.is_empty():
		s._expect(false, "the %s window rendered" % window.title)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
