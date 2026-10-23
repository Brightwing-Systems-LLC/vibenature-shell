class_name SceneVan
extends Node2D

## The van on the far bank and you coming and going (issue 198,
## the route issue 255): what `DailyRhythm` decides, played in
## the scene with the bench's van (the companion's `van/`, issue 197) and the look's day actions (`AvatarLook.day_sheets`).
##
## Movement makes sense (the human, 2026-10-19). The van parks on the far bank and the log is on the near bank, so
## you never cross the pond: you step out of the van, walk left along the far bank at the far band's size (`@far`,
## life size), go out of sight behind the near bank's plants under the birch, and come in at full size from the
## scene's left edge by the birch, walk to the log, put the thermos down and sit. Leaving is the same route
## reversed. The size changes only while you are out of sight (`route.far_hide_x_pt`, `route.near_from_x_pt`,
## both checked against the kit's pixels in tests). Legs move at the speed the body travels (walk frames by the
## ground covered), the van's wheels turn at its road speed (drive frames by distance) and it brakes to park and
## pulls away. You step down off the van's step (`day_step_out`) and up into it (`day_step_in`), turn to walk left
## with `day_turn_left` and carry the thermos on every walk; the lamps, once lit for the wrap-up, stay lit through
## the door and the drive-off (the van's `*_lit` frames; issue 264). They also come on for any departure once it is
## dark, and for an arrival before sunrise (`dark`, from `lamps_due`; issue 277). A look without day art keeps the fade
## at the log.
##
## Since issue 279 the van comes in from the right facing left and parks about in the middle of the far bank (the
## sheet flipped, so the door you step out of and back into faces the viewer). To leave it makes a real three-point
## turn (`_turn_out`) and drives out to the right. Its paint is the player's (`use_paint`, `VanPaint`), and when the
## lamps are on they glow by how dark it is (`_glow`: additive light, never drawn art).
##
## Everything is planned as two timed tracks (`plan`), the van's and yours, so a plan can be sampled at any time
## (`pose_at`) by tests and probes. `play` takes the rhythm's words: "arrive", "arrive_now", "leave", "leave_now",
## "invite" (the light leans golden, the lights come on, you stand, stretch and pack), "stay" (unpack and sit back
## down; lights off). Positions are in points; the scene reads `sitter_alpha`, `near` and `golden` each step.
## Nothing here is saved.
##
## Shelter from the rain (issue 476, the human: "have him run
## to the van and shelter there while it rains"): `shelter` is the evening's walk to the van without the stretch and
## a little hurried (`scene.day.shelter.hurry`), and the van stays; inside, a warm light shows in its windows
## (`interior`: the bench's own lit window pixels from `lights_on` over the parked frame, and an additive glow by
## how dark it is; a light effect in code, like the lamps). `unshelter` is the arrival's walk from the door to the
## log. `SceneShelter` decides when (the scene calls these). While he shelters the rhythm still decides: "leave"
## drives off with him inside (`leave_sheltered`: no walk back first), "invite" lights the lamps and he waits
## inside until "leave" or "stay"; a word that comes while he is walking either way waits until he is in or seated.

## You stepped out and wait at the door ("arrive_first", issue 199): the welcome opens.
signal at_door

## Seconds into the arrival where the first run waits at the door, or -1.
var hold_at := -1.0
var _door_told := false
## The scene's own tuning (`scene.day` in balance.json).
var tuning: Dictionary = {}
## "parked", "arriving", "invited", "leaving_walk", "leaving_drive", "away", and sheltering from the rain (issue
## 476): "sheltering" (walking to the van), "sheltered" (inside), "returning" (walking back to the log).
var state := "parked"
## 0..1: the warm light inside the van while you shelter in it (issue 476).
var interior := 0.0
## The wrap-up came while you shelter: the lamps are on and you wait inside for "leave" or "stay".
var wrap_inside := false
## A rhythm word that came while you were walking to or from the shelter, played once you are in or seated.
var pending := ""
## The seated or fading sitter's alpha (0 while you are standing, walking or away).
var sitter_alpha := 1.0
## You at full size near the log: {"show", "frame", "x" (feet, points), "flip"}; "show" false otherwise.
var near := {"show": false}
## 0..1: how far the light has leaned golden for the wrap-up.
var golden := 0.0
var lights := false
## It is dark now (dusk until sunrise, `scene.day.lamps`): the scene sets it before `play`, from `lamps_due`.
var dark := false
## Where the van's wheels touch the bank now (x, points), and you on the far bank ({} when not there).
var van_x := 0.0
var far := {}
## The plan playing now (`plan`), or {} when nothing moves.
var current := {}
var _t := 0.0
var _density := 1.0
var _van_meta := {}
var _day := {}
var _body := Sprite2D.new()
var _walker := Sprite2D.new()
var _cfg := {}
var _rest := {"van": {"kind": "anim", "anim": "parked", "x": 0.0, "flip": true}, "who": {"kind": "seat", "a0": 1.0, "a1": 1.0}}
## The van's paint ({body, accent}, `VanPaint`); set before `setup`, changed with `use_paint`.
var paint: Dictionary = {}
## 0..1: how dark it is now (from the light's tint, `scene.day.glow`): the lamps' glow scales with it.
var darkness := 0.0
var _art := ""
## The lamps' glow (issue 279, the human: a light effect in code, not drawn art): one additive radial sprite per
## lit lamp, and a faint pool on the ground ahead at dusk. Lamps are found in the bench's lit frames, never placed.
var _glows: Array[Sprite2D] = []
var _pool := Sprite2D.new()
var _glow_texture: Texture2D
var _lamps := {}
var _twins := {}
## The lit windows (issue 476): the bench's lit window pixels over the parked frame, and a glow on each window.
var _windows := Sprite2D.new()
var _window_glows: Array[Sprite2D] = []
var _window_spots: Array = []
var _windows_ready := false
static var _raw_cache := {}


## The van's `art` or `meta` (`scene.day.van`), a companion file (`AssetLibrary.companion_file`), "" if not set.
static func file(van: Dictionary, key: String) -> String:
	var rel := String(van.get(key, ""))
	return AssetLibrary.companion_file(rel) if rel != "" else ""


func setup(day_tuning: Dictionary, density: float) -> void:
	tuning = day_tuning
	name = "Van"
	_density = maxf(density, 0.01)
	var van: Dictionary = tuning["van"]
	var meta_file := SceneVan.file(van, "meta")
	if meta_file != "" and FileAccess.file_exists(meta_file):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(meta_file))
		if parsed is Dictionary:
			_van_meta = parsed
	_art = SceneVan.file(van, "art")
	_pool.name = "LampPool"
	_glow_texture = _radial()
	_pool.texture = _glow_texture
	_pool.material = _additive()
	_pool.visible = false
	add_child(_pool)
	for sprite in [_body, _walker]:
		sprite.centered = false
		sprite.region_enabled = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(sprite)
	_walker.visible = false
	_windows.name = "Windows"
	_windows.centered = false
	_windows.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_windows.visible = false
	add_child(_windows)
	move_child(_windows, _walker.get_index())
	use_paint(paint)
	position = Vector2(0.0, float(tuning["route"]["lane_y_pt"]))
	scale = Vector2.ONE / _density
	_cfg = config(tuning, _van_meta, {}, Vector2.ZERO, _density)
	_rest["van"]["x"] = float(_cfg["park_x"])
	_apply(_rest)


