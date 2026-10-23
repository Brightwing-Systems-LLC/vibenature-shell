class_name SceneSitter
extends Node2D

## The avatar on the log (contract §7: the game owns his idle life). He sits facing us and is never
## still for long, never busy either: he breathes, glances one way and the other, follows a bird
## across the scene with his eyes, rolls his shoulders. He dozes off only on a seat whose kit `seat` lists
## `"supports": ["doze"]` (issue 121, proposal
## `121-seat-supports`): nobody sleeps sitting upright on a log, so a seat that lists nothing never dozes.
## There, late at night, he is drowsy but awake instead: a slow stretch, a long look up at the sky, or his
## chin dipping a moment before he catches himself and looks up (the look's own frames, never new ones).
##
## An avatar with a `log` block in its meta.json (`<id>_log.png`, drawn seated at the kit's density,
## Skypatch issue 109) plays those frames at the seat, hips
## on the anchor: rests breathing, then one idle action (glances, following something across, a
## stretch, a sip from the thermos, a drowsy beat at night, nodding off and waking where the seat allows it), chosen at random by weight and never the
## same one twice in a row, with rests of random length between. Without one, the front `sit` frame
## is split into legs, body and head and moved a pixel at a time.
##
## Since issue 123 a seated look is a creature: it breathes
## visibly, drinks from the thermos (left standing on the ground until he packs up), reads a paperback, glances down,
## fidgets (once the bench draws them), and watches animals for a spell, looking down at one at his feet.
##
## The player's look (`AvatarLook.sheet`, Skypatch issue 202), set in
## `composed` before `setup`, plays the same way as a delivered `log` sheet; `use_sheet` swaps it in place.

const ACTIONS: Array[String] = ["look", "stretch", "sip", "doze"]
const LOOKS: Array[String] = ["left", "right", "up"]
## The chin-dip beat's own animation name: log_sit's first frame, then the first frame of the look's nod-off.
const DIP := "log_drowsy_dip"

## What the seat allows beyond sitting (the kit's `seat.supports`, set before `setup`): only "doze" so far.
var seat_supports: Array = []

var tuning: Dictionary = {}
var materials: Array[ShaderMaterial] = []
var mode := "rest"
var look := 0.0
var _look_target := 0.0
var _left := 4.0
var _glances: Array = []
var _nod := 0.0
var _nod_target := 0.0
var _lift := 0.0
var _lift_target := 0.0
var _breath := 0.0
var _breath_sec := 4.2
var _rng := RandomNumberGenerator.new()
var _legs := Sprite2D.new()
var _body := Sprite2D.new()
var _head := Sprite2D.new()
var _full := Sprite2D.new()
var _sheet: Image
var _frame := Vector2i.ZERO
var _rows := Vector2i.ZERO
var _delivered := {}
var _playing := ""
var _play_t := 0.0
## Where his eyes go when something moves (scene px), or null.
var interest = null
var seat := Vector2.ZERO
var ok := false
## The seated sheet's `log` block, when the avatar has one.
var _log: Dictionary = {}
var _seated := Sprite2D.new()
var _seated_scale := 1.0
## The current action as steps [{anim, hold, fps_scale?}]: each animation plays once (a loop for `hold`), then
## its last frame holds for `hold` seconds.
var _steps: Array = []
var _step_t := 0.0
var _step_fps := 1.0
var _shown := -1
var _last_action := ""
var _watching := ""
## The smallest step a part moves, in sheet px: one physical pixel at the scene's scale.
var snap_step := 0.5
## A swapped look ({image, meta}) to sit instead of the avatar id's delivered art.
var composed: Dictionary = {}
## The look's `day` block while its day actions are in use (`use_day`).
var _day: Dictionary = {}
var _standing := Sprite2D.new()

## Reading the elder's letter (issue 270): the look's `letter`
## sheet (`use_letter`) shares the log sheet's frame, anchor and scale, so it swaps onto the same sprite.
signal letter_started
## Set by the scene while a letter is due on the log and you sit there: the next rest ends in reading it.
var letter_pending := false
## Set by the scene while a letter waits for the log at all (issue 359): no new idle activity starts meanwhile, so
## the letter comes first once he sits.
var letter_due := false
## Set by the scene while he is not on the log (the van away, or standing): he only rests, starting nothing.
var away := false
## Words in the letter he will read (the game sets it with the letter due), for how long he reads it.
var letter_words := 0
## How long the reading takes in all (read, look up, read again), set when he takes the letter out.
var letter_read_total := 0.0
var _letter: Dictionary = {}
var _letter_texture: Texture2D
var _log_texture: Texture2D
var _on_letter := false
## The reading frames' drawn pixels, in the sheet's frame px (the click target while reading).
var _letter_rect := Rect2()

## The seated activity sheets (issue 123, `AvatarLook.extra_sheets`): {block: {"meta", "texture"}}. Each shares the log
## sheet's frame, anchor and scale and swaps onto the same sprite while one of its animations plays.
var _extra := {}
## Which sheet is on the sprite now: "log", "letter" or an extra block.
var _worn := "log"
## The thermos stands on the ground beside the log (the human, issue 123: once he sets it down it stays there until
## he packs up). Drawn as the bench's ground prop at its `at` in the log frame whenever no thermos frame is shown.
var thermos_down := false
var _prop := Sprite2D.new()
## Something close by (an animal at his feet or on the log in front), in points, or null: watched before `interest`.
var near = null
var _breath_period := 4.4
var _lifted := -1.0
var _watch_t := 0.0
var _watch_cap := 0.0
var _watch_gap := 0.0
var _dir_t := 0.0
var _day_thermos := -1
var _had_near := false
var _last_target = null
var _lost_t := 0.0


