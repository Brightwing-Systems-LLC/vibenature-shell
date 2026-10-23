class_name Avatar
extends Node

## The player's character. It lives at home on the bench, vanishes in a puff of smoke and
## reappears on the island the player clicks, walks along the island's front band, and
## does the job of the tool in hand. Per-frame work only while it walks.
##
## The art is one of six avatars (`<build>_<preset>`, the companion's `avatar/<id>/`), each with
## three views as layers: `front`, `side` (facing east; mirrored for west) and `back`. The
## mechanics only say what the avatar is doing (`show_doing`); `view_for` alone decides
## which view that shows.
##
## On an illustrated island it also draws at the depth where its feet are (`IslandPack.layer_at`):
## the full-size sheets in front, the bench's smaller `@mid` and `@back` sheets further back
## (meta `depths`), swapped as it walks; never a scaled sprite. An avatar without a depth's
## sheets does not walk into that depth: its walk is clamped to the depths it has.

signal arrived

## What the avatar can be doing, and the view each one shows.
const SIDE_DOINGS: Array[String] = ["walk", "cast", "cast_charge", "wait", "reel", "camera", "camera_hold", "throw"]
const PLACEHOLDER_SKIN := Color("f5a097")
const PLACEHOLDER_LEGS := Color("3e3546")
const PLACEHOLDER_ROD := Color("4c3e24")
## Per preset: hair, top, and whether the hair is long.
const PLACEHOLDER_PRESETS := {
	"p1": {"hair": Color("6e4c30"), "top": Color("4d9be6"), "long_hair": false},
	"p2": {"hair": Color("45293f"), "top": Color("b33831"), "long_hair": true},
}

var game: Game
var def: CreatureDef
var sprite: CreatureSprite
var avatar_id := ""
## The island it is on, or null at home.
var patch: PatchWindow
var tool_id := ""
var busy := false
## What it is doing (`sit`, `idle`, `walk`, a tool's action, `cast`, `wait`, `reel`).
var doing := "sit"
## Idle facing into the island (its back to the player), when a mechanic says so.
var facing_in := false
var facing_west := false
## The depth it is drawn at (`front`, `mid`, `back`): front at home and on shelf islands.
var depth := "front"
var _pos := Vector2.ZERO
var _target := Vector2.ZERO
var _speed := 40.0
var _poof_def: CreatureDef


func setup(owner_game: Game) -> void:
	game = owner_game
	var ids := Avatar.choices(game.balance.data["placeholders"])
	use_def(Avatar.load_def(Avatar.resolve_id(String(game.settings.data["avatar_id"]), ids),
			game.balance.data["placeholders"], game.idle_fps_max))
	_poof_def = CreatureDef.load_single("fx", "poof", game.idle_fps_max, CreatureDef.sheet_layer(
			Vector2i(24, 24), 4, Color("c7dcd0"), {"poof": {"frames": [0, 1, 2, 3], "fps": 12.0, "loop": false}},
			Vector2i(12, 20)))


func _ready() -> void:
	set_process(false)


## Swaps in another avatar's art where this one stands, doing the same thing.
func use_def(new_def: CreatureDef) -> void:
	def = new_def
	avatar_id = def.id
	var parent: Node2D = null
	if sprite != null:
		parent = sprite.get_parent() as Node2D
		if parent != null:
			sprite.mark_changed()
			parent.remove_child(sprite)
		sprite.queue_free()
	sprite = CreatureSprite.new(def)
	sprite.finished.connect(_on_animation_finished)
	sprite.position = _pos
	depth = "front"
	if parent != null:
		parent.add_child(sprite)
	show_doing(doing, facing_in)
	_update_depth()


## The avatars Config offers: every avatar delivered in `root`, or, until one
## is, the six placeholder avatars.
static func choices(placeholders: Dictionary, root: String = AssetLibrary.avatar_root()) -> Array[String]:
	var ids: Array[String] = []
	var dir := "%s/avatar" % root
	if DirAccess.dir_exists_absolute(dir):
		for id in DirAccess.get_directories_at(dir):
			if AssetLibrary.load_meta("avatar", id, root).has("layers"):
				ids.append(id)
	if ids.is_empty():
		for build in placeholders["avatar_build_widths"]:
			for preset in placeholders["avatar_presets"]:
				ids.append("%s_%s" % [build, preset])
	ids.sort()
	return ids