## The look's day actions (`AvatarLook.day_sheets`, {} for a look without them) and where the seated sheet's
## feet are (points): the route starts and ends there.
func use_day(sheets: Dictionary, feet: Vector2) -> void:
	_day = sheets.get("meta", {})
	_walker.texture = ImageTexture.create_from_image(sheets["far"]) if sheets.has("far") else null
	_cfg = config(tuning, _van_meta, _day, feet, _density)


## The van's paint (issue 279, `VanPaint`): the whole sheet swapped colour for colour, every frame and the lit ones,
## always (even the default choice). Before `setup` it is only kept.
func use_paint(choice: Dictionary) -> void:
	paint = VanPaint.sanitize(choice, _van_meta) if not _van_meta.is_empty() else choice
	if _art == "" or _van_meta.is_empty():
		return
	var image := VanPaint.sheet(_art, _van_meta, paint)
	_body.texture = ImageTexture.create_from_image(image) if image != null else null
	if is_inside_tree() or not current.is_empty():
		_show_pose()


## The painted sheet the van draws now (tests read its pixels), or null without the art.
func painted_image() -> Image:
	return _body.texture.get_image() if _body.texture != null else null


## Whether the van's art has been delivered (issue 197); without it the slot draws nothing.
func has_art() -> bool:
	return _body.texture != null


## The size the van's sprite draws (sheet px): one frame of `van.png`, never the whole 27-frame strip.
func drawn_size() -> Vector2i:
	if not has_art():
		return Vector2i.ZERO
	return Vector2i(_body.get_rect().size)


## Where the van is drawn now in the scene's points (its bottom is where its wheels stand); an empty
## rect while it is away or has no art. Animals on the far bank keep clear of it (issue 410).
func footprint() -> Rect2:
	if not visible or not has_art() or state == "away":
		return Rect2()
	return Rect2(position + _body.position * scale, _body.region_rect.size * scale)


## Whether the look walks the route (its day actions are delivered), or fades at the log.
func walks() -> bool:
	return bool(_cfg.get("walks", false))


func here() -> bool:
	return state in ["parked", "invited"]


## Whether the van is on the bank now (moving, parked or lit), art or not.
func on_bank() -> bool:
	return state != "away"


## The rhythm's word for what happens now (see the class notes). "arrive_first" is the first run's arrival
## (issue 199): the same drive-in, but you wait at the van's door until `release` (the welcome is open).
func play(what: String) -> void:
	if what in ["leave", "invite", "stay"] and _play_sheltering(what):
		return
	_t = 0.0
	hold_at = -1.0
	_door_told = false
	pending = ""
	wrap_inside = false
	interior = 0.0
	match what:
		"arrive", "arrive_first":
			state = "arriving"
			lights = dark
			current = plan(_cfg, "arrive", lights)
			if what == "arrive_first":
				hold_at = float(current.get("out_at", 0.0))
		"arrive_now":
			state = "parked"
			lights = false
			current = {}
		"leave":
			state = "leaving_walk"
			lights = lights or dark
			current = plan(_cfg, "leave_standing" if state_standing() else "leave", lights)
		"leave_now":
			state = "away"
			lights = false
			current = {}
		"invite":
			state = "invited"
			lights = true
			current = plan(_cfg, "invite", true)
		"stay":
			state = "parked"
			lights = false
			current = plan(_cfg, "stay") if state_standing() else {}
	_show_pose()


## The rhythm's word while you shelter from the rain (issue 476); false when you are not sheltering. Inside: "leave"
## drives off with you (no walk back first), "invite" turns the lamps on and you wait inside, "stay" turns them off
## again. Walking to or from the van: the word waits (`pending`) until you are in or seated; "leave" beats "invite",
## and "stay" takes back an "invite" still waiting.
func _play_sheltering(what: String) -> bool:
	if state in ["sheltering", "returning"]:
		match what:
			"leave":
				pending = "leave"
			"invite":
				if pending != "leave":
					pending = "invite"
			"stay":
				if pending == "invite":
					pending = ""
		return true
	if state != "sheltered":
		return false
	match what:
		"leave":
			_t = 0.0
			wrap_inside = false
			state = "leaving_drive"
			lights = lights or dark
			current = plan(_cfg, "leave_sheltered", lights)
		"invite":
			wrap_inside = true
			lights = true
		"stay":
			wrap_inside = false
			lights = false
	_show_pose()
	return true


## Whether you can go to shelter in the van now: the van parked, you seated on the log, nothing else moving.
func can_shelter() -> bool:
	return state == "parked" and current.is_empty() and hold_at < 0.0


## Whether you can walk back to the log now: in the van, no wrap-up waiting on you and no word pending.
func can_unshelter() -> bool:
	return state == "sheltered" and not wrap_inside and pending == ""


## You go to the van to shelter from the rain (issue 476): the evening's walk without the stretch, hurried.
func shelter() -> void:
	if not can_shelter():
		return
	_t = 0.0
	state = "sheltering"
	current = plan(hurried(_cfg, tuning.get("shelter", {})), "shelter", lights)
	_show_pose()


## The rain is over: you get out and walk back to the log and sit (the arrival's walk from the door).
func unshelter() -> void:
	if not can_unshelter():
		return
	_t = 0.0
	state = "returning"
	lights = false
	current = plan(_cfg, "unshelter")
	_show_pose()


## The route's numbers for a hurried walk (issue 476): walking `hurry` times as fast (the legs keep to the ground
## covered), the day actions played `hurry` times as fast, and `hidden_sec` out of sight instead of the route's.
static func hurried(cfg: Dictionary, shelter: Dictionary) -> Dictionary:
	var out := cfg.duplicate()
	var hurry := maxf(float(shelter.get("hurry", 1.0)), 0.01)
	out["far_walk"] = float(cfg["far_walk"]) * hurry
	out["near_walk"] = float(cfg["near_walk"]) * hurry
	out["rate"] = hurry
	out["hidden_sec"] = float(shelter.get("hidden_sec", cfg["hidden_sec"]))
	return out


## Whether you are inside the van now (its windows lit): sheltered, or in through the door on the way, or not yet out.
func inside() -> bool:
	match state:
		"sheltered":
			return true
		"sheltering":
			return _t >= float(current.get("in_at", INF))
		"leaving_drive":
			return String(current.get("kind", "")) == "leave_sheltered"
	return false


## Whether you are standing by the log now (after the wrap-up's stand, stretch and pack).
func state_standing() -> bool:
	return not current.is_empty() and String(current.get("kind", "")) == "invite"


