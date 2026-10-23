class_name SceneSheet
extends Sprite2D

## A creature the bench drew (contract §7, Skypatch issue 100),
## played for the behaviour engine: the scene package's `creatures/<id>/meta.json` with `views` (side,
## and toward/away where drawn), each with its frame grid, anchor, `px_per_m` and animations, and
## `depths` sheets (`<id>_<view>@mid.png` at 48 px/m, `<id>_<view>@far.png` at 24) for the far bank.
##
## - **Size:** a sheet px is always drawn at a whole number of art px (or a half): of the master,
##   `@mid` and `@far` sheets at ½, 1, 2 or 3 art px per sheet px, the one nearest the size the
##   creature's place wants (native size preferred), so pixel art stays crisp at every distance
##   (Skypatch issue 112). A far-bank animal shown at 2x
##   (48 art px/m) is the `@mid` sheet at 1:1, as fine as the kit, not `@far` doubled
##   (Skypatch issue 116).
## - **Gaits:** an animation with a `speed` (art px/s at the sheet's scale) plays at the rate the
##   animal actually covers ground, so feet do not slide; standing still holds the frame.
## - **Poses:** a long non-looping action (graze: head goes down, nibbles, comes up) plays its way in,
##   holds the middle for as long as the beat lasts, and plays its way out as the beat ends.
## - **Missing actions** fall back to the nearest one drawn (a fox has no graze: it looks).
## - **Cut frames are never played** (Skypatch issue 156): a
##   frame whose body runs into the frame's edge (a fish's dive cropped at the bottom) is left out of
##   its animation, so the animal never shows as half of itself. Found from the pixels at load, so a
##   redrawn sheet plays in full as soon as it lands.
## - **Depth crossfade:** when the size wanted crosses from one crisp set or scale to the next (a fish
##   swimming into the murk: master to `@back`, or master at 1/2 without one), the old drawing fades
##   out under the new one over `crossfade_sec` instead of popping.
## - **Depth views** (issue 237): given a heading
##   view (`SceneHeading`: 3q_toward, toward, 3q_away, away) and a looping action whose row is drawn
##   in the bench's toward/away sheets (`<action>_<heading>`, e.g. `swim_3q_away`), that row plays
##   instead of the side view. Its size is the side's (same px per metre, the action's `scale` and
##   tint), its body centre sits where the side view's does, it carries on at the same point of the
##   wingbeat or tail beat (`_cyc`, in cycles), the old view dissolves under the new over
##   `view_fade_sec`, and a straight-on view keeps the mirror it came in with (`face`), so nothing pops.
##   Species without such rows keep the side view.
##
## Parent units are metres (the creature's node is scaled to points per metre).

## Art px per sheet px a sheet may be drawn at.
const SCALES := [0.5, 1.0, 2.0, 3.0]
## What drawing off native size costs in the choice (as a log of size): half drops pixels, double
## and triple make the pixels chunky next to the kit, so native wins any close call.
const SCALE_COST := [0.18, 0.0, 0.25, 0.3]
## What to play when an action is not drawn, nearest first.
const FALLBACK := {
	"graze": ["peck", "drink", "look", "idle"], "peck": ["graze", "idle"], "drink": ["graze", "look", "idle"],
	"trot": ["walk", "run"], "run": ["trot", "walk"], "walk": ["trot", "swim", "run"], "strike": ["look", "idle"],
	"startle": ["look", "idle"], "lie": ["sit", "idle"], "sit": ["idle"], "groom": ["sit", "idle"], "look": ["idle"],
	"ear_flick": ["look", "idle"], "tail_flick": ["sit", "look", "idle"], "climb": ["run", "walk"], "hop": ["walk", "peck"],
	"takeoff": ["fly"], "glide": ["fly"], "land": ["fly"], "perch": ["idle"], "surface": ["swim"], "dive": ["swim"],
	"swim": ["walk", "idle"], "bottom": ["swim"], "turn": ["swim"], "bask": ["idle"], "idle": ["perch", "bask", "swim", "walk"], "fly": ["glide"], "hover": ["fly"],
	"stalk": ["walk"], "freeze": ["look", "idle"], "strike_fast": ["strike"], "shake": ["groom"],
	"catch_frog": ["look"], "catch_fish": ["look"], "wiggle_frog": ["look"], "wiggle_fish": ["look"], "flip_frog": ["look"], "flip_fish": ["look"],
	"swallow_frog": ["look"], "swallow_fish": ["look"], "preen_breast_in": ["groom"], "preen_breast": ["groom"], "preen_breast_out": ["groom"],
	"preen_back_in": ["groom"], "preen_back": ["groom"], "preen_back_out": ["groom"], "preen_wing_in": ["groom"], "preen_wing": ["groom"], "preen_wing_out": ["groom"],
}