## `wanted` if it is one of `ids`, else the first of them.
static func resolve_id(wanted: String, ids: Array[String]) -> String:
	if ids.has(wanted) or ids.is_empty():
		return wanted
	return ids[0]


## The id after `current` in `ids`, wrapping round.
static func next_id(current: String, ids: Array[String]) -> String:
	if ids.is_empty():
		return current
	return ids[(ids.find(current) + 1) % ids.size()]


## The delivered avatar `id`, or a placeholder in the same format (three views, every
## animation) sized from `placeholders`.
static func load_def(id: String, placeholders: Dictionary, idle_fps_max: float, root: String = AssetLibrary.avatar_root()) -> CreatureDef:
	var def := CreatureDef.load_creature("avatar", id, {}, idle_fps_max, Color.WHITE, root)
	if not def.layers.is_empty():
		var meta := AssetLibrary.load_meta("avatar", id, root)
		def.rod_tips = meta.get("rod_tips", {})
		def.depths = Avatar.load_depths(def, meta, root)
		return def
	var figure := AssetLibrary.vec2i(placeholders["avatar_figure"])
	var parts := id.rsplit("_", true, 1)
	var widths: Dictionary = placeholders["avatar_build_widths"]
	if parts.size() == 2 and widths.has(parts[0]):
		figure.x = int(widths[parts[0]])
	var preset := String(parts[1]) if parts.size() == 2 and PLACEHOLDER_PRESETS.has(parts[1]) else "p1"
	def.is_placeholder = true
	def.layers = Avatar.placeholder_layers(AssetLibrary.vec2i(placeholders["avatar_frame"]), figure, preset)
	return def


## The avatar's sheets at each further depth its meta's `depths` gives (`mid`, `back`): per
## depth, `<id>_<view>@<depth>.png` for every view `front_def` has, with the depth's `frame`
## and `anchor` and the full-size sheet's animations (same frame order and counts). A depth
## missing any view's sheet is left out, so the avatar stays out of it.
static func load_depths(front_def: CreatureDef, meta: Dictionary, root: String = AssetLibrary.avatar_root()) -> Dictionary:
	var out := {}
	var depths: Dictionary = meta.get("depths", {})
	for depth_name in ["mid", "back"]:
		if not depths.has(depth_name):
			continue
		var dm: Dictionary = depths[depth_name]
		var frame := AssetLibrary.vec2i(dm["frame"])
		var at_depth := CreatureDef.new()
		at_depth.id = front_def.id
		at_depth.rod_tips = dm.get("rod_tips", {})
		for view in front_def.layers:
			var texture := AssetLibrary.load_texture("avatar", front_def.id, "%s_%s@%s" % [front_def.id, view, depth_name], root)
			if texture == null or frame.x <= 0 or frame.y <= 0:
				push_warning("VibeNature: avatar %s has no %s sheet for its %s view; it stays out of that depth" % [front_def.id, depth_name, view])
				at_depth.layers.clear()
				break
			at_depth.layers[view] = {
				"texture": texture,
				"frame_size": frame,
				"anchor": AssetLibrary.vec2i(dm["anchor"]),
				"columns": maxi(1, texture.get_width() / frame.x),
				"animations": front_def.layers[view]["animations"],
			}
		if not at_depth.layers.is_empty():
			out[depth_name] = at_depth
	return out


## The view that shows `what_doing`: side while walking or with the rod, back when idle
## facing into the island, front otherwise (sitting, idle, other tools).
static func view_for(what_doing: String, into_island: bool = false) -> String:
	if SIDE_DOINGS.has(what_doing):
		return "side"
	if what_doing == "idle" and into_island:
		return "back"
	return "front"