func setup(avatar_id: String, seat_at: Vector2, band_scale: float, sitter_tuning: Dictionary, shader: Shader, seed: int) -> void:
	tuning = sitter_tuning
	name = "Sitter"
	seat = seat_at
	_rng.seed = seed
	_left = _rng.randf_range(2.0, 5.0)
	if not composed.is_empty() and _setup_texture(ImageTexture.create_from_image(composed["image"]), composed["meta"], shader):
		return
	var meta := AssetLibrary.load_meta("avatar", avatar_id, AssetLibrary.avatar_root())
	if meta.has("log") and _setup_log(avatar_id, meta["log"], shader):
		return
	if not meta.has("layers") or not meta["layers"].has("front"):
		push_warning("VibeNature: the scene has no seated avatar for %s" % avatar_id)
		return
	var front: Dictionary = meta["layers"]["front"]
	var depth := _depth_for(meta, band_scale)
	var file := AssetLibrary.companion_file("avatar/%s/%s_front%s.png" % [avatar_id, avatar_id, "" if depth == "front" else "@" + depth])
	if not AssetLibrary.image_exists(file):
		push_warning("VibeNature: no avatar sheet %s" % file)
		return
	_sheet = AssetLibrary.load_image(file)
	_sheet.convert(Image.FORMAT_RGBA8)
	var anchor: Vector2i
	if depth == "front":
		_frame = Vector2i(int(front["frame_w"]), int(front["frame_h"]))
		anchor = AssetLibrary.vec2i(front["anchor"])
	else:
		_frame = AssetLibrary.vec2i(meta["depths"][depth]["frame"])
		anchor = AssetLibrary.vec2i(meta["depths"][depth]["anchor"])
	var sit_frame := int(front["animations"]["sit"]["frames"][0])
	for action in ACTIONS:
		var anim := "log_" + action
		if front["animations"].has(anim):
			_delivered[action] = front["animations"][anim]
	var frame := _sheet.get_region(Rect2i(sit_frame * _frame.x, 0, _frame.x, _frame.y))
	_rows = Vector2i(roundi(float(tuning["head_until"]) * _frame.y), roundi(float(tuning["body_until"]) * _frame.y))
	var hip := roundi(float(tuning["hip_row"]) * _frame.y)
	# The sheets are drawn at one px per point for a smaller figure; the near bank is closer.
	var k := float(tuning["scale"])
	scale = Vector2(k, k)
	position = seat - Vector2(anchor.x, hip) * k
	_part(_legs, frame, _rows.y - 1, _frame.y, shader)
	_part(_body, frame, _rows.x - 1, _rows.y + 1, shader)
	_part(_head, frame, 0, _rows.x + 1, shader)
	_full.centered = false
	_full.visible = false
	_full.material = _lit(shader)
	add_child(_full)
	ok = true


func _setup_log(avatar_id: String, log_meta: Dictionary, shader: Shader) -> bool:
	var file := AssetLibrary.companion_file("avatar/%s/%s" % [avatar_id, String(log_meta.get("file", avatar_id + "_log.png"))])
	if not AssetLibrary.image_exists(file):
		push_warning("VibeNature: no seated sheet %s" % file)
		return false
	return _setup_texture(AssetLibrary.cached_texture(file), log_meta, shader)


func _setup_texture(texture: Texture2D, log_meta: Dictionary, shader: Shader) -> bool:
	if texture == null or not log_meta.has("animations") or not log_meta["animations"].has("log_sit"):
		return false
	_log = log_meta
	_frame = Vector2i(int(_log["frame_w"]), int(_log["frame_h"]))
	_seated_scale = maxf(float(_log.get("art_scale", 1.0)), 0.01)
	_log_texture = texture
	_seated.texture = texture
	_seated.centered = false
	_seated.region_enabled = true
	_seated.scale = Vector2.ONE / _seated_scale
	_seated.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_seated.position = seat - Vector2(AssetLibrary.vec2i(_log["anchor"])) / _seated_scale
	var m := _lit(shader)
	m.set_shader_parameter("density", _seated_scale)
	m.set_shader_parameter("pixel_snap", true)
	_seated.material = m
	add_child(_seated)
	_prop.centered = false
	_prop.visible = false
	_prop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var pm := _lit(shader)
	pm.set_shader_parameter("density", _seated_scale)
	pm.set_shader_parameter("pixel_snap", true)
	_prop.material = pm
	add_child(_prop)
	_set_breath_row()
	_rest()
	_show(int(_anim("log_sit")["frames"][0]))
	ok = true
	return true


## Sits a newly swapped look where the old one sat, in the same action and frame (the picker's live
## preview on the log). Only for a sitter already playing a seated sheet.
func use_sheet(sheet: Dictionary) -> bool:
	if _log.is_empty() or sheet.is_empty():
		return false
	var meta: Dictionary = sheet["meta"]
	if not meta.get("animations", {}).has("log_sit"):
		return false
	composed = sheet
	_log = meta
	_frame = Vector2i(int(_log["frame_w"]), int(_log["frame_h"]))
	_seated_scale = maxf(float(_log.get("art_scale", 1.0)), 0.01)
	_log_texture = ImageTexture.create_from_image(sheet["image"])
	if _worn == "log":
		_seated.texture = _log_texture
	_set_breath_row()
	_seated.scale = Vector2.ONE / _seated_scale
	_seated.position = seat - Vector2(AssetLibrary.vec2i(_log["anchor"])) / _seated_scale
	(_seated.material as ShaderMaterial).set_shader_parameter("density", _seated_scale)
	var frame := _shown
	_shown = -1
	_show(maxi(frame, 0))
	return true


## Where the seated sheet's boots are (points): the day actions stand there (issue 197). ZERO without one.
func feet_pt() -> Vector2:
	if _log.is_empty() or not _log.has("feet"):
		return Vector2.ZERO
	return seat + Vector2(AssetLibrary.vec2i(_log["feet"]) - AssetLibrary.vec2i(_log["anchor"])) / _seated_scale


## The look's standing day actions (`AvatarLook.day_sheets`), played by `stand` at full size near the log.
func use_day(sheets: Dictionary) -> void:
	_day = sheets.get("meta", {})
	if _day.is_empty() or not sheets.has("full"):
		_day = {}
		_standing.texture = null
		return
	_standing.texture = ImageTexture.create_from_image(sheets["full"])
	if _standing.get_parent() == null:
		_standing.centered = false
		_standing.region_enabled = true
		_standing.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_standing.visible = false
		var m := _lit(_seated.material.shader if _seated.material != null else null)
		m.set_shader_parameter("pixel_snap", true)
		_standing.material = m
		add_child(_standing)
	var k := maxf(float(_day.get("art_scale", 1.0)), 0.01)
	_standing.scale = Vector2.ONE / k
	(_standing.material as ShaderMaterial).set_shader_parameter("density", k)