var id := ""
## The reduced sets a view may carry besides its master, in `meta.json` `depths` and `<id>_<view>@<depth>.png`.
const DEPTHS := ["mid", "far", "back"]
## Their px per metre when the meta does not say (`back`, a fish toward the back of the cut-away:
## `BACK_SHARE` of the master's).
const DEPTH_PPM := {"mid": 48.0, "far": 24.0}
const BACK_SHARE := 0.55
## A frame is cut when, within `CUT_BAND` px of one of its edges, a row (or column) is opaque for at
## least `CUT_SHARE` of that edge: a body sliced off, not a fin tip or a nose touching it.
const CUT_BAND := 3
const CUT_SHARE := 0.3
## Texture path -> {frame index: true} of its cut frames (read once per sheet).
static var _cut_cache := {}

## view -> {"master": set, "mid": set, "far": set}; set = {tex, frame, anchor, ppm}
var sets := {}
## view -> animations
var anims := {}
## The master scale of the side view (for gait speeds).
var master_ppm := 140.0
## Per species tweaks from the behaviour data: {action: action} swaps, {action: scale}.
var swap := {}
var action_scale := {}
## Per action, a value to multiply the drawing by (a pale flight frame drawn a little darker).
var action_tint := {}
## Per action, one frame of a drawn animation held still: {"glide": ["fly", 2]} (a heron gliding on
## spread wings is a wingbeat's frame held, not the flapping loop).
var hold := {}
## Art px per master sheet px as last drawn (the set's scale and the chosen whole scale).
var art_per_master_px := 1.0
## The frame a one-shot starts on and whether it plays backwards (a freeze undone, a miss coming up
## out of the stab partway through the slow strike).
var start_frame := 0
var reverse := false
var view := "side"
var depth := "master"
var action := "idle"
var _t := 0.0
## How fast a loop plays (a fish's tail: lazy hanging in the water, fast in a dart).
var rate := 1.0
var _loop := 0.0
## Loops: how far through the cycle, in cycles (so a view swap keeps the point of the wingbeat).
var _cyc := 0.0
## Seconds the old view takes to dissolve when the view changes (0: a straight swap).
var view_fade_sec := 0.0
## Which way the creature faces (+1 right); straight-on views keep the one they came in with.
var face := 1.0
var _lock_face := 1.0
## The row of the view being played (`fly_3q_away`; the action's own name in the side view).
var row := ""
## Per depth row, the frame a held action holds ({"fly_toward": 2}), from the species' `hold_rows`.
var hold_rows := {}
## The most a reduced set (`@mid`, `@far`, `@back`) is blown up: a heron flying away into the scene
## at 3x its 24 px/m `@far` set reads as blocks (issue 237), so it takes 2 (species `max_reduced_scale`).
var max_reduced_scale := 3.0
## view -> the side row's body centre less its anchor, in master px, for views anchored on the
## body centre drawn in place of a side view anchored on the feet (a flying heron).
var _body_shift := {}
var _kinds := {}
var _echo_view := ""
var _echo_row := ""
var _echo_len := 0.0
var _echo_mirror := 1.0
var _mirror := 1.0
var _view_hint_was := ""
var _dur := -1.0
var _phase := 0.0
## Where in its cycle (0..1) the first loop or gait starts, then -1 (issue 272): two of a kind that
## arrive together never beat or step in lockstep. Later actions start at their first frame.
var start_phase := -1.0
var _loaded := ""
## Metres of the animal under the surface (a wading heron's legs, a swimming turtle), from the feet up.
var wade_m := 0.0
## A waterline in the parent's units (the look's: metres, down positive) wherever the body is, INF
## none: a bass leaping out on the pond is cut at the surface row for its depth (issue 340).
var waterline_local := INF
var below_alpha := 0.0
## Water haze toward the back of the cut-away: 0 clear, 1 all haze colour.
var haze := 0.0
var haze_color := Color(0.2, 0.35, 0.35)
## Seconds the old drawing takes to fade out when the set or scale changes (0: a straight swap).
var crossfade_sec := 0.0
## view -> {frame: true}: frames cut in any of the view's sets.
var cut := {}
var _material: ShaderMaterial
var _pick_key := ""
var _echo: Sprite2D
var _echo_t := 0.0
## The open edges (issue 424), set by the scene: an animal there dissolves with the ground it stands on.
## `fade_world` is the scene's world node (a sheet outside it, in the transit window, never fades);
## `fade_edges` the open bands (left margin, right, bottom; points) and the scene's width.
static var fade_world: Node2D
static var fade_edges := Vector4.ZERO
static var fade_h := 0.0
static var fade_soft := Vector2(0.3, 0.85)


