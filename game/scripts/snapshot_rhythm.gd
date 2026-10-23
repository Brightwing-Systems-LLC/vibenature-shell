class_name SnapshotRhythm
extends RefCounted

## Stills of the daily rhythm's stand-ins (issue 198), off
## screen (the van is an empty slot until issue 197 delivers its art, so only its timing shows): the van driving in, parked with you fading in at the log, the wrap-up (golden light, lights on,
## a stretch), you gone and the van driving off, and the empty log at dusk. Each as the whole scene, a
## phone-sized copy, and 1:1 crops round the van and the seat. `game/tools/snap.sh <godot> <out> rhythm`.

## [step, preset, minute of day or -1 for the preset's, what to play, seconds to run after it]
## Issue 279: the van comes in from the right and parks mid-bank facing left; leaving, it makes a three-point turn
## (shots 07c-07e at dusk, lamps glowing) and goes out to the right; 09-11 are its paint on the far bank.
const SHOTS: Array = [
	["01_van_braking", "van_arrive", -1, "arrive", 7.5],
	["02_van_parked", "van_arrive", -1, "arrive", 11.8],
	["03_far_bank", "van_arrive", -1, "arrive", 20.0],
	["04_by_the_birch", "van_arrive", -1, "arrive", 60.1],
	["05_sitting", "van_arrive", -1, "arrive", 66.6],
	["06_wrap_up", "van_leave", -1, "invite", 9.0],
	["06b_stepping_in", "van_leave", -1, "leave", 51.2],
	["07_leaving_drive", "van_leave", -1, "leave", 59.5],
	["07c_dusk_turning", "dusk", -1, "leave", 56.9],
	["07d_dusk_front_on", "dusk", -1, "leave", 58.0],
	["07e_dusk_reversing", "dusk", -1, "leave", 59.2],
	["07b_dusk_leaving", "dusk", -1, "leave", 62.0],
	["08_empty_log_dusk", "dusk", -1, "leave", 71.0],
	["09_paint_red_cream", "van_paint_a", -1, "arrive_now", 1.0],
	["10_paint_deep_blue_white", "van_paint_b", -1, "arrive_now", 1.0],
	["11_paint_mustard_butter", "van_paint_c", -1, "arrive_now", 1.0],
]
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
	for shot in SHOTS:
		var scene := _scene_shots.build(String(shot[1]))
		if int(shot[2]) >= 0:
			scene.minute = float(shot[2])
		await _scene_shots.play(scene, String(shot[1]), 1.0)
		scene.day(String(shot[3]))
		var frames := int(float(shot[4]) * float(_scene_shots.clips["fps"]))
		for i in frames:
			scene.advance(1.0 / float(_scene_shots.clips["fps"]), scene.minute)
			if i % 10 == 9:
				await game.get_tree().process_frame
		_expect(String(shot[0]), scene)
		await game.get_tree().process_frame
		_save(String(shot[0]), scene)
	await _start_of_day_with_letter()
	Pace.stop_moving()


## Issue 431: a start-of-day time at 08:30, an agent busy with nobody at the Mac (no van), then someone sits down
## (the idle seconds, faked) and the van drives in with a letter from the elder, read on the log.
func _start_of_day_with_letter() -> void:
	var scene := _scene_shots.build("letter_morning")
	scene.day("leave_now")
	var card := scene.add_letter_card(game.balance.data["letter_card"], Game.ui_scale(true, 2.0))
	scene.letter_started.connect(game._on_letter_started)
	if game.letters != null:
		if game.letters.waiting().is_empty():
			game.letters._deliver(game.letters.pool()[0], {}, "", game.clock.now(), game.day_key(), game.elder_choice())
		game.letters.waiting()["on_log"] = false
		game._letter_due_update()
	var clock := GameClock.new(0.0, Time.get_unix_time_from_datetime_string("2026-10-21T08:40:00"))
	clock.tz_bias_min = 0
	var r := DailyRhythm.new(clock, game.settings.day_phases(), game.balance.data["daily_rhythm"])
	r.start_minutes = DayPhases.minutes("08:30")
	r.idle_sec = 3600.0
	var before := r.launched()
	before.append_array(r.turn(true))
	before.append_array(r.tick())
	s._expect(before.is_empty() and not r.here, "start of day: an agent busy with nobody at the Mac brings no van")
	r.idle_sec = 3.0
	var events := r.tick()
	s._expect(events == ["arrive"], "start of day: someone at the Mac after the start time, the van drives in (%s)" % [events])
	for e in events:
		scene.day(String(e))
	s._expect(scene.letter_due, "start of day: a letter rides in with the van")
	var dt := 1.0 / float(_scene_shots.clips["fps"])
	var t := 0.0
	var saved := {}
	while t < 150.0:
		scene.advance(dt, scene.minute)
		t += dt
		if not saved.has("12") and t >= 11.8:
			saved["12"] = true
			await game.get_tree().process_frame
			_save("12_start_of_day_van_parked", scene)
		if not saved.has("13") and scene.sitter.step_anim() == "log_letter_read" and card.shown() and card.alpha >= 1.0:
			saved["13"] = true
			await game.get_tree().process_frame
			_save("13_start_of_day_letter_reading", scene)
			break
		if int(t / dt) % 10 == 9:
			await game.get_tree().process_frame
	s._expect(saved.has("13") or DisplayServer.get_name() == "headless", "start of day: the letter is read on the log after the arrival")
	s.notes["start_of_day_letter_sec"] = t