## Whether you are standing at the van's door waiting (the first run's welcome is open).
func waiting_at_door() -> bool:
	return hold_at >= 0.0 and not current.is_empty() and _t >= hold_at


## The look changed while you wait at the door (the welcome's picker): the route is planned again for it and
## you stay where you are.
func rehold() -> void:
	if hold_at < 0.0 or String(current.get("kind", "")) != "arrive":
		return
	current = plan(_cfg, "arrive", lights)
	hold_at = float(current.get("out_at", 0.0))
	_t = minf(_t, hold_at)
	_show_pose()


## The welcome is done: you walk on from the door to the log and sit, on the route planned for your look now.
func release() -> void:
	if hold_at < 0.0:
		return
	var at := minf(_t, hold_at)
	current = plan(_cfg, "arrive", lights)
	_t = minf(at, float(current.get("out_at", 0.0)))
	hold_at = -1.0
	_show_pose()


func step(dt: float, tint: Color) -> void:
	_t += dt
	if hold_at >= 0.0 and _t >= hold_at:
		_t = hold_at
		if not _door_told:
			_door_told = true
			at_door.emit()
	if not current.is_empty():
		var kind := String(current["kind"])
		if kind.begins_with("leave") and state == "leaving_walk" and _t >= float(current.get("drive_at", INF)):
			state = "leaving_drive"
		if _t >= float(current["end"]) and not bool(current.get("holds", false)):
			match kind:
				"arrive", "stay":
					state = "parked"
					lights = false
				"leave", "leave_standing", "leave_sheltered":
					state = "away"
					lights = false
					interior = 0.0
				"shelter":
					state = "sheltered"
				"unshelter":
					state = "parked"
			current = {}
			if state in ["sheltered", "parked"] and pending != "":
				var word := pending
				pending = ""
				play(word)
	var golden_sec := maxf(float(tuning["golden_sec"]), 0.01)
	golden = move_toward(golden, 1.0 if state == "invited" or wrap_inside else 0.0, dt / golden_sec)
	var light_sec := maxf(float(tuning.get("shelter", {}).get("light_sec", 2.0)), 0.01)
	interior = move_toward(interior, 1.0 if inside() else 0.0, dt / light_sec)
	_body.modulate = tint
	_walker.modulate = Color(tint, _walker.modulate.a)
	darkness = dark_share(tuning.get("glow", {}), tint)
	_show_pose()


## 0..1 how dark the light is, by its tint's luminance between `lum_day` (none) and `lum_dark` (full).
static func dark_share(glow: Dictionary, tint: Color) -> float:
	var day := float(glow.get("lum_day", 0.9))
	var night := float(glow.get("lum_dark", 0.4))
	return clampf((day - tint.get_luminance()) / maxf(day - night, 0.01), 0.0, 1.0)


func _show_pose() -> void:
	if state == "away":
		visible = false
		sitter_alpha = 0.0
		near = {"show": false}
		return
	if not current.is_empty():
		_apply(pose_at(current, _t))
	elif state == "sheltered":
		_apply({"van": _rest["van"], "who": {"kind": "none"}})
	else:
		_apply(_rest)


func _apply(pose: Dictionary) -> void:
	visible = has_art()
	var v: Dictionary = pose["van"]
	van_x = float(v["x"])
	far = {}
	if has_art():
		var frame := int(v.get("frame", -1))
		if frame < 0:
			frame = int(_van_meta["animations"]["lights_on" if lights else "parked"]["frames"][0])
		var fw := int(_van_meta["frame_w"])
		_body.region_rect = Rect2(frame * fw, 0, fw, int(_van_meta["frame_h"]))
		var anchor := AssetLibrary.vec2i(_van_meta["anchor"])
		var flip := bool(v.get("flip", false))
		_body.flip_h = flip
		var ax := (fw - anchor.x) if flip else anchor.x
		_body.position = Vector2(roundf(float(v["x"]) * _density) - ax,
				roundf(float(v.get("y", 0.0)) * _density) + float(v.get("dy", 0)) - anchor.y)
		_glow(frame, flip)
		_show_windows(frame, flip)
	var w: Dictionary = pose["who"]
	var kind := String(w["kind"])
	sitter_alpha = 0.0
	near = {"show": false}
	_walker.visible = false
	match kind:
		"seat":
			sitter_alpha = float(w.get("alpha", 1.0))
		"near":
			near = {"show": true, "frame": int(w["frame"]), "x": float(w["x"]), "flip": bool(w["flip"])}
		"far":
			if _walker.texture == null:
				return
			var far_meta: Dictionary = _day["depths"]["far"]
			var size := AssetLibrary.vec2i(far_meta["frame"])
			var anchor := AssetLibrary.vec2i(far_meta["anchor"])
			var flip := bool(w["flip"])
			_walker.region_rect = Rect2(int(w["frame"]) * size.x, 0, size.x, size.y)
			_walker.flip_h = flip
			var ax := (size.x - anchor.x) if flip else anchor.x
			_walker.position = Vector2(roundf(float(w["x"]) * _density) - ax, -anchor.y)
			_walker.modulate.a = float(w.get("alpha", 1.0))
			_walker.visible = true
			far = {"x": float(w["x"]), "frame": int(w["frame"]), "flip": flip}


## The warm light in the windows while you are inside (issue 476): the lit frame's own window pixels over the
## parked frame (only on a parked frame: the door and the drive move the windows), lit a little less than full by
## the light's tint, and a soft additive glow on each window that grows with how dark it is.
func _show_windows(frame: int, flip: bool) -> void:
	var show := interior > 0.0 and has_art() and visible and _window_frame(frame)
	if show and not _windows_ready:
		_build_windows()
	show = show and _windows.texture != null
	_windows.visible = show
	var s: Dictionary = tuning.get("shelter", {})
	var tint := _body.modulate
	if show:
		_windows.position = _body.position
		_windows.flip_h = flip
		var lit := tint.lerp(Color.WHITE, float(s.get("window_keep", 0.6)))
		_windows.modulate = Color(lit.r, lit.g, lit.b, interior)
	var fw := float(_van_meta.get("frame_w", 0))
	var strength := interior * (float(s.get("glow_day", 0.0)) + darkness * float(s.get("glow_dark", 0.0)))
	var colour := Color(String(s.get("glow_colour", "ffd890")))
	for i in maxi(_window_spots.size(), _window_glows.size()):
		if i >= _window_glows.size():
			var g := Sprite2D.new()
			g.texture = _glow_texture
			g.material = _additive()
			add_child(g)
			move_child(g, _walker.get_index())
			_window_glows.append(g)
		var sprite := _window_glows[i]
		if not show or i >= _window_spots.size() or strength <= 0.0:
			sprite.visible = false
			continue
		var spot: Dictionary = _window_spots[i]
		var at: Vector2 = spot["at"]
		sprite.position = _body.position + Vector2((fw - at.x) if flip else at.x, at.y)
		var r := float(spot["radius"]) * float(s.get("glow_scale", 1.6))
		sprite.scale = Vector2.ONE * (r / (float(_glow_texture.get_width()) * 0.5))
		sprite.modulate = Color(colour.r, colour.g, colour.b, strength)
		sprite.visible = true