## Whether `load_for(sheet_id)` would give a sheet, without making one: a check that builds the
## node leaks a Sprite2D and its material each call, since nodes are not freed by reference
## (issue 297, a desktop flight asked every frame).
## A creature's folder, in the scene package (`AssetLibrary.creature_dir`).
static func dir_of(sheet_id: String) -> String:
	return AssetLibrary.creature_dir(sheet_id)


## A creature's meta.json, or {}.
static func meta_of(sheet_id: String) -> Dictionary:
	var path := dir_of(sheet_id).path_join("meta.json")
	if sheet_id == "" or not FileAccess.file_exists(path):
		return {}
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	return meta if meta is Dictionary else {}


static func exists(sheet_id: String) -> bool:
	var path := dir_of(sheet_id).path_join("meta.json")
	if sheet_id == "" or not FileAccess.file_exists(path):
		return false
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not meta is Dictionary or not meta.has("views") or not (meta["views"] as Dictionary).has("side"):
		return false
	return AssetLibrary.image_exists(dir_of(sheet_id).path_join("%s_side.png" % sheet_id))


static func load_for(sheet_id: String) -> SceneSheet:
	var path := dir_of(sheet_id).path_join("meta.json")
	if sheet_id == "" or not FileAccess.file_exists(path):
		return null
	var meta = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not meta is Dictionary or not meta.has("views"):
		return null
	var s := SceneSheet.new()
	s.id = sheet_id
	s.centered = false
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s._material = ShaderMaterial.new()
	s._material.shader = preload("res://scripts/scene/scene_sheet.gdshader")
	s.material = s._material
	for v in meta["views"]:
		var spec: Dictionary = meta["views"][v]
		var file := dir_of(sheet_id).path_join("%s_%s.png" % [sheet_id, v])
		var tex := AssetLibrary.cached_texture(file)
		if tex == null:
			continue
		var entry := {"master": {"tex": tex, "frame": Vector2(float(spec["frame_w"]), float(spec["frame_h"])),
				"anchor": Vector2(float(spec["anchor"][0]), float(spec["anchor"][1])), "ppm": float(spec.get("px_per_m", 140.0))}}
		if spec.has("perch_anchor"):
			entry["master"]["perch"] = Vector2(float(spec["perch_anchor"][0]), float(spec["perch_anchor"][1]))
		if spec.has("water_anchor"):
			entry["master"]["water"] = Vector2(float(spec["water_anchor"][0]), float(spec["water_anchor"][1]))
		for d in DEPTHS:
			var depth_spec: Dictionary = spec.get("depths", {}).get(d, {})
			var depth_file := dir_of(sheet_id).path_join("%s_%s@%s.png" % [sheet_id, v, d])
			var depth_tex := AssetLibrary.cached_texture(depth_file) if not depth_spec.is_empty() else null
			if depth_tex != null:
				entry[d] = {"tex": depth_tex, "frame": Vector2(float(depth_spec["frame"][0]), float(depth_spec["frame"][1])),
						"anchor": Vector2(float(depth_spec["anchor"][0]), float(depth_spec["anchor"][1])),
						"ppm": float(depth_spec.get("px_per_m", DEPTH_PPM.get(d, float(spec.get("px_per_m", 140.0)) * BACK_SHARE)))}
				if depth_spec.has("perch_anchor"):
					entry[d]["perch"] = Vector2(float(depth_spec["perch_anchor"][0]), float(depth_spec["perch_anchor"][1]))
				if depth_spec.has("water_anchor"):
					entry[d]["water"] = Vector2(float(depth_spec["water_anchor"][0]), float(depth_spec["water_anchor"][1]))
		s.sets[v] = entry
		s._kinds[v] = String(spec.get("anchor_kind", ""))
		s.anims[v] = spec.get("animations", {})
		var cut_here := {}
		for d in entry:
			var set: Dictionary = entry[d]
			cut_here.merge(cut_frames_of(set["tex"], set["frame"]))
		s.cut[v] = cut_here
	if not s.sets.has("side"):
		return null
	s.master_ppm = float(s.sets["side"]["master"]["ppm"])
	return s


