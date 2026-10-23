class_name SnapshotLetters
extends RefCounted

## Stills of the elder's letters (issue 213), off screen:
## the first letter read on the log (issue 270: taking it out, reading, looking up, putting it away, sitting after),
## a photo with "Send to {elder_name}", the same photo sent (its mark, in the album and enlarged), the first letter
## in the journal, a reply, and Config's Elder tab.
## `game/tools/snap.sh <godot> <out> letters`.

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
	s._expect(book != null and game.letters != null, "scene mode has the book and the letters")
	if book == null or game.letters == null:
		return
	s._expect(String(game.letters.waiting().get("id", "")) == "first", "the first letter waits on the first launch")

	SnapshotScene.apply(game.scene, _scene_shots.clips["presets"]["letter_morning"], _scene_shots.clips)
	game.scene.set_random_visits(false)
	game.scene.day("arrive_now")
	s._expect(game.scene.find_child("LetterSign", true, false) == null, "no envelope on the log (issue 270)")
	s._expect(game.scene.letter_due, "the waiting letter is due on the log")
	await _reading_beats()
	await _small_card()
	SnapshotScene.apply(game.scene, _scene_shots.clips["presets"]["dawn_mist"], _scene_shots.clips)
	game.scene.set_random_visits(false)
	game.scene.behaviour.spawn("great_blue_heron", "debug")
	await _scene_shots.play(game.scene, "dawn_mist", 3.0)
	game.scene.advance(0.1, game.scene.minute)
	await _frames()

	var shot := _grab(game.scene)
	if shot == null:
		shot = Image.create_empty(1152, 512, false, Image.FORMAT_RGBA8)
		shot.fill(Color("6a8a6a"))
	shot = shot.get_region(Rect2i(Vector2i(shot.get_width() / 4, shot.get_height() / 4), Vector2i(shot.get_width() / 2, shot.get_height() / 2)))
	var id := game.album.add(shot, {"unix": game.clock.now() - 86400.0, "weather": "fog", "species": ["great_blue_heron"]})
	game.album.add(shot, {"unix": game.clock.now() - 2.0 * 86400.0, "weather": "sunny", "species": ["deer"]})

	game.letters.mark_read()
	game._letter_due_update()
	book.open(SceneBookWindow.PHOTOS)
	await _frames()
	var send := book.find_child("Photo_" + id, true, false).find_child("Send", true, false) as Button
	s._expect(send != null and send.text.begins_with("Send to "), "the photo offers Send to {elder_name}")
	_save(book, "letters_2_send_button")
	game.send_photo(id)
	book.refresh()
	await _frames()
	s._expect(book.find_child("Photo_" + id, true, false).find_child("SentMark", true, false) != null, "a sent photo shows its mark")
	_save(book, "letters_3_sent_mark")
	book.enlarge(id)
	await _frames()
	_save(book, "letters_4_sent_enlarged")
	book.close_book()

	# The next day, a reply (the dice made sure here: a still, not a test of the odds).
	var tuning: Dictionary = game.letters.tuning
	var chance := float(tuning["reply_chance"])
	tuning["reply_chance"] = 1.0
	game.letters.sent[id]["day"] = "0000-00-00"
	var tomorrow := game.clock.now() + 86400.0
	var reply := game.letters.overnight(tomorrow, game.clock.date_key(tomorrow), game.elder_choice(), game.rng)
	tuning["reply_chance"] = chance
	s._expect(not reply.is_empty(), "a reply comes for the sent photo")
	game._on_book_requested()
	await _frames()
	s._expect(book.visible and book.tabs.current_tab == SceneBookWindow.LETTERS, "the journal opens at the waiting letter")
	_save(book, "letters_5_reply_and_first_in_journal")
	book.close_book()

	game.set_elder({"who": "walt", "relation": "great", "name": ""})
	game.scene_config.open(SceneConfigWindow.ELDER)
	await _frames()
	_save(game.scene_config, "letters_6_config_elder")
	game.scene_config.close_config()
	Pace.stop_moving()