## Whether `frame` is the parked frame (lit or not): the only frames the lit windows are cut from and match.
func _window_frame(frame: int) -> bool:
	var anims: Dictionary = _van_meta.get("animations", {})
	for anim in ["parked", "lights_on"]:
		if anims.has(anim) and int(anims[anim]["frames"][0]) == frame:
			return true
	return false


func _build_windows() -> void:
	_windows_ready = true
	var anims: Dictionary = _van_meta.get("animations", {})
	if not anims.has("parked") or not anims.has("lights_on") or _art == "" or not AssetLibrary.image_exists(_art):
		return
	var found := find_windows(_raw(), _van_meta, int(anims["lights_on"]["frames"][0]), int(anims["parked"]["frames"][0]),
			tuning.get("glow", {}), tuning.get("shelter", {}))
	_window_spots = found["spots"]
	_windows.texture = ImageTexture.create_from_image(found["image"]) if found["image"] != null else null


## The lit windows of the bench's van (issue 476): the warm pixels of the `lit` frame that differ from the unlit
## `dark` frame, above the lamps (`glow.lamp_min_y_share`). {"image" (one frame: those pixels, the rest clear; null
## when there are none), "spots" ([{"at" (frame px), "radius"}], one per window)}.
static func find_windows(sheet: Image, meta: Dictionary, lit: int, dark: int, glow: Dictionary, shelter: Dictionary) -> Dictionary:
	var fw := int(meta["frame_w"])
	var fh := int(meta["frame_h"])
	var max_y := float(fh) * float(glow.get("lamp_min_y_share", 0.55))
	var min_r := float(shelter.get("window_min_red", 0.85))
	var max_b := float(shelter.get("window_max_blue", 0.6))
	var image := Image.create_empty(fw, fh, false, Image.FORMAT_RGBA8)
	var warm := {}
	for y in fh:
		if float(y) >= max_y:
			break
		for x in fw:
			var a := sheet.get_pixel(lit * fw + x, y)
			if a.a <= 0.0 or a.r < min_r or a.b > max_b or a.is_equal_approx(sheet.get_pixel(dark * fw + x, y)):
				continue
			warm[Vector2i(x, y)] = a
	var spots: Array = []
	var seen := {}
	for p in warm:
		if seen.has(p):
			continue
		var blob: Array = [p]
		seen[p] = true
		var i := 0
		while i < blob.size():
			var q: Vector2i = blob[i]
			i += 1
			for n in [q + Vector2i.LEFT, q + Vector2i.RIGHT, q + Vector2i.UP, q + Vector2i.DOWN]:
				if warm.has(n) and not seen.has(n):
					seen[n] = true
					blob.append(n)
		if blob.size() < int(shelter.get("window_min_px", 8)):
			continue
		var lo := Vector2(blob[0])
		var hi := Vector2(blob[0])
		for q in blob:
			lo = lo.min(Vector2(q))
			hi = hi.max(Vector2(q))
			image.set_pixelv(q, warm[q])
		spots.append({"at": (lo + hi + Vector2.ONE) * 0.5, "radius": maxf(hi.x - lo.x, hi.y - lo.y) * 0.5 + 0.5})
	return {"image": image if not spots.is_empty() else null, "spots": spots}


## The glow round each lit lamp of `frame` and the pool ahead on the ground, scaled by `darkness` (none by day).
func _glow(frame: int, flip: bool) -> void:
	var g: Dictionary = tuning.get("glow", {})
	var lamps := lamps_of(frame) if lights else []
	var strength := darkness * float(g.get("strength", 0.0))
	var fw := float(_van_meta["frame_w"])
	var anchor := AssetLibrary.vec2i(_van_meta["anchor"])
	var radius := float(g.get("radius_px", 6.0))
	var tex_r := float(_glow_texture.get_width()) * 0.5
	var heads: Array = []
	for i in maxi(lamps.size(), _glows.size()):
		if i >= _glows.size():
			var s := Sprite2D.new()
			s.texture = _glow_texture
			s.material = _additive()
			add_child(s)
			_glows.append(s)
		var sprite := _glows[i]
		if i >= lamps.size() or strength <= 0.0:
			sprite.visible = false
			continue
		var lamp: Dictionary = lamps[i]
		var at: Vector2 = lamp["at"]
		var local := Vector2((fw - at.x) if flip else at.x, at.y)
		sprite.position = _body.position + local
		var r := radius * (1.0 if bool(lamp["head"]) else float(g.get("tail_share", 0.6)))
		sprite.scale = Vector2.ONE * (r / tex_r)
		var c: Color = lamp["colour"]
		sprite.modulate = Color(c.r, c.g, c.b, strength)
		sprite.visible = true
		if bool(lamp["head"]):
			heads.append(local)
	var pool_alpha := darkness * float(g.get("pool_strength", 0.0))
	_pool.visible = not heads.is_empty() and pool_alpha > 0.0
	if not _pool.visible:
		return
	var mean := Vector2.ZERO
	for h in heads:
		mean += h
	mean /= float(heads.size())
	var ground := _body.position.y + float(anchor.y)
	var dx := mean.x - float(fw - anchor.x if flip else anchor.x)
	var pool: Array = g.get("pool_px", [40, 6])
	var ahead := float(g.get("pool_ahead_px", 14.0))
	if absf(dx) < float(g.get("front_px", 10.0)):
		_pool.position = Vector2(_body.position.x + mean.x, ground + float(g.get("pool_front_dy_px", 4.0)))
		_pool.scale = Vector2(float(pool[1]) * 3.0, float(pool[1])) / tex_r
	else:
		_pool.position = Vector2(_body.position.x + mean.x + signf(dx) * ahead, ground)
		_pool.scale = Vector2(float(pool[0]), float(pool[1])) / tex_r
	_pool.modulate = Color(Color(String(g.get("pool_colour", "ffe6a8"))), pool_alpha)


## The lit lamps of `frame`, found in the bench's own frames: the pixels that differ from its unlit twin, in blobs
## low on the body (the lit windows above are left out). [{"at" (frame px), "colour", "head"}], [] for a dark frame.
func lamps_of(frame: int) -> Array:
	if _lamps.has(frame):
		return _lamps[frame]
	if _twins.is_empty():
		_twins = lit_twins(_van_meta)
	var out: Array = []
	if _twins.has(frame) and _art != "" and AssetLibrary.image_exists(_art):
		out = find_lamps(_raw(), _van_meta, frame, int(_twins[frame]), tuning.get("glow", {}))
	_lamps[frame] = out
	return out




func _raw() -> Image:
	if not _raw_cache.has(_art):
		var image := AssetLibrary.load_image(_art)
		if image.is_compressed():
			image.decompress()
		image.convert(Image.FORMAT_RGBA8)
		_raw_cache[_art] = image
	return _raw_cache[_art]