## Shows the avatar doing `what_doing` in the view `view_for` picks. `cast` plays once,
## then the avatar waits with the rod (`wait` loops). A tool action the art lacks
## plays `act`, else idle.
func show_doing(what_doing: String, into_island: bool = false) -> void:
	if what_doing == "nap":
		_show_nap()
		return
	var view := Avatar.view_for(what_doing, into_island)
	if not def.has_layer(view):
		view = "front" if def.has_layer("front") else String(def.layers.keys()[0])
	if what_doing == doing and into_island == facing_in and sprite.layer == view and sprite.anim != "" \
			and SIDE_DOINGS.has(what_doing) and what_doing != "cast":
		# Already looping it (a fishing refresh): don't restart the animation.
		return
	doing = what_doing
	facing_in = into_island
	sprite.set_layer(view)
	sprite.flip_h = view == "side" and facing_west
	var anim := doing
	if not def.has_animation(view, anim) and not SIDE_DOINGS.has(anim) and anim not in ["sit", "idle"]:
		anim = "act"
	if doing == "cast" and not def.has_animation(view, "cast"):
		show_doing("wait")
		return
	sprite.play(anim)


## Napping: the art's own `nap` (any view that has it) when the bench delivers one
## (asset avatar_nap), else sitting (`sit`, front).
func _show_nap() -> void:
	doing = "nap"
	facing_in = false
	var view := "front" if def.has_layer("front") else String(def.layers.keys()[0])
	for layer in def.layers:
		if def.has_animation(layer, "nap"):
			view = layer
	sprite.set_layer(view)
	sprite.flip_h = false
	sprite.play("nap" if def.has_animation(view, "nap") else "sit")


func _on_animation_finished() -> void:
	if doing == "cast":
		show_doing("wait")


## Faces east or west toward `point` (art pixels), for the side view.
func face(point: Vector2) -> void:
	if point.x != _pos.x:
		facing_west = point.x < _pos.x
		sprite.flip_h = sprite.layer == "side" and facing_west


## A placeholder until the bench's avatar lands, in its delivery format: `front` (idle,
## sit, act), `side` facing east (idle, walk, cast, wait, reel) and `back` (idle), each a
## row of `frame`-sized frames with the figure's feet at the bottom centre.
static func placeholder_layers(frame: Vector2i, figure: Vector2i, preset: String = "p1") -> Dictionary:
	var look: Dictionary = PLACEHOLDER_PRESETS.get(preset, PLACEHOLDER_PRESETS["p1"])
	var anchor := Vector2i(frame.x / 2, frame.y - 3)
	var front := ["idle", "breathe", "sit", "act"]
	var side := ["stand", "step_a", "step_b", "cast", "wait", "wait_low", "reel_a", "reel_b"]
	var back := ["idle", "breathe"]
	return {
		"front": _placeholder_sheet(frame, figure, anchor, look, "front", front, {
			"idle": {"frames": [0, 1], "fps": 2.0, "loop": true},
			"sit": {"frames": [2], "fps": 1.0, "loop": true},
			"act": {"frames": [3, 0], "fps": 4.0, "loop": true},
		}),
		"side": _placeholder_sheet(frame, figure, anchor, look, "side", side, {
			"idle": {"frames": [0], "fps": 1.0, "loop": true},
			"walk": {"frames": [1, 2], "fps": 6.0, "loop": true},
			"cast": {"frames": [3, 4], "fps": 3.0, "loop": false},
			"wait": {"frames": [4, 5], "fps": 2.0, "loop": true},
			"reel": {"frames": [6, 7], "fps": 4.0, "loop": true},
		}),
		"back": _placeholder_sheet(frame, figure, anchor, look, "back", back, {
			"idle": {"frames": [0, 1], "fps": 2.0, "loop": true},
		}),
	}


static func _placeholder_sheet(frame: Vector2i, figure: Vector2i, anchor: Vector2i, look: Dictionary, view: String,
		poses: Array, animations: Dictionary) -> Dictionary:
	var image := Image.create_empty(frame.x * poses.size(), frame.y, false, Image.FORMAT_RGBA8)
	for i in poses.size():
		_placeholder_pose(image, Vector2i(i * frame.x + anchor.x, anchor.y), figure, look, view, String(poses[i]))
	return {
		"texture": ImageTexture.create_from_image(image),
		"frame_size": frame,
		"anchor": anchor,
		"columns": poses.size(),
		"animations": animations,
	}