## You standing or walking near the log (`SceneVan.near`: {"show", "frame", "x" feet in points, "flip"});
## the seated sheet hides meanwhile, and sitting again starts from rest.
func stand(pose: Dictionary) -> void:
	var show := bool(pose.get("show", false)) and _standing.texture != null
	if not show:
		if _standing.visible:
			_standing.visible = false
			_seated.visible = true
			if _log.is_empty():
				return
			_rest()
			_wear("log")
			_shown = -1
			_show(int(_anim("log_sit")["frames"][0]))
		return
	_standing.visible = true
	_seated.visible = false
	var k := maxf(float(_day.get("art_scale", 1.0)), 0.01)
	var fw := int(_day["frame_w"])
	var fh := int(_day["frame_h"])
	var anchor := AssetLibrary.vec2i(_day["anchor"])
	var flip := bool(pose["flip"])
	var frame := int(pose["frame"])
	_thermos_by_day(frame)
	_standing.region_rect = Rect2(frame * fw, 0, fw, fh)
	_standing.flip_h = flip
	var ax := (fw - anchor.x) if flip else anchor.x
	var feet := feet_pt()
	var x := roundf(float(pose["x"]) * k) / k
	_standing.position = Vector2(x, feet.y) - Vector2(ax, anchor.y) / k
	(_standing.material as ShaderMaterial).set_shader_parameter("origin", _standing.position - Vector2(frame * fw, 0) / k)


## The day sheet's pack (and the unpack, its reverse) draws the thermos on the ground from its second frame: the
## pack picks up the one standing there (the prop hides as its own pixels take over), and the unpack leaves it there
## (shown as the prop once the frame without it comes, through sitting down and on).
func _thermos_by_day(frame: int) -> void:
	var pack: Array = []
	for f in _day.get("animations", {}).get("day_pack", {}).get("frames", []):
		pack.append(int(f))
	if pack.size() < 2 or not _has_prop():
		return
	var held := pack.slice(1)
	if held.has(frame):
		_day_thermos = frame
		thermos_down = false
	elif frame == int(pack[0]) and _day_thermos >= 0:
		thermos_down = true
		_day_thermos = -1
	elif not held.has(frame) and frame != int(pack[0]):
		_day_thermos = -1
	_update_prop()


## Whether you are standing (the day actions) rather than seated.
func standing() -> bool:
	return _standing.visible


## The frame shown now (the seated sheet's index), for tests and stills.
func shown_frame() -> int:
	return _shown


func _anim(anim_name: String) -> Dictionary:
	if anim_name == DIP:
		return {"frames": [int(_log["animations"]["log_sit"]["frames"][0]), _dip_frame()],
				"fps": float(tuning["log"]["drowsy"]["dip_fps"]), "loop": false}
	if anim_name.begins_with("log_letter_") and _letter.get("animations", {}).has(anim_name):
		return _letter["animations"][anim_name]
	if _log["animations"].has(anim_name):
		return _log["animations"][anim_name]
	for block in _extra:
		var anims: Dictionary = _extra[block]["meta"].get("animations", {})
		if anims.has(anim_name):
			return anims[anim_name]
	return _log["animations"]["log_sit"]


## Which sheet draws `anim_name`: "letter", an extra block, or "log".
func _sheet_of(anim_name: String) -> String:
	if anim_name.begins_with("log_letter_") and _letter.get("animations", {}).has(anim_name):
		return "letter"
	if _log.is_empty() or _log["animations"].has(anim_name):
		return "log"
	for block in _extra:
		if _extra[block]["meta"].get("animations", {}).has(anim_name):
			return String(block)
	return "log"


## Whether the look can play `anim_name` (its log sheet or one of its activity sheets).
func has_anim(anim_name: String) -> bool:
	return not _log.is_empty() and (_log["animations"].has(anim_name) or _sheet_of(anim_name) != "log")


## The look's seated activity sheets (`AvatarLook.extra_sheets`: {block: {meta, image, prop?, prop_meta?}}); a block
## left out takes its activities away. Called again for a new look. `ground_thermos` stands the thermos beside the
## log at once (you were sitting there before the app started).
func use_extras(sheets: Dictionary, ground_thermos: bool = false) -> void:
	_extra = {}
	if _log.is_empty():
		return
	for block in sheets:
		var sheet: Dictionary = sheets[block]
		_extra[block] = {"meta": sheet["meta"], "texture": ImageTexture.create_from_image(sheet["image"])}
		if sheet.has("prop"):
			_extra[block]["prop"] = ImageTexture.create_from_image(sheet["prop"])
			_extra[block]["prop_meta"] = sheet["prop_meta"]
	if not _has_prop():
		thermos_down = false
		_prop.texture = null
	else:
		var pm: Dictionary = _extra["thermos"]["prop_meta"]
		_prop.texture = _extra["thermos"]["prop"]
		var k := maxf(float(pm.get("art_scale", _seated_scale)), 0.01)
		_prop.scale = Vector2.ONE / k
		_prop.position = _seated.position + (Vector2(AssetLibrary.vec2i(pm["at"])) - Vector2(AssetLibrary.vec2i(pm["anchor"]))) / _seated_scale
		(_prop.material as ShaderMaterial).set_shader_parameter("origin", _prop.position)
		(_prop.material as ShaderMaterial).set_shader_parameter("density", k)
		if ground_thermos:
			thermos_down = true
	var worn := _worn
	if worn != "log" and worn != "letter" and not _extra.has(worn):
		_rest()
		worn = "log"
	_worn = ""
	_wear(worn)
	var frame := _shown
	_shown = -1
	_show(maxi(frame, 0))
	_update_prop()


func _has_prop() -> bool:
	return _extra.has("thermos") and _extra["thermos"].has("prop")


## The prop stands on the ground while the thermos is down and no thermos frame (which draws its own) is shown.
func _update_prop() -> void:
	_prop.visible = thermos_down and _prop.texture != null and _worn != "thermos"