## Lit frame -> its unlit twin, from the sheet's animations (`X_lit` beside `X`, `lights_on` beside `parked`).
static func lit_twins(meta: Dictionary) -> Dictionary:
	var out := {}
	var anims: Dictionary = meta.get("animations", {})
	for anim in anims:
		var name_lit := String(anim)
		var base := "parked" if name_lit == "lights_on" else (name_lit.trim_suffix("_lit") if name_lit.ends_with("_lit") else "")
		if base == "" or not anims.has(base):
			continue
		var lit: Array = anims[name_lit]["frames"]
		var dark: Array = anims[base]["frames"]
		for i in mini(lit.size(), dark.size()):
			if int(lit[i]) != int(dark[i]):
				out[int(lit[i])] = int(dark[i])
	return out


static func find_lamps(sheet: Image, meta: Dictionary, lit: int, dark: int, g: Dictionary) -> Array:
	var fw := int(meta["frame_w"])
	var fh := int(meta["frame_h"])
	var min_y := float(fh) * float(g.get("lamp_min_y_share", 0.55))
	var changed := {}
	for y in fh:
		for x in fw:
			var a := sheet.get_pixel(lit * fw + x, y)
			if a.a > 0.0 and not a.is_equal_approx(sheet.get_pixel(dark * fw + x, y)):
				changed[Vector2i(x, y)] = a
	var out: Array = []
	var seen := {}
	for p in changed:
		if seen.has(p):
			continue
		var blob: Array = [p]
		seen[p] = true
		var i := 0
		while i < blob.size():
			var q: Vector2i = blob[i]
			i += 1
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var n := q + Vector2i(dx, dy)
					if changed.has(n) and not seen.has(n):
						seen[n] = true
						blob.append(n)
		var sum := Vector2.ZERO
		var col := Color(0, 0, 0, 0)
		for q in blob:
			sum += Vector2(q) + Vector2(0.5, 0.5)
			col += changed[q]
		var at := sum / float(blob.size())
		col /= float(blob.size())
		if at.y < min_y or blob.size() > int(g.get("lamp_max_px", 24)):
			continue
		# A lamp is bright (a headlamp) or a strong red (a tail lamp); the dull warm spill by the wheels is neither.
		if maxf(col.r, maxf(col.g, col.b)) < float(g.get("head_min_value", 0.8)) and col.s < float(g.get("tail_min_saturation", 0.55)):
			continue
		var head := col.g > 0.55 * col.r
		out.append({"at": at, "colour": Color(col.r, col.g, col.b).lightened(0.3), "head": head})
	return out


static func _radial() -> Texture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.35, Color(1, 1, 1, 0.35))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


static func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## Whether the van's lamps are due at `minute` of the day: from `lamps.from` until `lamps.until`, each
## [phase, minutes after its start] in the player's day phases, across midnight.
static func lamps_due(lamps: Dictionary, phases: DayPhases, minute: float) -> bool:
	var from := float(phases.start_of(String(lamps["from"][0])) + int(lamps["from"][1]))
	var until := float(phases.start_of(String(lamps["until"][0])) + int(lamps["until"][1]))
	return fposmod(minute - from, 1440.0) < fposmod(until - from, 1440.0)


## The route's numbers in points and points per second, from the tuning, the van's meta and the look's `day`.
static func config(day_tuning: Dictionary, van_meta: Dictionary, day: Dictionary, feet: Vector2, density: float) -> Dictionary:
	var van: Dictionary = day_tuning["van"]
	var route: Dictionary = day_tuning["route"]
	var far_ppm := float(van.get("px_per_m", 24.0)) / density
	var near_ppm := float(day.get("px_per_m", 180.0)) / density
	# It parks facing left (issue 279), the sheet flipped: the door, drawn facing right, is the other side of the
	# anchor, on the side facing the viewer.
	var door_dx := 0.0
	if van_meta.has("door"):
		door_dx = -(float(van_meta["door"][0]) - float(van_meta["anchor"][0])) / density
	var turn: Dictionary = van.get("turn", {})
	var walk := float(route["walk_m_per_sec"])
	var walks := not day.is_empty() and day.has("animations") and feet != Vector2.ZERO
	return {
		"walks": walks, "day": day, "van": van_meta, "feet": feet,
		"from_x": float(van["from_x_pt"]), "park_x": float(van["park_x_pt"]), "to_x": float(van["to_x_pt"]),
		"door_x": float(van["park_x_pt"]) + door_dx,
		"cruise": float(van["cruise_m_per_sec"]) * far_ppm, "brake": float(van["brake_m"]) * far_ppm,
		"pull": float(van["pull_away_m"]) * far_ppm, "wheel": float(van["wheel_m_per_cycle"]) * far_ppm,
		"far_walk": walk * far_ppm, "near_walk": walk * near_ppm,
		"far_stride": walk / float(day.get("animations", {}).get("day_walk", {}).get("fps", 10.0)) * far_ppm,
		"near_stride": walk / float(day.get("animations", {}).get("day_walk", {}).get("fps", 10.0)) * near_ppm,
		"lane_y": float(route["lane_y_pt"]), "hide_x": float(route["far_hide_x_pt"]),
		"near_from_x": float(route["near_from_x_pt"]), "hidden_sec": float(route["hidden_sec"]),
		"idle_sec": float(route["idle_sec"]),
		"close_after": float(route["door_close_after_sec"]), "open_before": float(route["door_open_before_sec"]),
		"fade_sec": float(day_tuning["fade_sec"]),
		"turn_forward": float(turn.get("forward_m", 1.0)) * far_ppm, "turn_reverse": float(turn.get("reverse_m", 0.5)) * far_ppm,
		"turn_out": float(turn.get("out_m", 0.5)) * far_ppm, "turn_toward": float(turn.get("toward_viewer_m", 0.0)) * far_ppm,
		"turn_hold": float(turn.get("hold_sec", 1.0)), "turn_stop": float(turn.get("stop_sec", 0.3)),
		"turn_split": int(turn.get("reverse_frames", 5)),
		"turn_reverse_sec": float(turn.get("reverse_sec", 0.0)), "turn_out_sec": float(turn.get("out_sec", 0.0)),
		"settle_px": int(van.get("settle_px", 1)), "settle_sec": float(van.get("settle_sec", 0.15)),
	}