## One figure with its feet at `feet`: blocks for head, hair, top, arms and legs, posed.
static func _placeholder_pose(image: Image, feet: Vector2i, figure: Vector2i, look: Dictionary, view: String, pose: String) -> void:
	var h := figure.y
	var w := figure.x if view != "side" else maxi(figure.x * 3 / 5, 16)
	var drop := 0
	if pose in ["breathe", "wait_low"]:
		drop = 1
	elif pose == "sit":
		drop = h * 3 / 10
	var top := feet.y - h + 1 + drop
	var head := mini(h / 6, w * 3 / 4)
	var cx := feet.x
	var hair: Color = look["hair"]
	var shirt: Color = look["top"]
	image.fill_rect(Rect2i(cx - head / 2, top, head, head), PLACEHOLDER_SKIN if view != "back" else hair)
	image.fill_rect(Rect2i(cx - head / 2, top, head, head / 3), hair)
	if view == "side":
		image.fill_rect(Rect2i(cx - head / 2, top, head / 3, head * 2 / 3), hair)
		image.fill_rect(Rect2i(cx + head / 2, top + head / 2, 2, 3), PLACEHOLDER_SKIN)
	var torso_top := top + head + 2
	var torso_h := h * 36 / 100
	if bool(look["long_hair"]):
		image.fill_rect(Rect2i(cx - head / 2 - 2, top, 3, head + 10), hair)
		image.fill_rect(Rect2i(cx + head / 2 - 1, top, 3, head + 10), hair)
		if view == "back":
			image.fill_rect(Rect2i(cx - head / 2, top + head, head, 10), hair)
	image.fill_rect(Rect2i(cx - head / 4, top + head, head / 2, 2), PLACEHOLDER_SKIN)
	image.fill_rect(Rect2i(cx - w / 2, torso_top, w, torso_h), shirt)
	if view == "back":
		image.fill_rect(Rect2i(cx - head / 2, top, head, head * 2 / 3), hair)
	var leg_top := torso_top + torso_h
	var leg_w := maxi(w / 4, 4)
	if pose == "sit":
		image.fill_rect(Rect2i(cx - w / 2, leg_top, w, maxi(feet.y - leg_top + 1, 2)), PLACEHOLDER_LEGS)
	elif view == "side":
		var stride := 0
		if pose == "step_a":
			stride = w / 3
		elif pose == "step_b":
			stride = -w / 3
		image.fill_rect(Rect2i(cx - leg_w / 2 + stride, leg_top, leg_w, feet.y - leg_top + 1), PLACEHOLDER_LEGS)
		image.fill_rect(Rect2i(cx - leg_w / 2 - stride, leg_top, leg_w, feet.y - leg_top + 1), PLACEHOLDER_LEGS.lightened(0.15))
	else:
		image.fill_rect(Rect2i(cx - w / 2 + 2, leg_top, leg_w, feet.y - leg_top + 1), PLACEHOLDER_LEGS)
		image.fill_rect(Rect2i(cx + w / 2 - 2 - leg_w, leg_top, leg_w, feet.y - leg_top + 1), PLACEHOLDER_LEGS)
	_placeholder_arms(image, cx, torso_top, torso_h, w, view, pose)