## The look reading the elder's letter (`AvatarLook.letter_sheet`; {} for a look without it, which never reads on
## the log: the letter just waits in the journal).
func use_letter(sheet: Dictionary) -> void:
	if sheet.is_empty() or _log.is_empty():
		_letter = {}
		_letter_texture = null
		if _on_letter:
			_rest()
			_wear("log")
			_shown = -1
			_show(int(_anim("log_sit")["frames"][0]))
		return
	_letter = sheet["meta"]
	var image: Image = sheet["image"]
	_letter_texture = ImageTexture.create_from_image(image)
	_letter_rect = Rect2()
	for name in ["log_letter_read", "log_letter_look_up"]:
		for f in _letter["animations"].get(name, {}).get("frames", []):
			var used := Rect2(image.get_region(Rect2i(int(f) * _frame.x, 0, _frame.x, _frame.y)).get_used_rect())
			_letter_rect = used if not _letter_rect.has_area() else _letter_rect.merge(used)
	if _on_letter:
		_seated.texture = _letter_texture
		var frame := _shown
		_shown = -1
		_show(maxi(frame, 0))


## Whether this look can read a letter on the log.
func can_read() -> bool:
	return ok and _letter_texture != null and not _letter.is_empty()


## The seated animation playing now ("" without a seated sheet), for stills and tests.
func step_anim() -> String:
	return String(_steps[0]["anim"]) if not _steps.is_empty() else ""


## Reading the elder's letter on the log right now.
func reading() -> bool:
	return mode == "letter" and not standing()


## Where the reader and the letter are drawn, in global coordinates (a click there opens the journal at it).
func letter_rect_global() -> Rect2:
	return _seated.get_global_transform() * _letter_rect


func _wear(block: String) -> void:
	if block == "letter" and _letter_texture == null:
		block = "log"
	if block != "log" and block != "letter" and not _extra.has(block):
		block = "log"
	if block == _worn:
		return
	_worn = block
	_on_letter = block == "letter"
	match block:
		"log":
			_seated.texture = _log_texture
		"letter":
			_seated.texture = _letter_texture
		_:
			_seated.texture = _extra[block]["texture"]
	_shown = -1
	_update_prop()


## Takes the letter from the pocket, opens it, reads, looks up at the water, reads a little more and puts it away.
func _start_letter() -> void:
	letter_pending = false
	var t: Dictionary = tuning["log"]["letter"]
	letter_read_total = letter_read_sec(letter_words, t)
	var look_up := minf(_rng.randf_range(float(t["look_up_sec"][0]), float(t["look_up_sec"][1])), letter_read_total * 0.25)
	var reading := letter_read_total - look_up
	_begin("letter", [
		{"anim": "log_letter_out", "hold": 0.0},
		{"anim": "log_letter_open", "hold": 0.0},
		{"anim": "log_letter_read", "hold": reading * float(t["read_share"])},
		{"anim": "log_letter_look_up", "hold": look_up},
		{"anim": "log_letter_look_down", "hold": 0.0},
		{"anim": "log_letter_read", "hold": reading * (1.0 - float(t["read_share"]))},
		{"anim": "log_letter_put_away", "hold": 0.0},
	])
	letter_started.emit()


## How long he reads a letter of `words` words (issue 317: long enough to read it on the card):
## words / `words_per_sec` + `extra_sec`, clamped to `read_total_sec`. Pure.
static func letter_read_sec(words: int, letter_tuning: Dictionary) -> float:
	var r: Array = letter_tuning["read_total_sec"]
	return clampf(float(words) / float(letter_tuning["words_per_sec"]) + float(letter_tuning["extra_sec"]), float(r[0]), float(r[1]))


## Words in a letter as the card shows it (body and sign-off).
static func letter_word_count(letter: Dictionary) -> int:
	var text := "%s %s" % [String(letter.get("body", "")), String(letter.get("sign_off", ""))]
	return text.replace("\n", " ").replace("\t", " ").split(" ", false).size()


func _show(frame: int) -> void:
	if frame == _shown:
		return
	_shown = frame
	_seated.region_rect = Rect2(frame * _frame.x, 0, _frame.x, _frame.y)
	# The shader's world position is the texture's top-left: the strip, not the frame.
	(_seated.material as ShaderMaterial).set_shader_parameter("origin", _seated.position - Vector2(frame * _frame.x, 0) / _seated_scale)


func _range(key: String) -> float:
	var r: Array = tuning["log"][key]
	return _rng.randf_range(float(r[0]), float(r[1]))


func _begin(action: String, steps: Array) -> void:
	mode = action
	_steps = steps
	_step_t = 0.0
	_step_fps = _fps_of(_steps[0])
	_on_step(_steps[0])
	if not _log.is_empty():
		_wear(_sheet_of(String(_steps[0]["anim"])))
		_show(int(_anim(String(_steps[0]["anim"]))["frames"][0]))


func _fps_of(step: Dictionary) -> float:
	return float(_anim(String(step["anim"])).get("fps", 2.0)) * float(step.get("fps_scale", 1.0)) * _rng.randf_range(0.85, 1.15)


## Whether this seat lets him doze (a seat listing nothing does not).
func can_doze() -> bool:
	return "doze" in seat_supports


## The look's head-dipping frame (the first of its nod-off that is neither log_sit's nor a sleeping one), or -1.
func _dip_frame() -> int:
	if _log.is_empty() or not _log["animations"].has("log_nod_off"):
		return -1
	var asleep: Array = _log["animations"].get("log_doze", {}).get("frames", [])
	var sit := int(_log["animations"]["log_sit"]["frames"][0])
	for f in _log["animations"]["log_nod_off"]["frames"]:
		if int(f) != sit and not asleep.has(f):
			return int(f)
	return -1


## A drowsy-but-awake beat (late at night on a seat that does not support dozing).
func _start_drowsy() -> void:
	var t: Dictionary = tuning["log"]["drowsy"]
	var span := func(key: String) -> float:
		return _rng.randf_range(float(t[key][0]), float(t[key][1]))
	var beats := ["stretch", "sky"]
	if _dip_frame() >= 0:
		beats.append("dip")
	match String(beats[_rng.randi() % beats.size()]):
		"stretch":
			_begin("drowsy", [{"anim": "log_stretch", "hold": span.call("after_sec"), "fps_scale": float(t["stretch_fps_scale"])}])
		"sky":
			_begin("drowsy", [{"anim": "log_look_up", "hold": span.call("sky_sec"), "fps_scale": float(t["slow_fps_scale"])}])
		_:
			_begin("drowsy", [{"anim": DIP, "hold": span.call("dip_sec")},
					{"anim": "log_look_up", "hold": span.call("catch_sec")}])