## A whole route as two tracks of timed segments: {"kind", "van": [...], "who": [...], "end", "holds", "drive_at"}.
## kinds: "arrive", "leave" (from the log), "leave_standing" (after the wrap-up), "invite", "stay", and for the rain
## (issue 476) "shelter" (from the log into the parked van), "unshelter" (out of it back to the log) and
## "leave_sheltered" (it drives off with you inside). `lit`: the lamps are on (the wrap-up), and every van frame of
## the plan is its lit twin (`*_lit`, `lights_on`).
static func plan(cfg: Dictionary, kind: String, lit: bool = false) -> Dictionary:
	var van: Array = []
	var who: Array = []
	var out := {"kind": kind, "van": van, "who": who, "holds": false, "cfg": cfg, "lit": lit}
	var walks := bool(cfg["walks"])
	var park := float(cfg["park_x"])
	match kind:
		"arrive", "unshelter":
			var t := 0.0
			if kind == "arrive":
				t = _drive_in(cfg, van)
				t = _seg(van, t, float(cfg["idle_sec"]), {"kind": "anim", "anim": "idle", "x": park, "settle": true})
			if not walks:
				_seg(van, t, -1.0, {"kind": "anim", "anim": "parked", "x": park})
				if t > 0.0:
					_seg(who, 0.0, t, {"kind": "none"})
				out["out_at"] = t
				out["end"] = _seg(who, t, float(cfg["fade_sec"]), {"kind": "seat", "a0": 0.0, "a1": 1.0})
				return out
			t = _seg(van, t, _anim_sec(cfg["van"], "door_open"), {"kind": "anim", "anim": "door_open", "x": park})
			_seg(who, 0.0, t, {"kind": "none"})
			# Down off the step as soon as the door is open, turned to the walk left along the bank.
			var w := _seg(who, t, _anim_sec(cfg["day"], "day_step_out"),
					{"kind": "far", "anim": "day_step_out", "x0": cfg["door_x"], "x1": cfg["door_x"], "flip": true})
			var close_at := w + float(cfg["close_after"])
			_seg(van, t, close_at - t, {"kind": "anim", "anim": "door_open_hold", "x": park})
			t = _seg(van, close_at, _anim_sec(cfg["van"], "door_close"), {"kind": "anim", "anim": "door_close", "x": park})
			_seg(van, t, -1.0, {"kind": "anim", "anim": "parked", "x": park})
			# Out of the van, standing at its door: where the first run waits for the welcome (issue 199).
			out["out_at"] = w
			w = _walk(cfg, who, w, "far", float(cfg["door_x"]), float(cfg["hide_x"]))
			w = _seg(who, w, float(cfg["hidden_sec"]), {"kind": "none"})
			var feet: Vector2 = cfg["feet"]
			w = _walk(cfg, who, w, "near", float(cfg["near_from_x"]), feet.x)
			w = _act(cfg, who, w, "day_turn", false, true)
			w = _act(cfg, who, w, "day_unpack", false)
			w = _act(cfg, who, w, "day_sit_down", false)
			_seg(who, w, -1.0, {"kind": "seat", "a0": 1.0, "a1": 1.0})
			out["end"] = w
		"shelter":
			if not walks:
				var f := _seg(who, 0.0, float(cfg["fade_sec"]), {"kind": "seat", "a0": 1.0, "a1": 0.0})
				_seg(who, f, -1.0, {"kind": "none"})
				_seg(van, 0.0, -1.0, {"kind": "anim", "anim": "parked", "x": park})
				out["in_at"] = f
				out["end"] = f
				return out
			# The evening's walk to the van without the stretch (the human, issue 476), at `cfg`'s pace (`hurried`).
			var w := _act(cfg, who, 0.0, "day_stand_up", false)
			w = _act(cfg, who, w, "day_pack", false)
			w = _act(cfg, who, w, "day_turn_left", false)
			var t := _to_the_door(cfg, van, who, w)
			out["in_at"] = float(who[-1]["t0"])
			_seg(van, t, -1.0, {"kind": "anim", "anim": "parked", "x": park})
			out["end"] = t
		"leave_sheltered":
			_seg(who, 0.0, -1.0, {"kind": "none"})
			var t := _seg(van, 0.0, float(cfg["idle_sec"]), {"kind": "anim", "anim": "idle", "x": park})
			out["drive_at"] = 0.0
			out["end"] = _turn_out(cfg, van, t)
		"leave", "leave_standing":
			var w := 0.0
			if not walks:
				w = _seg(who, 0.0, float(cfg["fade_sec"]), {"kind": "seat", "a0": 1.0, "a1": 0.0})
				_seg(who, w, -1.0, {"kind": "none"})
				var t := _seg(van, 0.0, w, {"kind": "anim", "anim": "parked", "x": park})
				t = _seg(van, t, float(cfg["idle_sec"]), {"kind": "anim", "anim": "idle", "x": park})
				out["drive_at"] = t
				out["end"] = _turn_out(cfg, van, t)
				return out
			if kind == "leave":
				w = _act(cfg, who, w, "day_stand_up", false)
				w = _act(cfg, who, w, "day_pack", false)
			w = _act(cfg, who, w, "day_turn_left", false)
			var t := _to_the_door(cfg, van, who, w)
			t = _seg(van, t, float(cfg["idle_sec"]), {"kind": "anim", "anim": "idle", "x": park})
			out["drive_at"] = t
			out["end"] = _turn_out(cfg, van, t)
		"invite":
			_seg(van, 0.0, -1.0, {"kind": "anim", "anim": "parked", "x": park})
			if not walks:
				_seg(who, 0.0, -1.0, {"kind": "seat", "a0": 1.0, "a1": 1.0})
				out["end"] = 0.0
				return out
			var w := _act(cfg, who, 0.0, "day_stand_up", false)
			w = _act(cfg, who, w, "day_stretch", false)
			w = _act(cfg, who, w, "day_pack", false)
			_seg(who, w, -1.0, _held(cfg, "day_pack", false))
			out["end"] = w
			out["holds"] = true
		"stay":
			_seg(van, 0.0, -1.0, {"kind": "anim", "anim": "parked", "x": park})
			var w := _act(cfg, who, 0.0, "day_unpack", false)
			w = _act(cfg, who, w, "day_sit_down", false)
			_seg(who, w, -1.0, {"kind": "seat", "a0": 1.0, "a1": 1.0})
			out["end"] = w
	return out


## From the log (turned to walk left, at `w`) to the van and up into it: near the log out of the scene's left edge,
## out of sight, along the far bank to the door and up its step; the van opens its door to meet you and closes it.
## Returns when the door is shut (the van's track ends there, you are `none` from inside).
static func _to_the_door(cfg: Dictionary, van: Array, who: Array, w: float) -> float:
	var park := float(cfg["park_x"])
	var feet: Vector2 = cfg["feet"]
	w = _walk(cfg, who, w, "near", feet.x, float(cfg["near_from_x"]))
	w = _seg(who, w, float(cfg["hidden_sec"]), {"kind": "none"})
	w = _walk(cfg, who, w, "far", float(cfg["hide_x"]), float(cfg["door_x"]))
	var open_at := maxf(0.0, w - float(cfg["open_before"]) - _anim_sec(cfg["van"], "door_open"))
	w = _seg(who, w, _anim_sec(cfg["day"], "day_step_in") / float(cfg.get("rate", 1.0)),
			{"kind": "far", "anim": "day_step_in", "x0": cfg["door_x"], "x1": cfg["door_x"], "flip": false, "rate": float(cfg.get("rate", 1.0))})
	_seg(who, w, -1.0, {"kind": "none"})
	var t := _seg(van, 0.0, open_at, {"kind": "anim", "anim": "parked", "x": park})
	t = _seg(van, t, _anim_sec(cfg["van"], "door_open"), {"kind": "anim", "anim": "door_open", "x": park})
	t = _seg(van, t, maxf(0.0, w - t), {"kind": "anim", "anim": "door_open_hold", "x": park})
	return _seg(van, t, _anim_sec(cfg["van"], "door_close"), {"kind": "anim", "anim": "door_close", "x": park})