## The drawn action that stands for `a` in `in_view`.
func resolve(a: String, in_view: String = "side") -> String:
	var have: Dictionary = anims.get(in_view, {})
	var want := String(swap.get(a, a))
	if have.has(want):
		return want
	var seen := {want: true}
	var queue: Array = FALLBACK.get(want, []).duplicate()
	while not queue.is_empty():
		var next := String(queue.pop_front())
		if seen.has(next):
			continue
		seen[next] = true
		if have.has(next):
			return next
		queue.append_array(FALLBACK.get(next, []))
	return "idle" if have.has("idle") else String(have.keys()[0])


## Starts `a` for `seconds` (-1: for as long as it lasts, a gait or a loop).
func set_action(a: String, seconds: float = -1.0, from: int = 0, backwards: bool = false) -> void:
	if a == action and seconds == _dur and from == start_frame and backwards == reverse:
		return
	if a != action or from != start_frame or backwards != reverse:
		_t = 0.0
		_phase = 0.0
		_loop = 0.0
		_cyc = 0.0
		if from > 0:
			var anim: Dictionary = anims.get("side", {}).get(resolve(a), {})
			_t = float(from) / maxf(1.0, float(anim.get("fps", 8)))
		elif start_phase >= 0.0:
			var anim: Dictionary = anims.get("side", {}).get(resolve(a), {})
			if float(anim.get("speed", 0.0)) > 0.0 or bool(anim.get("loop", true)):
				_cyc = start_phase
				_phase = start_phase * float(frames_of(a, "side").size())
	start_phase = -1.0
	action = a
	_dur = seconds
	start_frame = from
	reverse = backwards


## Where the talons grip on a perch (`perch_anchor`, issue 329) from the body-centre anchor, in art px
## facing right, for the set drawn at `ppm_art` art px per metre; ZERO when the sheet has none.
func perch_offset(ppm_art: float) -> Vector2:
	var entry: Dictionary = sets["side"]
	var pick := pick_scale(entry, ppm_art, max_reduced_scale)
	var set: Dictionary = entry[String(pick[0])]
	if not set.has("perch"):
		return Vector2.ZERO
	return ((set["perch"] as Vector2) - (set["anchor"] as Vector2)) * float(pick[1])