## Reading the letter on the log (issue 270), one still per beat: the hand at the pocket, reading, looking up at
## the water, folding it away, and sitting as before. The scene steps at the clip rate.
func _reading_beats() -> void:
	var sitter := game.scene.sitter
	var beats := [["letters_1a_taking_out", "log_letter_out", 10], ["letters_1b_reading", "log_letter_read", 27],
			["letters_1c_looking_up", "log_letter_look_up", 39], ["letters_1d_putting_away", "log_letter_put_away", 12]]
	var dt := 1.0 / float(_scene_shots.clips["fps"])
	var t := 0.0
	var started := -1.0
	for beat in beats:
		while t < 90.0 and not (sitter.step_anim() == String(beat[1]) and sitter.shown_frame() == int(beat[2])):
			game.scene.advance(dt, game.scene.minute)
			t += dt
			if started < 0.0 and sitter.reading():
				started = t
		s._expect(t < 90.0, "the reading reaches %s" % beat[0])
		await _frames()
		_save(game.scene, String(beat[0]))
		if String(beat[0]) == "letters_1b_reading":
			_card_crops(game.scene, "letters_1b_reading")
	while t < 120.0 and sitter.reading():
		game.scene.advance(dt, game.scene.minute)
		t += dt
	s._expect(not sitter.reading() and sitter.shown_frame() == int(sitter._anim("log_sit")["frames"][0]), "the letter put away, you sit as before")
	s._expect(game.letters.waiting().get("on_log", false), "read on the log once; it still waits in the journal")
	s.notes["letter_read"] = {"settled_to_reading_sec": started, "done_sec": t}
	await _frames()
	_save(game.scene, "letters_1e_sitting_after")


## The letter card at 50% (issue 314): the first lines and "Read in the journal".
func _small_card() -> void:
	var first: Dictionary = game.letters.letters[0]
	var again := first.duplicate()
	again["id"] = "again"
	again["on_log"] = false
	again["read"] = false
	first["read"] = true
	game.set_scene_size(50)
	game.scene.day("leave_now")
	game.scene.advance(0.1, game.scene.minute)
	game.letters.letters.append(again)
	game._letter_due_update()
	game.scene.day("arrive_now")
	var card := game.scene.letter_card
	var dt := 1.0 / float(_scene_shots.clips["fps"])
	var t := 0.0
	while t < 90.0 and not (card.catches() and card.alpha >= 1.0 and game.scene.sitter.step_anim() == "log_letter_read"):
		game.scene.advance(dt, game.scene.minute)
		t += dt
	s._expect(card.catches() and card.compact, "at 50% the card shows the first lines")
	await _frames()
	_save(game.scene, "letters_1f_card_50")
	_card_crops(game.scene, "letters_1f_card_50")
	while t < 180.0 and game.scene.sitter.reading():
		game.scene.advance(dt, game.scene.minute)
		t += dt
	game.letters.letters.erase(again)
	first["read"] = false
	game._letter_due_update()
	game.set_scene_size(100)
	await _frames()


## A phone-sized copy of the scene and a 1:1 crop of the letter card around it.
func _card_crops(window: Window, step: String) -> void:
	var image := _grab(window)
	var card := game.scene.letter_card
	if image == null or card == null or not card.shown():
		s._expect(image == null, "%s: the letter card shows" % step)
		return
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color("3a3f44"))
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	var phone := flat.duplicate() as Image
	phone.resize(1170, int(float(flat.get_height()) * 1170.0 / flat.get_width()), Image.INTERPOLATE_LANCZOS)
	phone.save_png(s.out_dir.path_join("%s__phone.png" % step))
	var r := card.card_rect()
	var crop := Rect2i(((r.position - Vector2(16, 16)) * card.ui_scale).round(), ((r.size + Vector2(32, 32)) * card.ui_scale).round())
	flat.get_region(crop.intersection(Rect2i(Vector2i.ZERO, flat.get_size()))).save_png(s.out_dir.path_join("%s__card_1x.png" % step))
	s.steps.append({"step": step + "_crops", "windows": [window.title], "files": ["%s__phone.png" % step, "%s__card_1x.png" % step], "checks": []})


func _frames() -> void:
	await game.get_tree().process_frame
	await game.get_tree().process_frame


func _save(window: Window, step: String) -> void:
	var image := _grab(window)
	if image == null:
		return
	var flat := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	flat.fill(Color("3a3f44"))
	flat.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	flat.save_png(s.out_dir.path_join("%s.png" % step))
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
