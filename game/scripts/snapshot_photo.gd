class_name SnapshotPhoto
extends RefCounted

## Stills of taking a photo (Skypatch issue 176), off
## screen: the viewfinder over the scene, the photo it takes, the flash, a frame over the strip's
## corner (the strip is not in the photo), and the book showing the photos.
## `game/tools/snap.sh <godot> <out> photo`.

const PRESET := "calm"
const DESKTOP := "4a5a6a"

var s: Snapshot
var game: Game
var _scene_shots: SnapshotScene


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	_scene_shots = SnapshotScene.new(owner)


func run() -> void:
	Pace.start_moving()
	var scene := game.scene
	var finder := scene.viewfinder
	s._expect(finder != null, "scene mode has the viewfinder")
	if finder == null:
		return
	SnapshotScene.apply(scene, _scene_shots.clips["presets"][PRESET], _scene_shots.clips)
	scene.set_random_visits(false)
	scene.behaviour.spawn("deer", "debug")
	await _scene_shots.play(scene, PRESET, 6.0)
	var deer: SceneCreature = null
	for c in scene.behaviour.creatures:
		if (c as SceneCreature).sp.id == "deer":
			deer = c
	var aim: Vector2 = deer.pos + Vector2(0, -40) if deer != null else finder.bounds.get_center()

	game.scene.controls.press("photo")
	s._expect(finder.is_open, "📷 opens the viewfinder")
	finder.center_pt = aim
	finder.resize(-3.0)
	await _frames()
	_scene_still("photo_1_viewfinder")

	finder.button(MOUSE_BUTTON_LEFT, Vector2(finder.rect().get_center() * scene.scale_px))
	s._expect(not finder.is_open and not scene.hit.regions.has(SceneViewfinder.REGION), "the shot closes the viewfinder and gives the clicks back")
	s._expect(game.last_photo != "", "the photo is in the album")
	var first := game.album.image(game.last_photo) if game.last_photo != "" else null
	if first != null:
		first.save_png(s.out_dir.path_join("photo_2_photo.png"))
		_step("photo_2_photo")
		var meta: Dictionary = game.album.photos()[0]
		s._expect(deer == null or (meta["species"] as Array).has("deer"), "the deer in the frame is in its species (%s)" % [meta["species"]])
	await game.get_tree().process_frame
	_scene_still("photo_3_flash")
	for i in 30:
		finder.step(0.05, null)

	# A frame over the strip's corner: the strip is in the scene, never in the photo.
	game.scene.controls.press("photo")
	finder.resize(-20.0)
	finder.center_pt = Vector2(finder.bounds.end.x, finder.bounds.position.y)
	await _frames()
	var with := _grab(scene)
	var strip_px := Vector2i((scene.controls.button_rect("book").get_center() * scene.controls.ui_scale).round())
	finder.button(MOUSE_BUTTON_LEFT, Vector2(finder.rect().get_center() * scene.scale_px))
	var corner_photo := game.album.image(game.last_photo)
	var r := finder.rect()
	var origin := Vector2i((r.position * scene.scale_px).round())
	if with != null and corner_photo != null:
		var inside := Rect2i(origin, corner_photo.get_size()).has_point(strip_px)
		_scene_still("photo_4_corner_scene")
		var body := ScenePhoto.body_rect(scene.world, deer.look.sheet) if deer != null else Rect2()
		var cut := body.intersection(r).get_area() / body.get_area() if body.has_area() else 0.0
		print("VibeNature snapshot: the deer is %d%% inside the corner frame" % int(cut * 100.0))
		s._expect(cut < float(finder.tuning["species_share"]) or (game.album.photos()[0]["species"] as Array).has("deer"),
				"the deer partly in the corner frame (%d%%) is listed" % int(cut * 100.0))
		corner_photo.save_png(s.out_dir.path_join("photo_5_corner_photo.png"))
		_step("photo_5_corner_photo")
		if inside:
			s._expect(corner_photo.get_pixelv(strip_px - origin) != with.get_pixelv(strip_px), "the strip is not in a photo framed over it")
	for i in 30:
		finder.step(0.05, null)

	game.book.open(SceneBookWindow.PHOTOS)
	await _frames()
	_save(game.book, "photo_6_book")
	game.book.enlarge(game.album.photos()[-1]["id"])
	await _frames()
	_save(game.book, "photo_7_enlarged")
	game.book.close_book()
	Pace.stop_moving()


func _frames() -> void:
	await game.get_tree().process_frame
	await game.get_tree().process_frame


## The scene window as drawn (strip and viewfinder included) over a plain desktop.
func _scene_still(step: String) -> void:
	var image := _grab(game.scene)
	if image == null:
		return
	var desktop := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	desktop.fill(Color(DESKTOP))
	desktop.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	desktop.save_png(s.out_dir.path_join("%s.png" % step))
	_step(step)


func _save(window: Window, step: String) -> void:
	var image := _grab(window)
	if image == null:
		return
	image.save_png(s.out_dir.path_join("%s.png" % step))
	_step(step)


func _step(step: String) -> void:
	s.steps.append({"step": step, "windows": [], "files": ["%s.png" % step], "checks": []})
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