func _rest() -> void:
	_begin("rest", [{"anim": "log_sit", "hold": _range("rest_sec")}])


## One idle action, weighted by the day (drowsy on a still warm afternoon, never asleep in the
## rain), never the action just done.
func _pick(env: SceneEnvironment) -> String:
	var weights := pick_weights(env)
	weights.erase(_last_action)
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := _rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return String(weights.keys()[0])


## The weight of each idle action now: the log sheet's own beats, then the activities this look has the art for
## (issue 123), by the hour and the weather. An activity without its sheet is left out; with the thermos, the
## log sheet's cup sip is (the thermos is the drink).
func pick_weights(env: SceneEnvironment) -> Dictionary:
	var weights: Dictionary = tuning["log"]["weights"].duplicate()
	if env != null:
		var drowsy := 1.0 + float(tuning["drowsy_boost"]) * (1.0 - clampf(env.wind.mean / 0.5, 0.0, 1.0)) * env.daylight()
		weights["doze"] = float(weights.get("doze", 0.0)) * drowsy * (1.0 - env.rain)
	if not can_doze():
		weights.erase("doze")
		var night := (1.0 - env.daylight()) if env != null else 0.0
		weights["drowsy"] = float(tuning["log"]["drowsy"]["weight_night"]) * night
	if not has_anim("log_look_down") or not has_anim("log_look_up_from_down"):
		weights.erase("glance_down")
	var acts: Dictionary = tuning["log"].get("activities", {})
	if acts.has("thermos") and has_anim("log_thermos_sip"):
		weights.erase("sip")
		weights["thermos"] = activity_weight(acts["thermos"], env, tuning["log"].get("chill", {}))
	if acts.has("paperback") and has_anim("log_paperback_read"):
		var w := activity_weight(acts["paperback"], env, tuning["log"].get("chill", {}))
		if env != null and env.daylight() < float(acts["paperback"].get("dark_below", 0.0)):
			w = 0.0
		weights["paperback"] = w
	var fidgets := fidget_names()
	if acts.has("fidget") and not fidgets.is_empty():
		var each := float(acts["fidget"]["weight"]) / float(fidgets.size())
		for f in fidgets:
			weights["fidget:" + String(f)] = each
	return weights


## An activity's weight at the hour and in the weather: `weight` × the `hours` curve ([minute, factor] pairs, straight
## between) × (1 + `chill` × how cold it feels) × the rain's share toward `rain`. Pure.
static func activity_weight(a: Dictionary, env: SceneEnvironment, chill_tuning: Dictionary) -> float:
	var w := float(a.get("weight", 0.0))
	if env == null:
		return w
	w *= hour_factor(a.get("hours", []), env.minute)
	w *= 1.0 + float(a.get("chill", 0.0)) * chill_of(env, chill_tuning)
	w *= lerpf(1.0, float(a.get("rain", 1.0)), clampf(env.rain, 0.0, 1.0))
	return w


## A [minute, factor] curve at `minute` (straight between points; 1 with no points). Pure.
static func hour_factor(points: Array, minute: float) -> float:
	if points.is_empty():
		return 1.0
	if minute <= float(points[0][0]):
		return float(points[0][1])
	for i in range(1, points.size()):
		var a: Array = points[i - 1]
		var b: Array = points[i]
		if minute <= float(b[0]):
			var u := (minute - float(a[0])) / maxf(float(b[0]) - float(a[0]), 0.001)
			return lerpf(float(a[1]), float(b[1]), u)
	return float(points[-1][1])


## How cold it feels at the log, 0..1: mist, wind, cloud, rain and the dark, each by its share in `chill_tuning`. Pure.
static func chill_of(env: SceneEnvironment, chill_tuning: Dictionary) -> float:
	var c := float(chill_tuning.get("mist", 0.0)) * env.mist + float(chill_tuning.get("wind", 0.0)) * env.wind.mean
	c += float(chill_tuning.get("cloud", 0.0)) * env.cloud + float(chill_tuning.get("rain", 0.0)) * env.rain
	c += float(chill_tuning.get("dark", 0.0)) * (1.0 - env.daylight())
	return clampf(c, 0.0, 1.0)


## The fidgets the look's fidget sheet has (issue 321), by name: every `log_fidget_<name>` animation, with or without
## `_in` / `_loop` / `_hold` / `_out`. Empty until the bench delivers the sheet.
func fidget_names() -> Array:
	var out: Array = []
	if not _extra.has("fidget"):
		return out
	for anim_name in _extra["fidget"]["meta"].get("animations", {}):
		var n := String(anim_name)
		if not n.begins_with("log_fidget_"):
			continue
		n = n.trim_prefix("log_fidget_")
		for suffix in ["_in", "_loop", "_hold", "_out"]:
			if n.ends_with(suffix):
				n = n.trim_suffix(suffix)
				break
		if n != "" and not out.has(n):
			out.append(n)
	out.sort()
	return out


func _span(r: Array) -> float:
	return _rng.randf_range(float(r[0]), float(r[1]))


func _start_log(action: String) -> void:
	_last_action = action
	if action.begins_with("fidget:"):
		_start_fidget(action.trim_prefix("fidget:"))
		return
	match action:
		"look":
			var first := LOOKS[_rng.randi() % LOOKS.size()]
			var steps: Array = [{"anim": "log_look_" + first, "hold": _range("hold_sec")}]
			if _rng.randf() < float(tuning["log"]["second_glance"]):
				var others := LOOKS.filter(func(l: String) -> bool: return l != first)
				steps.append({"anim": "log_look_" + String(others[_rng.randi() % others.size()]), "hold": _range("hold_sec")})
			_begin("look", steps)
		"follow":
			_begin("follow", [{"anim": "log_follow", "hold": _range("hold_sec")}])
		"glance_down":
			_begin("glance_down", [{"anim": "log_look_down", "hold": _span(tuning["log"]["glance_down"]["hold_sec"])},
					{"anim": "log_look_up_from_down", "hold": _range("after_sec")}])
		"stretch":
			_begin("stretch", [{"anim": "log_stretch", "hold": _range("after_sec")}])
		"sip":
			_begin("sip", [{"anim": "log_sip", "hold": _range("after_sec")}])
		"thermos":
			_start_thermos()
		"paperback":
			_start_paperback()
		"drowsy":
			_start_drowsy()
		"doze":
			if not can_doze():
				_start_drowsy()
				return
			_begin("doze", [{"anim": "log_nod_off", "hold": 0.0}, {"anim": "log_doze", "hold": _range("doze_sec")},
					{"anim": "log_wake", "hold": _range("after_sec")}])
		_:
			_rest()