## Where the floating body's waterline point is (`water_anchor`, issue 355) from the body-centre anchor,
## in art px facing right, for the set drawn at `ppm_art` art px per metre playing `a` (its
## `action_scale` counted); ZERO when the sheet has none.
func water_offset(ppm_art: float, a: String = "") -> Vector2:
	var entry: Dictionary = sets["side"]
	var pick := pick_scale(entry, ppm_art, max_reduced_scale)
	var set: Dictionary = entry[String(pick[0])]
	if not set.has("water"):
		return Vector2.ZERO
	return ((set["water"] as Vector2) - (set["anchor"] as Vector2)) * float(pick[1]) * float(action_scale.get(resolve(a), 1.0) if a != "" else 1.0)


## Where the master sheet's pixel `px` is drawn, in art px from the feet (facing right).
func art_offset(px: Vector2, in_view: String = "side") -> Vector2:
	var anchor: Vector2 = sets.get(in_view, sets["side"])["master"]["anchor"]
	return (px - anchor) * art_per_master_px


## `moved_m` this step, the place's art px per metre, the view wanted, and how far off the ground
## the game lifts it (a hop, a pounce) in metres.
func update(dt: float, moved_m: float, ppm_art: float, view_hint: String = "side", air: float = 0.0) -> void:
	_t += dt
	var base := resolve(action)
	var v := "side"
	var r_name := base
	var dr := depth_row(view_hint)
	if not dr.is_empty():
		v = String(dr[0])
		r_name = String(dr[1])
	elif sets.has(view_hint) and anims[view_hint].has(resolve(action, view_hint)) and resolve(action, view_hint) == base:
		v = view_hint
		r_name = base
	var straight := SceneHeading.is_straight(view_hint) and not dr.is_empty()
	if straight and _view_hint_was == "":
		_lock_face = face
	_view_hint_was = view_hint if straight else ""
	_mirror = (_lock_face * face) if straight else 1.0
	var entry: Dictionary = sets[v]
	var pick := pick_scale(entry, ppm_art, max_reduced_scale)
	var d := String(pick[0])
	var set: Dictionary = entry[d]
	var key := v + "/" + d
	if key != _loaded:
		_loaded = key
		texture = set["tex"]
		var frame_size: Vector2 = set["frame"]
		hframes = maxi(1, int(round(texture.get_width() / frame_size.x)))
		vframes = maxi(1, int(round(texture.get_height() / frame_size.y)))
		offset = -(set["anchor"] as Vector2) + body_shift(v) * float(set["ppm"]) / maxf(master_ppm, 0.01)
	var pick_key := "%s/%s@%s" % [v, d, pick[1]]
	if _pick_key != "" and pick_key != _pick_key:
		if pick_key.get_slice("/", 0) != _pick_key.get_slice("/", 0) and view_fade_sec > 0.0:
			_start_echo(_pick_key, view_fade_sec)
		elif pick_key.get_slice("/", 0) == _pick_key.get_slice("/", 0) and crossfade_sec > 0.0:
			_start_echo(_pick_key, crossfade_sec)
	elif row != "" and r_name != row and is_depth_row(row) and is_depth_row(r_name) and view_fade_sec > 0.0:
		# Three-quarter to straight on (one sheet, two rows): the old row dissolves too.
		_start_echo(_pick_key, view_fade_sec)
	_pick_key = pick_key
	view = v
	depth = d
	var r := float(pick[1]) * float(action_scale.get(base, 1.0))
	art_per_master_px = r * float(set["ppm"]) / maxf(float(entry["master"]["ppm"]), 0.01)
	scale = Vector2(r * _mirror, r) / maxf(ppm_art, 0.01)
	var tone := float(action_tint.get(base, 1.0))
	var fade_in := 1.0
	if _echo != null and _echo.visible:
		_echo_t += dt
		var u := clampf(_echo_t / maxf(_echo_len, 0.001), 0.0, 1.0)
		fade_in = u
		_echo.modulate.a = 1.0 - u
		_echo.visible = u < 1.0
	self_modulate = Color(tone, tone, tone, fade_in)
	position = Vector2(0.0, -air)
	# The waterline in the sheet's own px: metres times sheet px per metre as drawn.
	var line := -wade_m * ppm_art / maxf(r, 0.01) if wade_m > 0.001 else 1.0e6
	if waterline_local < 1.0e5:
		line = minf(line, (waterline_local + air) / maxf(scale.y, 0.0001))
	_material.set_shader_parameter("waterline", line)
	_material.set_shader_parameter("below_alpha", below_alpha)
	_material.set_shader_parameter("haze", haze)
	_material.set_shader_parameter("haze_color", haze_color)
	_edge_fade()
	row = r_name
	frame = _frame(dt, moved_m, r_name, v)
	if hold.has(action):
		var held_name := String(hold[action][0])
		var name := r_name if not dr.is_empty() else held_name
		if anims[v].has(name):
			var held: Array = anims[v][name].get("frames", [frame])
			var i := int(hold[action][1])
			if name != held_name:
				var side_n := float((anims["side"].get(held_name, {}).get("frames", [0]) as Array).size())
				i = int(hold_rows.get(name, roundi(float(i) / maxf(side_n, 1.0) * float(held.size()))))
			frame = int(held[clampi(i, 0, held.size() - 1)])
	if _echo != null and _echo.visible:
		if _echo_view == v and _echo_row == r_name:
			_echo.frame = mini(frame, _echo.hframes * _echo.vframes - 1)
		elif String(_echo.get_meta("action")) == action and bool(anims[_echo_view].get(_echo_row, {}).get("loop", true)):
			# The old view carries on at the same point of the cycle while it fades.
			var old := frames_of(_echo_row, _echo_view)
			_echo.frame = mini(int(old[clampi(int(fposmod(_cyc, 1.0) * old.size()), 0, old.size() - 1)]), _echo.hframes * _echo.vframes - 1)
		var er := float(_echo.get_meta("r")) / maxf(r, 0.01)
		_echo.scale = Vector2(er * _echo_mirror * _mirror, er)


