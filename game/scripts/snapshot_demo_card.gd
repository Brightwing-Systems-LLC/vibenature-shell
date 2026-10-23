class_name SnapshotDemoCard
extends RefCounted

## Stills of the demo's morning card (issue 268), off screen:
## the card over the morning scene at rest and with the button hovered, each as the whole scene over a plain desktop,
## a phone-sized copy and a 1:1 crop of the card. The run is made the demo build (`Edition.forced`).
## `game/tools/snap.sh <godot> <out> demo_card`.

const PRESET := "demo_card"
const DESKTOP := "4a5a6a"
const PHONE_WIDTH := 1170

var s: Snapshot
var game: Game
var _scene_shots: SnapshotScene


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	_scene_shots = SnapshotScene.new(owner)


func run() -> void:
	Pace.start_moving()
	Edition.forced = "demo"
	var scene := game.scene
	SnapshotScene.apply(scene, _scene_shots.clips["presets"][PRESET], _scene_shots.clips)
	scene.set_random_visits(false)
	await _scene_shots.play(scene, PRESET, 2.0)
	var card := scene.demo_card
	if card == null:
		card = scene.add_demo_card(game.balance.data["demo_card"], Game.ui_scale(true, DisplayServer.screen_get_max_scale()))
		card.pointer_source = func() -> Variant: return null
	var opened: Array[String] = []
	card.opener = func(url: String) -> void: opened.append(url)
	game.settings.data["demo_card_day"] = ""
	game._play_day(["arrive_now"])
	s._expect(card.shown and not scene.mouse_passthrough, "the morning's first arrival shows the card, and it takes the mouse")
	card.set_process(false)
	card.step(2.0)
	s._expect(is_equal_approx(card.alpha, 1.0) and opened.is_empty(), "faded in; nothing opened")
	await _shot("01_card")
	card.hovered = "button"
	card.queue_redraw()
	await _shot("02_card_button_hover")
	card.hovered = ""
	card.hovered = "close"
	card.queue_redraw()
	await _shot("03_card_close_hover")
	card.press("close")
	s._expect(not card.shown, "the ✕ closes it")
	Edition.forced = ""
	Pace.stop_moving()


func _shot(step: String) -> void:
	await game.get_tree().process_frame
	var scene := game.scene
	if DisplayServer.get_name() == "headless":
		return
	WindowChrome.redraw(scene)
	RenderingServer.force_draw(false)
	var image: Image = scene.get_texture().get_image()
	if image == null or image.is_empty():
		s._expect(false, "%s: the scene rendered" % step)
		return
	image.convert(Image.FORMAT_RGBA8)
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(DESKTOP))
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	flat.save_png(s.out_dir.path_join("%s__scene.png" % step))
	var phone := flat.duplicate() as Image
	phone.resize(PHONE_WIDTH, int(float(flat.get_height()) * PHONE_WIDTH / flat.get_width()), Image.INTERPOLATE_LANCZOS)
	phone.save_png(s.out_dir.path_join("%s__phone.png" % step))
	var card := scene.demo_card
	var r := card.card_rect()
	var crop := Rect2i(((r.position - Vector2(16, 16)) * card.ui_scale).round(), ((r.size + Vector2(32, 32)) * card.ui_scale).round())
	flat.get_region(crop.intersection(Rect2i(Vector2i.ZERO, flat.get_size()))).save_png(s.out_dir.path_join("%s__card_1x.png" % step))
	s.steps.append({"step": step, "windows": ["scene"], "files": ["%s__scene.png" % step, "%s__phone.png" % step, "%s__card_1x.png" % step], "checks": []})
	print("VibeNature snapshot: %s" % step)