## A drink from the thermos (issue 122's sheet): picked up from the ground where he stood it (or out of the bag the
## first time), the cap unscrewed into a cup, one to a few sips, screwed back and stood on the ground again, where it
## stays through everything else until he packs up.
func _start_thermos() -> void:
	var a: Dictionary = tuning["log"]["activities"]["thermos"]
	var from_ground := thermos_down and has_anim("log_thermos_pick_up")
	var steps: Array = [{"anim": "log_thermos_pick_up" if from_ground else "log_thermos_out", "hold": 0.0, "lift": true},
			{"anim": "log_thermos_unscrew", "hold": 0.0}]
	var sips: Array = a["sips"]
	for i in _rng.randi_range(int(sips[0]), int(sips[1])):
		steps.append({"anim": "log_thermos_to_sip", "hold": 0.0})
		steps.append({"anim": "log_thermos_sip", "hold": _span(a["sip_sec"])})
		steps.append({"anim": "log_thermos_from_sip", "hold": _span(a["between_sec"])})
	steps.append({"anim": "log_thermos_screw_back", "hold": _span(a["between_sec"]) * 0.5})
	if _has_prop() and has_anim("log_thermos_set_down") and (from_ground or _rng.randf() < float(a["set_down_share"])):
		steps.append({"anim": "log_thermos_set_down", "hold": _range("after_sec"), "ground": true})
	else:
		steps.append({"anim": "log_thermos_put_away", "hold": _range("after_sec")})
	_begin("thermos", steps)


## Reading the paperback (issue 122's sheet): out, open, reading with a page turned now and then and a look out at the
## water between, closed and put away. Something worth watching lifts his eyes from the page (`_step_log`).
func _start_paperback() -> void:
	var a: Dictionary = tuning["log"]["activities"]["paperback"]
	var steps: Array = [{"anim": "log_paperback_out", "hold": 0.0}, {"anim": "log_paperback_open", "hold": 0.0}]
	var left := _span(a["read_sec"])
	while left > 0.0:
		var page := minf(_span(a["page_sec"]), left)
		left -= page
		steps.append({"anim": "log_paperback_read", "hold": page})
		if left <= 0.0:
			break
		if _rng.randf() < float(a["look_up_chance"]):
			steps.append({"anim": "log_paperback_look_up", "hold": _span(a["look_up_sec"])})
			steps.append({"anim": "log_paperback_look_down", "hold": 0.0})
		else:
			steps.append({"anim": "log_paperback_turn_page", "hold": 0.0})
	steps.append({"anim": "log_paperback_close", "hold": 0.0})
	steps.append({"anim": "log_paperback_put_away", "hold": _range("after_sec")})
	_begin("paperback", steps)


## One fidget from the look's fidget sheet (issue 321): in, held (or looped) a while, out.
func _start_fidget(fidget: String) -> void:
	var base := "log_fidget_" + fidget
	var hold := _span(tuning["log"]["activities"]["fidget"]["hold_sec"])
	var steps: Array = []
	if has_anim(base + "_in"):
		steps.append({"anim": base + "_in", "hold": 0.0})
	var held := ""
	for n in [base + "_loop", base + "_hold", base]:
		if has_anim(n):
			held = n
			break
	if held != "":
		steps.append({"anim": held, "hold": hold})
	elif not steps.is_empty():
		steps[-1]["hold"] = hold
	if has_anim(base + "_out"):
		steps.append({"anim": base + "_out", "hold": _range("after_sec")})
	if steps.is_empty():
		_rest()
		return
	_begin("fidget", steps)


## Where he looks to watch `p` (points): left, right or up; down at the ground by his boots (the looking-down heads,
## issue 313) when it is close, below him and not far to the side. Never up at something below him.
func _watch_dir(p: Vector2, is_near: bool) -> String:
	var w: Dictionary = tuning["log"]["watch"]
	var dx := p.x - seat.x
	# Already looking down, he keeps to it a little past the edges (a bird hopping about there is no reason to turn).
	var give := float(w["down_give_pt"]) if _watching.begins_with("down") else 0.0
	if is_near and p.y > seat.y + float(w["below_pt"]) - give and absf(dx) < float(w["down_reach_pt"]) + give \
			and has_anim("log_look_down_left") and has_anim("log_look_down_right"):
		if absf(dx) < float(w["down_mid_pt"]) and has_anim("log_look_down"):
			return "down"
		return "down_left" if dx < 0.0 else "down_right"
	var reach := float(tuning["follow_px"]) * 0.25
	var dir := "left" if dx < -reach else ("right" if dx > reach else "up")
	if dir == "up" and p.y > seat.y:
		dir = "left" if dx < 0.0 else "right"
	return dir


## The heads' way back up from looking down in `dir` ("" when `dir` is not a looking-down one).
func _up_from(dir: String) -> String:
	if not dir.begins_with("down"):
		return ""
	var n := "log_look_up_from_" + dir
	return n if has_anim(n) else ""


## Visible breathing for a whole sprite (issue 123): on the in-breath the rows above the hips are drawn `lift_px` art
## px higher (the seated shader's `breath_lift`), the legs staying put; slow, each breath a little different.
func _breathe(dt: float) -> void:
	var b: Dictionary = tuning["log"].get("breath", {})
	if b.is_empty():
		return
	_breath += dt / maxf(_breath_period, 0.5)
	if _breath >= 1.0:
		_breath = fposmod(_breath, 1.0)
		_breath_period = _span(b["doze_sec"] if mode == "doze" else b["sec"])
	var ins: Array = b["in_share"]
	var lift := float(b["lift_px"]) if _breath >= float(ins[0]) and _breath < float(ins[1]) else 0.0
	if lift != _lifted:
		_lifted = lift
		(_seated.material as ShaderMaterial).set_shader_parameter("breath_lift", lift)


