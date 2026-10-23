class_name SnapshotAvatar
extends RefCounted

## Stills of the avatar's looks (Skypatch issue 202), off screen:
## Config's Avatar tab on Body 1 and Body 2 and with the hair row hidden (look 5); the whole scene at full
## size with three looks and colour choices on the log, each with a 1:1 crop round the seat; and one look
## through every frame of its seated sheet, from the game's own render. `game/tools/snap.sh <godot> <out> avatar`.

const PRESET := "calm"
## [step, the picks in order]
const PICKERS: Array = [
	["picker_body1", [["body", 1], ["look", "look02"], ["hair", "auburn"], ["skin", "s2_cool"], ["top", "blue"]]],
	["picker_body2", [["body", 2], ["look", "look10"], ["hair", "teal"], ["skin", "s4_cool"], ["top", "charcoal"]]],
	["picker_look5_no_hair_row", [["body", 1], ["look", "look05"], ["skin", "s5_warm"], ["top", "olive"]]],
	["picker_van_red_cream", [["van_body", "red"], ["van_accent", "cream"]]],
	["picker_van_sky_blue_white", [["van_body", "sky_blue"], ["van_accent", "white"]]],
]
const ON_LOG: Array = [
	{"look": "look03", "skin": "s1_cool", "hair": "auburn", "top": "navy"},
	{"look": "look07", "skin": "s6_warm", "hair": "black", "top": "mustard"},
	{"look": "look10", "skin": "s3_cool", "hair": "pink", "top": "green"},
]
const STRIP_LOOK := {"look": "look09", "skin": "s4_warm", "hair": "auburn", "top": "red"}

var s: Snapshot
var game: Game
var _scene_shots: SnapshotScene


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	_scene_shots = SnapshotScene.new(owner)


func run() -> void:
	Pace.start_moving()
	await _ready_scene()
	game.scene_config.open(SceneConfigWindow.AVATAR)
	var picker := game.scene_config.avatar_picker
	for shot in PICKERS:
		for pick in shot[1]:
			picker.choose(String(pick[0]), pick[1])
		await game.get_tree().process_frame
		await game.get_tree().process_frame
		var step := String(shot[0])
		if step.begins_with("picker_van"):
			var want := {"body": String(shot[1][0][1]), "accent": String(shot[1][1][1])}
			s._expect(VanPaint.key(game.van_paint()) == VanPaint.key(want) and VanPaint.key(game.scene.van.paint) == VanPaint.key(want),
					"%s: the van's paint is saved and on the van" % step)
			s._expect(picker.rows["van"].visible and picker.van_preview.texture != null, "%s: Your van shows its paint" % step)
		elif step.contains("look5"):
			s._expect(not picker.rows["hair"].visible, "look 5: the hair row is hidden")
		else:
			s._expect(picker.rows["hair"].visible, "%s: the hair row shows" % step)
		s._expect(AvatarLook.key(picker.look) == AvatarLook.key(game.avatar_look()), "%s: the picker shows the saved look" % step)
		_save(game.scene_config, step)
	game.scene_config.close_config()
	var crops: Array[Image] = []
	for n in ON_LOG.size():
		game.set_avatar_look(ON_LOG[n])
		s._expect(game.scene.sitter.composed.get("key", "") == AvatarLook.key(ON_LOG[n]), "log %d: the sitter wears the look" % n)
		var crop := await _save_log(n)
		if crop != null:
			crops.append(crop)
	_join(crops, "log_crops_1x.png")
	await _strip()
	Pace.stop_moving()


func _ready_scene() -> void:
	var scene := game.scene
	SnapshotScene.apply(scene, _scene_shots.clips["presets"][PRESET], _scene_shots.clips)
	scene.set_random_visits(false)
	await _scene_shots.play(scene, PRESET, 2.0)
	await game.get_tree().process_frame


## The whole scene at full size with whoever sits on the log now, and a 1:1 crop round the seat.
func _save_log(n: int) -> Image:
	await game.get_tree().process_frame
	var image := _grab(game.scene)
	if image == null:
		return null
	image.save_png(s.out_dir.path_join("scene_full_%d.png" % n))
	var crop := image.get_region(_seat_rect(image))
	crop.save_png(s.out_dir.path_join("log_%d_1x.png" % n))
	s.steps.append({"step": "log_%d" % n, "windows": ["scene"], "files": ["scene_full_%d.png" % n, "log_%d_1x.png" % n], "checks": []})
	return crop


func _seat_rect(image: Image) -> Rect2i:
	var sitter := game.scene.sitter
	var at := Vector2i((sitter.seat * game.scene.scale_px).round())
	var half := Vector2i(130, 170)
	return Rect2i(at - Vector2i(half.x, half.y + 70), half * 2).intersection(Rect2i(Vector2i.ZERO, image.get_size()))


## One look through every frame of its seated sheet (the frames every log animation plays), as drawn in the scene.
func _strip() -> void:
	game.set_avatar_look(STRIP_LOOK)
	var sitter := game.scene.sitter
	var frames: Array[Image] = []
	var count := int((sitter.composed["image"] as Image).get_width() / int(sitter.composed["meta"]["frame_w"]))
	for f in count:
		sitter._shown = -1
		sitter._show(f)
		await game.get_tree().process_frame
		var image := _grab(game.scene)
		if image == null:
			return
		frames.append(image.get_region(_seat_rect(image)))
	s._expect(frames.size() == 13, "the strip has the sheet's 13 frames (got %d)" % frames.size())
	_join(frames, "strip_look09_1x.png", 13)
	s.steps.append({"step": "strip", "windows": ["scene"], "files": ["strip_look09_1x.png"], "checks": []})


func _join(images: Array[Image], file: String, cols: int = 3) -> void:
	if images.is_empty():
		return
	var w := images[0].get_width()
	var h := images[0].get_height()
	var grid := Image.create_empty(w * cols, h * ceili(images.size() / float(cols)), false, Image.FORMAT_RGBA8)
	for i in images.size():
		grid.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i((i % cols) * w, (i / cols) * h))
	grid.save_png(s.out_dir.path_join(file))


func _save(window: Window, step: String) -> void:
	var image := _grab(window)
	if image == null:
		return
	image.save_png(s.out_dir.path_join("%s.png" % step))
	s.steps.append({"step": step, "windows": [window.title], "files": ["%s.png" % step], "checks": []})
	print("VibeNature snapshot: %s" % step)


func _grab(window: Window) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	WindowChrome.redraw(window)
	RenderingServer.force_draw(false)
	var image: Image = window.get_texture().get_image()
	if image == null or image.is_empty():
		s._expect(false, "the %s window rendered" % window.title)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