func _expect(step: String, scene: LivingScene) -> void:
	var van := scene.van
	match step:
		"01_van_braking":
			s._expect(van.state == "arriving" and van.van_x > float(van.tuning["van"]["park_x_pt"]) and scene.sitter.modulate.a == 0.0, "arriving: the van brakes along the far bank from the right, the log is empty")
		"02_van_parked":
			s._expect(van.state == "arriving" and not van.far.is_empty(), "parked: you step out of the van on the far bank")
		"03_far_bank":
			s._expect(not van.far.is_empty() and not bool(van.near.get("show", false)), "you walk along the far bank at the far size")
		"04_by_the_birch":
			s._expect(van.far.is_empty() and scene.sitter.standing(), "you come in by the birch at full size")
		"05_sitting":
			s._expect(van.state == "parked" and not scene.sitter.standing() and scene.sitter.modulate.a == 1.0, "you sit on the log")
		"06_wrap_up":
			s._expect(scene.golden_lean > 0.99 and van.lights and scene.sitter.standing(), "the wrap-up: golden light, the van's lights on, you stand packed")
		"06b_stepping_in":
			s._expect(not van.far.is_empty() and van.lights and van.state == "leaving_walk", "after the wrap-up: you step up into the van, its lamps still lit")
		"07_leaving_drive":
			s._expect(van.state == "leaving_drive" and van.lights and scene.sitter.modulate.a == 0.0, "leaving: you are in the van, it pulls away with its lamps lit")
		"07b_dusk_leaving":
			s._expect(van.state == "leaving_drive" and van.lights and bool(van.current.get("lit", false)), "leaving at dusk with no wrap-up: the van pulls away with its lamps lit (issue 277)")
		"07c_dusk_turning", "07d_dusk_front_on", "07e_dusk_reversing":
			var turning: bool = String(van.current.get("kind", "")) == "leave" \
					and String(SceneVan.pose_at(van.current, van._t)["van"]["anim"]).begins_with("turn_")
			s._expect(turning and van.lights and van.darkness > 0.0, "%s: the three-point turn at dusk, lamps lit and glowing" % step)
		"09_paint_red_cream", "10_paint_deep_blue_white", "11_paint_mustard_butter":
			var want: Dictionary = _scene_shots.clips["presets"][{"09": "van_paint_a", "10": "van_paint_b", "11": "van_paint_c"}[step.left(2)]]["van"]
			s._expect(VanPaint.key(van.paint) == VanPaint.key(want) and van.here(), "%s: the van parked on the far bank in its paint" % step)
		"08_empty_log_dusk":
			s._expect(van.state == "away" and not van.visible and scene.sitter.modulate.a == 0.0, "after: the log is empty and the scene goes on")


func _save(step: String, scene: LivingScene) -> void:
	if DisplayServer.get_name() == "headless":
		return
	WindowChrome.redraw(scene)
	RenderingServer.force_draw(false)
	var image: Image = scene.get_texture().get_image()
	if image == null or image.is_empty():
		s._expect(false, "%s: the scene rendered" % step)
		return
	image.convert(Image.FORMAT_RGBA8)
	var files: Array = []
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color(String(_scene_shots.clips["background"])))
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	flat.save_png(s.out_dir.path_join("%s.png" % step))
	files.append("%s.png" % step)
	var phone := flat.duplicate() as Image
	phone.resize(PHONE_WIDTH, int(float(flat.get_height()) * PHONE_WIDTH / flat.get_width()), Image.INTERPOLATE_LANCZOS)
	phone.save_png(s.out_dir.path_join("%s_phone.png" % step))
	files.append("%s_phone.png" % step)
	var k := scene.scale_px
	var van_at := Vector2(scene.van.van_x, scene.van.position.y) * k
	var crops := {
		"van": Rect2i(Vector2i(van_at) - Vector2i(260, 160), Vector2i(640, 220)),
		"seat": Rect2i(Vector2i((scene.sitter.seat * k).round()) - Vector2i(420, 300), Vector2i(640, 400)),
	}
	if bool(scene.van.near.get("show", false)) and step.begins_with("04"):
		crops["near"] = Rect2i(Vector2i(Vector2(float(scene.van.near["x"]), scene.sitter.seat.y) * k) - Vector2i(240, 300), Vector2i(480, 400))
	if not scene.van.far.is_empty():
		crops["far"] = Rect2i(Vector2i(Vector2(float(scene.van.far["x"]), scene.van.position.y) * k) - Vector2i(160, 110), Vector2i(320, 160))
	for c in crops:
		var r: Rect2i = (crops[c] as Rect2i).intersection(Rect2i(Vector2i.ZERO, flat.get_size()))
		if r.has_area():
			flat.get_region(r).save_png(s.out_dir.path_join("%s_%s_1x.png" % [step, c]))
			files.append("%s_%s_1x.png" % [step, c])
	s.steps.append({"step": step, "windows": ["scene"], "files": files, "checks": []})
	print("VibeNature snapshot: %s" % step)