## Whether he is on the in-breath now (rows above the hips lifted), for tests and stills.
func breathing_in() -> bool:
	return _lifted > 0.0


func _set_breath_row() -> void:
	var b: Dictionary = tuning.get("log", {}).get("breath", {})
	if _log.is_empty() or _seated.material == null:
		return
	var hip := float(AssetLibrary.vec2i(_log["anchor"]).y)
	(_seated.material as ShaderMaterial).set_shader_parameter("breath_row", hip - float(b.get("above_hip_px", 10.0)))


## Watching what moves (issue 123: follow animals more, never twitchy): something in sight draws his eyes while he
## rests or glances, for a spell (`watch.far_sec`; one at his feet up to `near_max_sec`), then he lets it be for a
## while (`gap_sec`) and gets on with his idle life. A new arrival close by is watched at once. The way he looks
## changes only after `min_dir_sec`, and a looking-down head comes back up through its own frames.
func _watch(dt: float) -> void:
	var w: Dictionary = tuning["log"]["watch"]
	if mode != "watch":
		_watching = ""
	_dir_t += dt
	_watch_gap = maxf(0.0, _watch_gap - dt)
	if near != null and not _had_near:
		_watch_gap = 0.0
	_had_near = near != null
	var target: Variant = near if near != null else interest
	if target != null:
		_last_target = target
		_lost_t = 0.0
	elif mode == "watch" and _lost_t < float(w["lose_sec"]):
		# Gone from sight a moment (a hop, a flit behind a stem): his eyes stay where it was.
		_lost_t += dt
		target = _last_target
	var dir := ""
	if target != null and mode in ["rest", "look", "follow", "watch"] and (mode == "watch" or _watch_gap <= 0.0):
		dir = _watch_dir(target as Vector2, near != null or (_watching.begins_with("down") and target == _last_target))
	if mode == "watch":
		_watch_t += dt
		if dir != "" and _watch_t >= _watch_cap:
			dir = ""
			_watch_gap = _span(w["gap_sec"])
	if dir != "" and dir != _watching and (mode != "watch" or _dir_t >= float(w["min_dir_sec"])):
		if mode != "watch":
			_watch_t = 0.0
			_watch_cap = float(w["near_max_sec"]) if near != null else _span(w["far_sec"])
		var steps: Array = []
		var back := _up_from(_watching)
		if back != "" and not dir.begins_with("down"):
			steps.append({"anim": back, "hold": 0.0})
		steps.append({"anim": "log_look_" + dir, "hold": 3600.0})
		_watching = dir
		_dir_t = 0.0
		_begin("watch", steps)
	elif dir == "" and mode == "watch":
		var back := _up_from(_watching)
		_watching = ""
		if _watch_gap <= 0.0:
			_watch_gap = _span(w["gap_sec"])
		if back != "":
			_begin("look", [{"anim": back, "hold": _range("after_sec")}])
		else:
			_rest()
	elif mode == "paperback" and target != null and _watch_gap <= 0.0 and not _steps.is_empty() \
			and String(_steps[0]["anim"]) == "log_paperback_read" and _step_t > float(w["page_min_sec"]):
		# Something worth a look: his eyes come up from the page, then back to it.
		var left := float(_steps[0]["hold"]) - _step_t
		_steps[0]["hold"] = _step_t
		var look_sec := _span(w["far_sec"]) * float(w["from_book_share"])
		_steps.insert(1, {"anim": "log_paperback_look_up", "hold": look_sec})
		_steps.insert(2, {"anim": "log_paperback_look_down", "hold": 0.0})
		_steps.insert(3, {"anim": "log_paperback_read", "hold": maxf(left, float(w["page_min_sec"]))})
		_watch_gap = look_sec + _span(w["gap_sec"])


func _step_log(dt: float, env: SceneEnvironment) -> void:
	_breathe(dt)
	_watch(dt)
	_step_t += dt
	var step: Dictionary = _steps[0]
	_wear(_sheet_of(String(step["anim"])))
	var anim := _anim(String(step["anim"]))
	var frames: Array = anim["frames"]
	var played := frames.size() / maxf(_step_fps, 0.01)
	var i := int(_step_t * _step_fps)
	if bool(anim.get("loop", false)):
		_show(int(frames[i % frames.size()]))
		if _step_t >= float(step["hold"]):
			_advance(env)
	else:
		_show(int(frames[mini(i, frames.size() - 1)]))
		if _step_t >= played + float(step["hold"]):
			_advance(env)


func _advance(env: SceneEnvironment) -> void:
	var done: Dictionary = _steps.pop_front()
	if bool(done.get("ground", false)):
		thermos_down = true
		_update_prop()
	if not _steps.is_empty():
		_step_t = 0.0
		_step_fps = _fps_of(_steps[0])
		_on_step(_steps[0])
		return
	if mode == "rest" and letter_pending and can_read():
		_start_letter()
	elif mode == "rest" and (away or (letter_due and can_read())):
		_rest()
	elif mode == "rest":
		_start_log(_pick(env))
	else:
		_rest()


## Starts one idle action now (clips and the debug panel), on the log only.
func act(action: String) -> void:
	if ok and not _log.is_empty() and not standing():
		_watching = ""
		_start_log(action)


## He is on the log again after being away without standing up (the van's `arrive_now`; issue 359): whatever idle
## went on unseen is dropped and he starts from rest, so a waiting letter comes first. Never mid-pour: the thermos
## (and a letter he was reading) plays on.
func sit_down() -> void:
	if not ok or _log.is_empty() or mode in ["rest", "thermos", "letter"]:
		return
	_watching = ""
	_rest()


## A step starting: picking the thermos up takes it off the ground.
func _on_step(step: Dictionary) -> void:
	if bool(step.get("lift", false)):
		thermos_down = false
		_update_prop()


static func _depth_for(meta: Dictionary, band_scale: float) -> String:
	var best := "front"
	var gap := absf(1.0 - band_scale)
	for depth in meta.get("depths", {}):
		var s := float(meta["depths"][depth].get("scale", 1.0))
		if absf(s - band_scale) < gap:
			gap = absf(s - band_scale)
			best = String(depth)
	return best