## Where everything is at `t` seconds into `p`: {"van": {"x", "frame"}, "who": {"kind", "x", "frame", "flip", "alpha"}}.
## kind is "none", "seat" (on the log, `alpha`), "far" or "near"; frames index the van's and the day sheets.
static func pose_at(p: Dictionary, t: float) -> Dictionary:
	var vs := _at(p["van"], t)
	var ws := _at(p["who"], t)
	return {"van": _van_pose(p, vs, t), "who": _who_pose(p, ws, t)}


static func _at(track: Array, t: float) -> Dictionary:
	var found: Dictionary = track[0]
	for s in track:
		if float(s["t0"]) <= t:
			found = s
	return found


static func _van_pose(p: Dictionary, s: Dictionary, t: float) -> Dictionary:
	var meta: Dictionary = p["cfg"]["van"]
	var lt := clampf(t - float(s["t0"]), 0.0, float(s["sec"]) if float(s["sec"]) >= 0.0 else INF)
	var cfg: Dictionary = p["cfg"]
	var lit := bool(p.get("lit", false))
	var settle := int(cfg.get("settle_px", 0)) if bool(s.get("settle", false)) and lt < float(cfg.get("settle_sec", 0.0)) else 0
	match String(s["kind"]):
		"drive":
			var v0 := float(s["v0"])
			var a := float(s["a"])
			var dir := float(s.get("dir", 1.0))
			var d := v0 * lt + 0.5 * a * lt * lt
			var x := float(s["x0"]) + dir * d
			var travelled := float(s["d0"]) + d
			var drive := _lit(meta, String(s.get("anim", "drive_right")), lit)
			var frames: Array = meta.get("animations", {}).get(drive, {}).get("frames", [])
			var frame := -1
			if not frames.is_empty():
				var per := float(cfg["wheel"]) / frames.size()
				frame = int(frames[int(floor(travelled / per)) % frames.size()])
			return {"x": x, "y": 0.0, "frame": frame, "anim": drive, "speed": (v0 + a * lt) * dir, "flip": false, "dy": 0}
		"turn":
			var anim := _lit(meta, String(s["anim"]), lit)
			var frames: Array = meta["animations"][anim]["frames"]
			var sec := float(s["sec"])
			var k := clampf(lt / sec, 0.0, 1.0) if sec > 0.0 else 1.0
			# The views spread evenly over the step: the rotation keeps pace with the move.
			var n := int(s["to"]) - int(s["from"]) + 1
			var i := mini(int(s["from"]) + int(floor(k * n)), int(s["to"]))
			var e := k
			var de := 1.0
			match String(s.get("ease", "inout")):
				"inout":
					e = k * k * (3.0 - 2.0 * k)
					de = 6.0 * k * (1.0 - k)
				"in":
					e = k * k
					de = 2.0 * k
				"none":
					e = 0.0
					de = 0.0
			var dx := float(s["x1"]) - float(s["x0"])
			return {"x": float(s["x0"]) + dx * e, "y": lerpf(float(s["y0"]), float(s["y1"]), e), "frame": int(frames[i]),
					"anim": anim, "speed": dx * de / maxf(sec, 0.001), "flip": false, "dy": settle,
					"reverse": bool(s.get("reverse", false))}
	var anim := _lit(meta, String(s["anim"]), lit)
	var flip := bool(s.get("flip", true))
	if anim == "parked":
		return {"x": float(s["x"]), "y": 0.0, "frame": -1, "anim": anim, "speed": 0.0, "flip": flip, "dy": settle}
	return {"x": float(s["x"]), "y": 0.0, "frame": _frame_of(meta, anim, lt, false), "anim": anim, "speed": 0.0, "flip": flip, "dy": settle}


## The van's animation with its lamps lit when `lit` and the sheet has the twin ("parked" lit is `lights_on`).
static func _lit(meta: Dictionary, anim: String, lit: bool) -> String:
	if not lit:
		return anim
	var twin := "lights_on" if anim == "parked" else anim + "_lit"
	return twin if meta.get("animations", {}).has(twin) else anim


static func _who_pose(p: Dictionary, s: Dictionary, t: float) -> Dictionary:
	var kind := String(s["kind"])
	var sec := float(s["sec"])
	var lt := clampf(t - float(s["t0"]), 0.0, sec if sec >= 0.0 else INF)
	var k := clampf(lt / sec, 0.0, 1.0) if sec > 0.0 else 1.0
	var alpha := lerpf(float(s.get("a0", 1.0)), float(s.get("a1", 1.0)), k)
	match kind:
		"none":
			return {"kind": "none"}
		"seat":
			return {"kind": "seat", "alpha": alpha}
	var day: Dictionary = p["cfg"]["day"]
	var x0 := float(s["x0"])
	var x1 := float(s["x1"])
	var x := lerpf(x0, x1, k)
	var frame: int
	if String(s["anim"]) == "day_walk":
		var frames: Array = day["animations"]["day_walk"]["frames"]
		var stride := float(p["cfg"]["far_stride" if kind == "far" else "near_stride"])
		frame = int(frames[int(floor(absf(x - x0) / maxf(stride, 0.001))) % frames.size()])
	else:
		frame = _frame_of(day, String(s["anim"]), lt * float(s.get("rate", 1.0)), bool(s.get("reverse", false)))
	return {"kind": kind, "x": x, "frame": frame, "flip": bool(s["flip"]), "alpha": alpha, "anim": String(s["anim"])}


static func _frame_of(meta: Dictionary, anim: String, lt: float, reverse: bool) -> int:
	var a: Dictionary = meta["animations"][anim]
	var frames: Array = a["frames"].duplicate()
	if reverse:
		frames.reverse()
	var i := int(floor(lt * float(a.get("fps", 8.0))))
	if bool(a.get("loop", false)):
		return int(frames[i % frames.size()])
	return int(frames[mini(i, frames.size() - 1)])


static func _anim_sec(meta: Dictionary, anim: String) -> float:
	var a: Dictionary = meta.get("animations", {}).get(anim, {})
	if a.is_empty():
		return 0.0
	return float(a["frames"].size()) / maxf(float(a.get("fps", 8.0)), 0.01)


## Appends a segment starting at t0 lasting sec (-1: open-ended); returns its end.
static func _seg(track: Array, t0: float, sec: float, s: Dictionary) -> float:
	s["t0"] = t0
	s["sec"] = sec
	track.append(s)
	return t0 + maxf(sec, 0.0)