## Arms by pose, and the rod where the pose holds it: raised for `cast`, bent for `reel`.
static func _placeholder_arms(image: Image, cx: int, torso_top: int, torso_h: int, w: int, view: String, pose: String) -> void:
	var arm := maxi(w / 8, 3)
	var shade := PLACEHOLDER_SKIN.darkened(0.15)
	if view != "side":
		image.fill_rect(Rect2i(cx - w / 2 - arm, torso_top + 2, arm, torso_h - 4), shade)
		if pose == "act":
			image.fill_rect(Rect2i(cx + w / 2, torso_top + 4, w / 4, arm), shade)
		else:
			image.fill_rect(Rect2i(cx + w / 2, torso_top + 2, arm, torso_h - 4), shade)
		return
	var shoulder := Vector2i(cx, torso_top + 4)
	match pose:
		"cast":
			image.fill_rect(Rect2i(shoulder.x - arm, shoulder.y - torso_h / 2, arm, torso_h / 2 + 2), shade)
			_line(image, Vector2i(shoulder.x - arm / 2, shoulder.y - torso_h / 2), Vector2i(shoulder.x - w, maxi(shoulder.y - torso_h - 20, 0)), PLACEHOLDER_ROD)
		"wait", "wait_low":
			image.fill_rect(Rect2i(shoulder.x, shoulder.y + torso_h / 3, w * 2 / 3, arm), shade)
		"reel_a", "reel_b":
			var hand := Vector2i(shoulder.x + w / 3, shoulder.y + torso_h / 3)
			image.fill_rect(Rect2i(shoulder.x, hand.y, w / 3, arm), shade)
			var bend := 10 if pose == "reel_a" else 16
			var mid := hand + Vector2i(w / 2, -torso_h / 2)
			_line(image, hand, mid, PLACEHOLDER_ROD)
			_line(image, mid, mid + Vector2i(w / 3, bend), PLACEHOLDER_ROD)
		"step_a", "step_b":
			var swing := w / 4 if pose == "step_b" else -w / 4
			image.fill_rect(Rect2i(shoulder.x - arm / 2 + swing, shoulder.y, arm, torso_h - 6), shade)
		_:
			image.fill_rect(Rect2i(shoulder.x - arm / 2, shoulder.y, arm, torso_h - 6), shade)


static func _line(image: Image, from: Vector2i, to: Vector2i, color: Color) -> void:
	var steps := maxi(absi(to.x - from.x), absi(to.y - from.y))
	for s in steps + 1:
		var p := Vector2(from).lerp(Vector2(to), float(s) / maxf(steps, 1))
		var at := Vector2i(p.round())
		if Rect2i(Vector2i.ZERO, image.get_size()).has_point(at):
			image.set_pixelv(at, color)
			if at.x + 1 < image.get_width():
				image.set_pixelv(at + Vector2i(1, 0), color)


## Config's Avatar tab: wears `id` at once, wherever it is and whatever it is doing, and saves it.
func choose(id: String) -> void:
	var placeholders: Dictionary = game.balance.data["placeholders"]
	use_def(Avatar.load_def(Avatar.resolve_id(id, Avatar.choices(placeholders)), placeholders, game.idle_fps_max))
	game.settings.data["avatar_id"] = avatar_id
	game.settings.save()
	print("VibeNature: avatar %s" % avatar_id)


func is_home() -> bool:
	return patch == null


func _seat_point() -> Vector2:
	return game.home.seat_point() + Vector2(AssetLibrary.vec2i(game.balance.data["avatar"]["seat_offset_px"]))


## Sits on the bench at once (start up), no puff.
func sit_at_home() -> void:
	patch = null
	tool_id = ""
	_pos = _seat_point()
	_update_depth()
	_host(game.home.avatar_host())
	show_doing("sit")


## Puff out wherever it is, puff in at `point` on `target`.
func poof_to_patch(target: PatchWindow, point: Vector2) -> void:
	busy = true
	await _poof_out()
	patch = target
	_pos = clamp_to_depths(point.round()).round()
	_update_depth()
	_host(target.layer_node(depth))
	_poof(target.layer_node(depth), _pos)
	show_doing("idle")
	busy = false


func poof_home() -> void:
	busy = true
	await _poof_out()
	patch = null
	tool_id = ""
	_pos = _seat_point()
	_update_depth()
	_host(game.home.avatar_host())
	_poof(game.home.avatar_host(), _pos)
	show_doing("sit")
	busy = false


func _poof_out() -> void:
	if sprite.get_parent() != null:
		_poof(sprite.get_parent() as Node2D, _pos)
		sprite.mark_changed()
		sprite.get_parent().remove_child(sprite)
	await get_tree().create_timer(float(game.balance.data["avatar"]["poof_gap_sec"])).timeout


func _poof(host: Node2D, point: Vector2) -> void:
	var puff := CreatureSprite.new(_poof_def)
	puff.set_layer("front")
	puff.position = point
	host.add_child(puff)
	puff.finished.connect(func() -> void:
		puff.mark_changed()
		puff.queue_free())
	puff.play(_poof_def.animation_or_fallback("front", "poof"))