## The drawing as it was (`key`: view/depth@scale) kept a moment under the new one, fading out.
func _start_echo(key: String, seconds: float) -> void:
	var parts := key.split("/")
	var rest := parts[1].split("@")
	var set: Dictionary = sets.get(parts[0], {}).get(rest[0], {})
	if set.is_empty():
		return
	if _echo == null:
		_echo = Sprite2D.new()
		_echo.centered = false
		_echo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_echo.show_behind_parent = true
		_echo.use_parent_material = true
		add_child(_echo)
	_echo.texture = set["tex"]
	var frame_size: Vector2 = set["frame"]
	_echo.hframes = maxi(1, int(round(_echo.texture.get_width() / frame_size.x)))
	_echo.vframes = maxi(1, int(round(_echo.texture.get_height() / frame_size.y)))
	_echo.offset = -(set["anchor"] as Vector2) + body_shift(parts[0]) * float(set["ppm"]) / maxf(master_ppm, 0.01)
	_echo.frame = mini(frame, _echo.hframes * _echo.vframes - 1)
	_echo.set_meta("r", float(rest[1]) * float(action_scale.get(resolve(action), 1.0)))
	_echo.set_meta("action", action)
	_echo_view = parts[0]
	_echo_row = row
	_echo_len = seconds
	_echo_mirror = _mirror
	_echo.modulate = Color(1, 1, 1, 1)
	_echo.visible = true
	_echo_t = 0.0


## [view, row] for the heading view `hint` (3q_toward, toward, 3q_away, away) when the action in hand
## (or the one a held action holds) loops and has that row drawn; [] otherwise (the side view plays).
func depth_row(hint: String) -> Array:
	if not SceneHeading.is_depth(hint):
		return []
	var base := String(hold[action][0]) if hold.has(action) else resolve(action)
	var v := "toward" if hint.ends_with("toward") else "away"
	var name := base + "_" + hint
	var row_spec: Dictionary = anims.get(v, {}).get(name, {})
	if row_spec.is_empty() or not bool(row_spec.get("loop", true)) or not bool(anims["side"].get(base, {}).get("loop", true)):
		return []
	return [v, name]