static func _walk(cfg: Dictionary, who: Array, t0: float, depth: String, x0: float, x1: float) -> float:
	var speed := float(cfg["far_walk" if depth == "far" else "near_walk"])
	return _seg(who, t0, absf(x1 - x0) / maxf(speed, 0.001),
			{"kind": depth, "anim": "day_walk", "x0": x0, "x1": x1, "flip": x1 < x0})


## A standing action at the log's feet point (`flip` mirrors it, for turning to walk left).
## Played `cfg.rate` times as fast when hurried (issue 476).
static func _act(cfg: Dictionary, who: Array, t0: float, anim: String, flip: bool, reverse: bool = false) -> float:
	var feet: Vector2 = cfg["feet"]
	var rate := float(cfg.get("rate", 1.0))
	return _seg(who, t0, _anim_sec(cfg["day"], anim) / rate,
			{"kind": "near", "anim": anim, "x0": feet.x, "x1": feet.x, "flip": flip, "reverse": reverse, "rate": rate})


static func _held(cfg: Dictionary, anim: String, flip: bool) -> Dictionary:
	var feet: Vector2 = cfg["feet"]
	return {"kind": "near", "anim": anim, "x0": feet.x, "x1": feet.x, "flip": flip}


## The van comes along the far bank from the right (issue 279), facing left at a cruise (`drive_left`: its wheels
## roll forward as it goes left), and brakes evenly to stop at the park.
static func _drive_in(cfg: Dictionary, van: Array) -> float:
	var from := float(cfg["from_x"])
	var park := float(cfg["park_x"])
	var dir := signf(park - from) if park != from else -1.0
	var anim := "drive_left" if dir < 0.0 else "drive_right"
	var v := float(cfg["cruise"])
	var run := absf(park - from)
	var brake := minf(float(cfg["brake"]), run)
	var brake_at := from + dir * (run - brake)
	var t := _seg(van, 0.0, (run - brake) / v, {"kind": "drive", "anim": anim, "dir": dir, "x0": from, "v0": v, "a": 0.0, "d0": 0.0})
	var sec := 2.0 * brake / v
	return _seg(van, t, sec, {"kind": "drive", "anim": anim, "dir": dir, "x0": brake_at, "v0": v, "a": -v / maxf(sec, 0.001), "d0": run - brake})


## The evening turn (issue 279, the human: a real three-point turn, rotating the same way throughout): forward,
## steering toward the viewer, the nose swinging from facing left to front-on (`turn_reverse`'s views); a stop, the
## lamps on the viewer for `hold_sec`; reverse, steering the other way, the rotation going on to three-quarter
## front-right (`turn_forward`'s first `reverse_frames` views); a stop; forward out of the turn (the rest of
## `turn_forward`, ending side-on facing right), pulling away into `drive_right` and on out of sight behind the
## oak. Each stop settles the body by `settle_px`. The views carry the rotation (never flipped); the anchor moves
## along the bank (and a little toward the viewer and back) with the views.
static func _turn_out(cfg: Dictionary, van: Array, t0: float) -> float:
	var meta: Dictionary = cfg["van"]
	var park := float(cfg["park_x"])
	var to := float(cfg["to_x"])
	var anims: Dictionary = meta.get("animations", {})
	if not anims.has("turn_reverse") or not anims.has("turn_forward"):
		return _drive_out(cfg, van, t0, park, 0.0)
	var first: Array = anims["turn_reverse"]["frames"]
	var second: Array = anims["turn_forward"]["frames"]
	var fps1 := float(anims["turn_reverse"].get("fps", 8.0))
	var fps2 := float(anims["turn_forward"].get("fps", 8.0))
	var split := clampi(int(cfg["turn_split"]), 1, second.size() - 2)
	var toward := float(cfg["turn_toward"])
	var x := park
	# 1. Forward toward the viewer: from side-on facing left to front-on.
	var sec := float(first.size()) / fps1
	var x1 := x - float(cfg["turn_forward"])
	var t := _seg(van, t0, sec, {"kind": "turn", "anim": "turn_reverse", "from": 0, "to": first.size() - 1,
			"x0": x, "x1": x1, "y0": 0.0, "y1": toward, "ease": "inout"})
	x = x1
	# 2. Stopped, the lamps on the viewer.
	t = _seg(van, t, float(cfg["turn_hold"]), {"kind": "turn", "anim": "turn_reverse", "from": first.size() - 1,
			"to": first.size() - 1, "x0": x, "x1": x, "y0": toward, "y1": toward, "ease": "none", "settle": true})
	# 3. Reverse, steering the other way: on round to three-quarter front-right, backing toward the trees.
	sec = maxf(float(split) / fps2, float(cfg["turn_reverse_sec"]))
	x1 = x - float(cfg["turn_reverse"])
	t = _seg(van, t, sec, {"kind": "turn", "anim": "turn_forward", "from": 1, "to": split,
			"x0": x, "x1": x1, "y0": toward, "y1": 0.0, "ease": "inout", "reverse": true})
	x = x1
	# 4. Stopped.
	t = _seg(van, t, float(cfg["turn_stop"]), {"kind": "turn", "anim": "turn_forward", "from": split, "to": split,
			"x0": x, "x1": x, "y0": 0.0, "y1": 0.0, "ease": "none", "settle": true})
	# 5. Forward out of the turn to the right, from rest.
	sec = maxf(float(second.size() - 1 - split) / fps2, float(cfg["turn_out_sec"]))
	x1 = x + float(cfg["turn_out"])
	t = _seg(van, t, sec, {"kind": "turn", "anim": "turn_forward", "from": split + 1, "to": second.size() - 1,
			"x0": x, "x1": x1, "y0": 0.0, "y1": 0.0, "ease": "in"})
	return _drive_out(cfg, van, t, x1, 2.0 * (x1 - x) / maxf(sec, 0.001))


## It pulls away evenly (from `v0`) to a cruise, facing right, then on out of sight; then it stays at the road's
## end (away).
static func _drive_out(cfg: Dictionary, van: Array, t0: float, from: float, v0: float) -> float:
	var to := float(cfg["to_x"])
	var v := float(cfg["cruise"])
	v0 = minf(v0, v)
	var pull := minf(float(cfg["pull"]), to - from)
	var sec := 2.0 * pull / (v + v0)
	var t := _seg(van, t0, sec, {"kind": "drive", "anim": "drive_right", "dir": 1.0, "x0": from, "v0": v0,
			"a": (v - v0) / maxf(sec, 0.001), "d0": 0.0})
	t = _seg(van, t, (to - from - pull) / v, {"kind": "drive", "anim": "drive_right", "dir": 1.0, "x0": from + pull,
			"v0": v, "a": 0.0, "d0": pull})
	_seg(van, t, -1.0, {"kind": "anim", "anim": "parked", "x": to, "flip": false})
	return t