func _part(sprite: Sprite2D, frame: Image, from_row: int, to_row: int, shader: Shader) -> void:
	var rows := maxi(1, to_row - from_row)
	var region := frame.get_region(Rect2i(0, from_row, _frame.x, rows))
	sprite.texture = ImageTexture.create_from_image(region)
	sprite.centered = false
	sprite.position = Vector2(0, from_row)
	sprite.set_meta("row", from_row)
	sprite.material = _lit(shader)
	add_child(sprite)


func _lit(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.set_shader_parameter("depth", 0.6)
	materials.append(m)
	return m


## Which seated action is going on, for the behaviour engine and tests.
func doing() -> String:
	return mode


## Wake him (something startling happened nearby).
func rouse() -> void:
	if mode == "doze":
		if not _log.is_empty():
			_begin("doze", [{"anim": "log_wake", "hold": _range("after_sec")}])
			return
		_wake()


func step(dt: float, env: SceneEnvironment) -> void:
	if not ok:
		return
	if not _log.is_empty():
		_step_log(dt, env)
		return
	_left -= dt
	if interest != null and mode in ["rest", "look"]:
		var dx: float = (interest as Vector2).x - (seat.x)
		_look_target = clampf(dx / float(tuning["follow_px"]), -1.0, 1.0)
		mode = "look"
		_left = maxf(_left, 0.8)
	elif _left <= 0.0:
		_next(env)
	if mode == "look" and interest == null and not _glances.is_empty() and _left <= float(_glances[0]["until"]):
		_look_target = float(_glances.pop_front()["to"])
	# Head turns quickly but not instantly; a nod settles slowly.
	look = move_toward(look, _look_target, dt * float(tuning["turn_per_sec"]))
	_nod = move_toward(_nod, _nod_target, dt * (float(tuning["nod_per_sec"]) if _nod_target > _nod else float(tuning["wake_per_sec"])))
	_lift = move_toward(_lift, _lift_target, dt * float(tuning["lift_per_sec"]))
	_breath_sec = float(tuning["breath_sec_doze"]) if mode == "doze" else float(tuning["breath_sec"])
	_breath = fposmod(_breath + dt / _breath_sec, 1.0)
	_pose()
	if _playing != "":
		_play(dt)


func _next(env: SceneEnvironment) -> void:
	if mode == "doze":
		_wake()
		return
	if mode == "stretch":
		_lift_target = 0.0
	var weights: Dictionary = tuning["weights"].duplicate()
	# Drowsy on a warm, still afternoon; never in the rain.
	var drowsy := 1.0 + float(tuning["drowsy_boost"]) * (1.0 - clampf(env.wind.mean / 0.5, 0.0, 1.0)) * env.daylight()
	weights["doze"] = float(weights["doze"]) * drowsy * (1.0 - env.rain)
	if not can_doze():
		weights.erase("doze")
	if mode != "rest":
		mode = "rest"
		_look_target = 0.0 if _rng.randf() < 0.6 else _look_target
		_left = _rng.randf_range(float(tuning["rest_sec"][0]), float(tuning["rest_sec"][1]))
		return
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := _rng.randf() * total
	var pick := "look"
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			pick = String(k)
			break
	_start(pick)


func _start(action: String) -> void:
	if not _log.is_empty():
		_start_log(action)
		return
	if action in ["doze", "drowsy"] and not can_doze():
		action = "stretch"
	mode = action
	match action:
		"look":
			_glances.clear()
			var span := 0.0
			var n := _rng.randi_range(1, 3)
			var total := 0.0
			var holds: Array = []
			for i in n:
				var hold := _rng.randf_range(1.2, 3.5)
				holds.append(hold)
				total += hold
			_left = total
			span = total
			for i in n:
				span -= float(holds[i])
				var to := _rng.randf_range(0.5, 1.0) * (-1.0 if _rng.randf() < 0.5 else 1.0)
				if i == n - 1 and _rng.randf() < 0.4:
					to = 0.0
				_glances.append({"until": span + float(holds[i]) - 0.01, "to": to})
			_look_target = float(_glances.pop_front()["to"])
		"stretch":
			_left = float(tuning["stretch_sec"])
			_lift_target = float(tuning["stretch_px"])
			_look_target = 0.0
		"sip":
			if not _delivered.has("sip"):
				mode = "rest"
				_left = 2.0
				return
			_left = 3.0
		"doze":
			_left = _rng.randf_range(float(tuning["doze_sec"][0]), float(tuning["doze_sec"][1]))
			_nod_target = float(tuning["doze_nod_px"])
			_look_target = 0.0
	if _delivered.has(action):
		_playing = action
		_play_t = 0.0


func _wake() -> void:
	_nod_target = 0.0
	mode = "look"
	_glances = [{"until": 1.0, "to": 0.0}]
	_look_target = -0.8 if _rng.randf() < 0.5 else 0.8
	_left = 2.2


func _pose() -> void:
	# Breathing: the body rises half a pixel on the in-breath; the head rides on it.
	var inhale := 0.5 - 0.5 * cos(TAU * _breath)
	var rise := -float(tuning["breath_px"]) * smoothstep(0.25, 0.75, inhale)
	var body_y := rise - _lift
	_body.position = Vector2(0, float(_body.get_meta("row")) + _snap(body_y))
	var head_x := _snap(look * float(tuning["look_px"]))
	_head.position = Vector2(head_x, float(_head.get_meta("row")) + _snap(body_y + _nod - _lift * 0.5))


## Positions move in whole physical pixels.
func _snap(v: float) -> float:
	return roundf(v / snap_step) * snap_step


func _play(dt: float) -> void:
	var anim: Dictionary = _delivered[_playing]
	var frames: Array = anim["frames"]
	_play_t += dt
	var i := int(_play_t * float(anim.get("fps", 4)))
	if i >= frames.size() and not bool(anim.get("loop", false)):
		_playing = ""
		_full.visible = false
		for s in [_legs, _body, _head]:
			s.visible = true
		return
	var frame := int(frames[i % frames.size()])
	_full.texture = ImageTexture.create_from_image(_sheet.get_region(Rect2i(frame * _frame.x, 0, _frame.x, _frame.y)))
	_full.visible = true
	for s in [_legs, _body, _head]:
		s.visible = false