static func is_depth_row(name: String) -> bool:
	return name.ends_with("_toward") or name.ends_with("_away")


## Whether any looping action of this sheet has a toward or away row (the creature then tracks its heading).
func has_depth_rows() -> bool:
	for v in ["toward", "away"]:
		for name in anims.get(v, {}):
			var n := String(name)
			if (n.ends_with("_toward") or n.ends_with("_away")) and anims["side"].has(n.get_slice("_", 0)):
				return true
	return false


## In master px, how far the side view's body centre is from its anchor, for a view anchored on the
## body centre (`anchor_kind` centre) drawn in place of a side view anchored on its feet; zero
## otherwise. From the pixels of the side's looping rows that have depth rows (a flying heron's).
func body_shift(v: String) -> Vector2:
	if v == "side" or String(_kinds.get(v, "")) != "centre" or String(_kinds.get("side", "")) == "centre":
		return Vector2.ZERO
	if _body_shift.has(v):
		return _body_shift[v]
	var side: Dictionary = sets["side"]["master"]
	var image: Image = (side["tex"] as Texture2D).get_image()
	var shift := Vector2.ZERO
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		var size: Vector2 = side["frame"]
		var cols := maxi(1, int(round(image.get_width() / size.x)))
		var sum := Vector2.ZERO
		var n := 0
		var bases := {}
		for name in anims.get(v, {}):
			bases[String(name).get_slice("_", 0)] = true
		for base in bases:
			for f in anims["side"].get(base, {}).get("frames", []):
				var at := Vector2i(int((int(f) % cols) * size.x), int((int(f) / cols) * size.y))
				var used := image.get_region(Rect2i(at, Vector2i(size))).get_used_rect()
				if used.size.x > 0:
					sum += Vector2(used.get_center())
					n += 1
		if n > 0:
			shift = sum / float(n) - (side["anchor"] as Vector2)
	_body_shift[v] = shift
	return shift


## The frames of `a` in `v` that are played: its drawn frames less any cut by the frame's edge (the
## first frame if every one is cut).
func frames_of(a: String, v: String = "side") -> Array:
	var all: Array = anims.get(v, {}).get(a, {}).get("frames", [0])
	var cut_here: Dictionary = cut.get(v, {})
	var ok := all.filter(func(f) -> bool: return not cut_here.has(int(f)))
	return ok if not ok.is_empty() else all.slice(0, 1)


## {frame index: true} for every frame of `tex` (a grid of `frame_size` px cells) whose body runs
## into the frame's edge. Cached per texture.
static func cut_frames_of(tex: Texture2D, frame_size: Vector2) -> Dictionary:
	if tex == null:
		return {}
	var key := tex.resource_path if tex.resource_path != "" else str(tex.get_instance_id())
	if _cut_cache.has(key):
		return _cut_cache[key]
	var found := {}
	var image := tex.get_image()
	if image != null and not image.is_empty():
		if image.is_compressed():
			image.decompress()
		found = cut_frames_in(image, frame_size)
	_cut_cache[key] = found
	return found


static func cut_frames_in(image: Image, frame_size: Vector2) -> Dictionary:
	var found := {}
	var cols := maxi(1, int(round(image.get_width() / frame_size.x)))
	var rows := maxi(1, int(round(image.get_height() / frame_size.y)))
	for i in cols * rows:
		var at := Vector2i(int((i % cols) * frame_size.x), int((i / cols) * frame_size.y))
		if is_cut(image, Rect2i(at, Vector2i(frame_size))):
			found[i] = true
	return found


## Whether the drawing in `rect` of `image` is sliced off by one of the rect's edges.
static func is_cut(image: Image, rect: Rect2i) -> bool:
	var w := rect.size.x
	var h := rect.size.y
	for k in mini(CUT_BAND, mini(w, h)):
		for y in [rect.position.y + k, rect.end.y - 1 - k]:
			var n := 0
			for x in range(rect.position.x, rect.end.x):
				if image.get_pixel(x, y).a > 0.03:
					n += 1
			if float(n) >= CUT_SHARE * float(w):
				return true
		for x in [rect.position.x + k, rect.end.x - 1 - k]:
			var n := 0
			for y in range(rect.position.y, rect.end.y):
				if image.get_pixel(x, y).a > 0.03:
					n += 1
			if float(n) >= CUT_SHARE * float(h):
				return true
	return false