func _host(parent: Node2D) -> void:
	if sprite.get_parent() != parent:
		if sprite.get_parent() != null:
			sprite.mark_changed()
			sprite.get_parent().remove_child(sprite)
		parent.add_child(sprite)
	sprite.position = _pos
	sprite.mark_changed()


## Walks along the island to `point` (art pixels in the island's window).
func walk_to(point: Vector2) -> void:
	_target = clamp_to_depths(point.round()).round()
	if _target == _pos:
		return
	face(_target)
	show_doing("walk")
	_speed = float(game.balance.data["avatar"]["walk_speed_px_per_sec"])
	set_process(true)
	Pace.start_moving()
	await arrived
	show_doing("idle")


## Plays the tool's action (its own animation if the art has one, else `act`), then idles.
## `into_island`: the mechanic says this spot faces into the island, so it idles from the back.
func act(action: String, into_island: bool = false) -> void:
	show_doing(action)
	await get_tree().create_timer(float(game.balance.data["avatar"]["act_sec"])).timeout
	show_doing("idle", into_island)


func art_position() -> Vector2:
	return _pos


## Where the rod the art draws in its hands ends now (window art pixels, the centre of the
## tip pixel), for the line to hang from; INF when the frame shown draws no rod or the art
## gives no `rod_tips` (a placeholder), so the island draws the rod itself.
func rod_tip() -> Vector2:
	if sprite == null or sprite.layer == "" or sprite.anim == "":
		return Vector2.INF
	var tips: Array = sprite.def.rod_tips.get(sprite.anim, [])
	var frames: Array = sprite.def.layers[sprite.layer]["animations"].get(sprite.anim, {}).get("frames", [])
	var index := frames.find(sprite.frame)
	if index < 0 or index >= tips.size() or not (tips[index] is Array):
		return Vector2.INF
	var sheet: Dictionary = sprite.def.layers[sprite.layer]
	var tip := Vector2(float(tips[index][0]) + 0.5, float(tips[index][1]) + 0.5)
	if sprite.flip_h:
		tip.x = float(Vector2i(sheet["frame_size"]).x) - tip.x
	return sprite.position + tip - Vector2(sheet["anchor"])


func _process(delta: float) -> void:
	_pos = _pos.move_toward(_target, _speed * delta)
	sprite.move_to(_pos.round())
	_update_depth()
	if _pos == _target:
		set_process(false)
		Pace.stop_moving()
		arrived.emit()


## The illustrated island it is on (its pack has `art/meta.json`), or null.
func _illustrated_pack() -> IslandPack:
	if patch == null or game == null:
		return null
	var pack: IslandPack = game.packs.get(patch.def.id)
	return pack if pack != null and pack.illustrated else null


## The furthest depth this avatar has sheets for, front to back without a gap.
func furthest_depth() -> String:
	if not def.depths.has("mid"):
		return "front"
	return "back" if def.depths.has("back") else "mid"


## The depth to draw at with its feet at `point` (window art pixels): the island's layer
## there (`IslandPack.layer_at`), or the nearest one this avatar has sheets for; front at
## home and on islands without `art/meta.json`.
func depth_at(point: Vector2) -> String:
	var pack := _illustrated_pack()
	if pack == null:
		return "front"
	var order := CreatureDef.LAYER_ORDER
	var wanted := order.find(pack.layer_at(point.y - patch.sky_px))
	return order[maxi(wanted, order.find(furthest_depth()))]


## `point` (window art pixels) moved forward, if need be, into the depths this avatar has
## sheets for.
func clamp_to_depths(point: Vector2) -> Vector2:
	var pack := _illustrated_pack()
	if pack == null:
		return point
	var top := ceilf(pack.layer_top(furthest_depth())) + patch.sky_px
	return Vector2(point.x, maxf(point.y, top))


## Draws at the depth where its feet are now, in that depth's layer of the island.
func _update_depth() -> void:
	if sprite == null:
		return
	var wanted := depth_at(_pos)
	if wanted != depth:
		depth = wanted
		sprite.use_sheets(def if depth == "front" else def.depths[depth])
	if patch != null and sprite.get_parent() != null and sprite.get_parent() != patch.layer_node(depth):
		_host(patch.layer_node(depth))
