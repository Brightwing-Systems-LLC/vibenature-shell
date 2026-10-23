class_name SnapshotBook
extends RefCounted

## Stills of the book (Skypatch issue 177), off screen:
## the empty book on both parts, then sample photos made from scene renders (until the photo ticket,
## issue 176, takes real ones), the album, one photo enlarged, a delete asking, and the field guide
## after a while of the scene. `game/tools/snap.sh <godot> <out> book`.

## Presets rendered as sample photos, with the weather word and species each is labelled with.
const SAMPLES := [
	["calm", "sunny", ["northern_cardinal", "bluegill"]],
	["dawn_mist", "mist", ["great_blue_heron"]],
	["rain", "rain", []],
	["dusk", "cloudy", ["deer", "painted_turtle", "dragonfly_blue_darner"]],
	["fog", "fog", ["bluegill"]],
	["gusty", "wind", []],
]
const GUIDE_SPAWNS := ["deer", "great_blue_heron", "painted_turtle", "bluegill", "dragonfly_blue_darner", "red_fox"]

var s: Snapshot
var game: Game
var _scene_shots: SnapshotScene


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	_scene_shots = SnapshotScene.new(owner)


func run() -> void:
	Pace.start_moving()
	var book := game.book
	s._expect(book != null, "scene mode has the book")
	if book == null:
		return
	# The first letter would open the book at Letters (issue 213; its stills are the `letters` path).
	game.letters.mark_read()
	game.scene.controls.press("book")
	await _frames()
	s._expect(book.visible and book.tabs.current_tab == SceneBookWindow.PHOTOS, "📖 opens the book on Photos")
	s._expect(game.album.photos().is_empty(), "a fresh album is empty")
	_save(book, "book_1_photos_empty")
	book.tabs.current_tab = SceneBookWindow.FIELD_GUIDE
	await _frames()
	_save(book, "book_2_guide_empty")
	book.close_book()

	var unix := game.clock.now() - 3.0 * 86400.0
	for sample in SAMPLES:
		var preset: String = sample[0]
		SnapshotScene.apply(game.scene, _scene_shots.clips["presets"][preset], _scene_shots.clips)
		game.scene.set_random_visits(false)
		await _scene_shots.play(game.scene, preset, 2.0)
		await _frames()
		var image := _grab(game.scene)
		if image == null:
			image = Image.create_empty(1152, 512, false, Image.FORMAT_RGBA8)
			image.fill(Color("6a8a6a"))
		var id := game.album.add(image, {"unix": unix, "weather": sample[1], "species": sample[2], "path": "/never/kept"})
		s._expect(id != "", "the album keeps a photo of %s" % preset)
		unix += 19.0 * 3600.0

	var photos := game.album.photos()
	s._expect(photos.size() == SAMPLES.size(), "the album has every sample (got %d)" % photos.size())
	s._expect(not photos.is_empty() and float(photos[0]["unix"]) > float(photos[-1]["unix"]), "newest first")
	# Sightings over a few days, on the game's clock.
	var at := {"unix": game.clock.now() - 4.0 * 86400.0}
	game.scene.behaviour.unix_clock = func() -> float: return float(at["unix"])
	for sid in GUIDE_SPAWNS:
		game.scene.behaviour.spawn(sid, "debug")
		at["unix"] = float(at["unix"]) + 17.0 * 3600.0
	at["unix"] = game.clock.now() - 1800.0
	game.scene.behaviour.spawn("deer", "debug")
	game.scene.behaviour.spawn("songbirds_few", "debug")
	s._expect(game.sightings.seen.has("deer") and int(game.sightings.seen["deer"]["times"]) >= 2, "a second deer updates last seen")

	book.open(SceneBookWindow.PHOTOS)
	await _frames()
	s._expect(book.spread, "the book opens as a two-page spread")
	_save(book, "book_3_photos")
	book.turn(SceneBookWindow.PHOTOS, 1)
	await _frames()
	s._expect(book.turned_to[SceneBookWindow.PHOTOS] == 1, "the pages turn to the next spread")
	_save(book, "book_3b_photos_turned")
	book.turn(SceneBookWindow.PHOTOS, -1)
	var newest := String(photos[0]["id"])
	book.enlarge(newest)
	await _frames()
	s._expect(book.enlarged == newest, "a photo enlarges")
	_save(book, "book_4_enlarged")
	book.ask_delete(newest)
	await _frames()
	_save(book, "book_5_delete_asks")
	book.keep(newest)
	book.back_to_album()
	book.tabs.current_tab = SceneBookWindow.FIELD_GUIDE
	await _frames()
	s._expect(not game.sightings.entries().is_empty(), "the field guide has what was seen")
	_save(book, "book_6_guide")
	book.tabs.current_tab = SceneBookWindow.PHOTOS
	book.use_spread(false)
	await _frames()
	_save(book, "book_7_narrow")
	book.use_spread(true)
	book.close_book()
	Pace.stop_moving()


func _frames() -> void:
	await game.get_tree().process_frame
	await game.get_tree().process_frame


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