## [depth, art px per sheet px] nearest `ppm_art` (art px per metre wanted) among the drawn sets at
## whole scales (`SCALE_COST`); a reduced set (`@far`...) no larger than `max_reduced` times.
static func pick_scale(entry: Dictionary, ppm_art: float, max_reduced := 3.0) -> Array:
	var best := ["master", 1.0]
	var best_cost := INF
	for d in ["master"] + DEPTHS:
		if not entry.has(d):
			continue
		var ppm := float(entry[d]["ppm"])
		for r in SCALES:
			if d != "master" and r > max_reduced:
				continue
			var cost := absf(log(ppm * r / maxf(ppm_art, 0.01))) + float(SCALE_COST[SCALES.find(r)])
			if cost < best_cost:
				best_cost = cost
				best = [d, r]
	return best


func _frame(dt: float, moved_m: float, a: String, v: String) -> int:
	var anim: Dictionary = anims[v].get(a, {})
	var frames: Array = frames_of(a, v)
	if frames.is_empty():
		return 0
	var n := frames.size()
	var fps := float(anim.get("fps", 8))
	var speed := float(anim.get("speed", 0.0))
	var k := 0
	if speed > 0.0:
		# Feet match the ground: the gait advances with the distance covered.
		var speed_m := speed / master_ppm
		if moved_m > 0.0001:
			_phase += clampf((moved_m / maxf(dt, 0.0001)) / speed_m, 0.25, 3.0) * fps * dt
		k = int(_phase) % n
	elif bool(anim.get("loop", true)):
		_loop += dt * fps * rate
		# In cycles, so another view's row (its own frame count and fps) picks up at the same point.
		_cyc += dt * fps * rate / float(n)
		k = int(fposmod(_cyc, 1.0) * float(n))
	elif a == "turn":
		# A turn plays straight through over the beat (quicker when the fish darts off).
		k = int(_t / _dur * float(n)) if _dur > 0.0 else int(_t * fps)
	elif n >= 12:
		var ends := ceili(float(n) * 0.2)
		var middle := n - 2 * ends
		var in_t := float(ends) / fps
		if _dur > 0.0 and _t > _dur - in_t:
			k = n - ends + clampi(int((_t - (_dur - in_t)) * fps), 0, ends - 1)
		elif _t < in_t:
			k = int(_t * fps)
		else:
			var m := int((_t - in_t) * fps) % maxi(1, middle * 2 - 2)
			k = ends + (m if m < middle else middle * 2 - 2 - m)
	else:
		k = mini(int(_t * fps), n - 1)
	if reverse and speed <= 0.0 and not bool(anim.get("loop", true)):
		k = n - 1 - clampi(k, 0, n - 1)
	return int(frames[clampi(k, 0, n - 1)])


## The scene's open edges on this sheet's shader: its own px to scene points, and the bands.
func _edge_fade() -> void:
	var w := fade_world
	var on := w != null and is_instance_valid(w) and w.is_ancestor_of(self) \
			and (fade_edges.x > 0.0 or fade_edges.y > 0.0 or fade_edges.z > 0.0)
	_material.set_shader_parameter("fade_on", on)
	if not on:
		return
	var xf := w.global_transform.affine_inverse() * global_transform
	_material.set_shader_parameter("fade_x", xf.x)
	_material.set_shader_parameter("fade_y", xf.y)
	_material.set_shader_parameter("fade_o", xf.origin)
	_material.set_shader_parameter("fade_edges", fade_edges)
	_material.set_shader_parameter("fade_h", fade_h)
	_material.set_shader_parameter("fade_soft", fade_soft)
