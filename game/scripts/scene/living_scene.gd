class_name LivingScene
extends Window

## The living scene (contract §7) in the screen's bottom-right corner: a scene kit drawn back to
## front by depth band, with one environment state moving all of it. Wind runs across the scene
## in gusts and every piece bends to it by its own sway; clouds drift and their shadows cross the
## ground; fronts bring wind, then rain (rings on the water, streaks slanted by the wind), then
## clear; mist lies on the water on calm mornings and some days are foggy; the light follows the
## real time of day. The avatar sits on the log and idles.
##
## Everything here is in scene points (the kit's art px divided by its `art_scale`), so the tuning
## holds whatever density the bench draws at. Hooks for the behaviour engine and director to come,
## all in points: `env` (weather, wind, light), `zones_of`/`in_zone`, `perches`/`perch_impulse`/
## `perch_offset` (landings dip the piece), `actor_layer(band)` (where a creature of that band draws,
## between the pieces behind and in front), `ring`/`wake`/`splash` (water), `is_water`, and `sitter` (the
## avatar's idle life, `rouse`), and `flights` (a songbird now and then out over the desktop).
##
## Never interrupts work: no focus, no sound, click-through outside the opaque art. The snapshot
## path drives it frame by frame (`manual`, `advance`) so a seed and a preset give the same clip.

signal stepped

const SHADER := preload("res://scripts/scene/scene_lit.gdshader")
const MIST_SHADER := preload("res://scripts/scene/scene_mist.gdshader")

var tuning: Dictionary = {}
var kit: SceneKit
var env: SceneEnvironment
var sway: SceneSway
## Kit art px per scene point.
var density := 1.0
## The scene's size in points.
var size_pt := Vector2.ZERO
## The old composition inside it (points): the kit's `origin`/`frame`, or all of it. Outside it the
## kit's margin art ends like a vignette and the game's sky dissolves into the desktop.
var frame_pt := Rect2()
## Window units per scene point, as shown.
var scale_px := 1.0
## Units per point the scene is drawn at: `scale_px`, or (between 50% and 100%) the full size's,
## shrunk smoothly to `scale_px` (`SharpShrink`, issue 222).
var render_scale := 1.0
## The full-size render and its shrunk view, at the in-between sizes only.
var shrink: SharpShrink
## In the bottom-left corner (issue 422) the whole picture is drawn mirrored, so the soft edge (the kit's
## margin, where the sky dissolves) faces the open desktop on the right and the left edge sits flush.
## The world stays in its own points; `shown` turns a world point into the window's and back.
var mirrored := false
## The screen corner the window holds (issue 424): its two
## edges there are straight and flush with the screen, the other two open and dissolving into the desktop.
var corner := "bottom_right"
## The part of the world the window shows (points): the whole kit, less its grown margin on a flush side.
var view_pt := Rect2()
## The open right and bottom edges' dissolve.
var edge_fade := SceneEdgeFade.new()
var _edge_version := 0
var world := Node2D.new()
var sky := SceneSky.new()
var sky_edge := SceneSkyEdge.new()
var rain := SceneRain.new()
var water_fx := SceneWaterFx.new()
var fireflies := SceneFireflies.new()
var sitter := SceneSitter.new()
## The van on the far bank and the avatar arriving and leaving (issue 198), played from `DailyRhythm`.
var van := SceneVan.new()
## When you shelter in the van from the rain and come back (issue 476); made in `setup`.
var shelter: SceneShelter
## 0..1: the light leaning golden for the wrap-up (the van's).
var golden_lean := 0.0
## The player's look ({look, skin, hair, top}), set before `setup`: its day actions walk the van's route.
var avatar_look: Dictionary = {}
var _day_ready := false
var visitors := SceneVisitors.new()
## The animals and the director (Skypatch issue 104).
var behaviour := SceneBehaviour.new()
## The sound engine while the Sound switch is on, else null (`set_sound`).
var sound: SceneSound
## Rare flights out over the desktop (Skypatch issue 120).
var flights := SceneDesktopFlight.new()
## Single leaves at the margin that fall now and then and regrow (kit `drop`).
var drops := SceneLeafDrops.new()
var beacon: CalmLabBeacon
var t := 0.0
## The snapshot path steps the scene itself; otherwise it runs on the frame clock.
var manual := false
## False: each step leaves the shaders' shared state (light, clouds, gusts) as it was. Only for
## headless measuring of motion (`tools/speed_probe.gd`, issue 384): nothing that moves reads it,
## and pushing it was nine tenths of an empty step.
var shading := true
## Returns the minute of the local day (float). Set by the game; clips set `minute` instead.
var clock_minute: Callable
var minute := 600.0
var _bands := {}
var _actors := {}
var _materials: Array[ShaderMaterial] = []
var _sway_textures := {}
var _gust_image: Image
var _gust_texture: ImageTexture
var _mask_image: Image
var _mask_texture: ImageTexture
var _mists: Array = []
var _zones: Array = []
## Each piece's image, to settle perches onto what is actually drawn.
var _piece_images := {}
var _piece_materials := {}
var _perches: Array = []
var _rng := RandomNumberGenerator.new()
## The seed this scene was set up with (random in the game, pinned in snapshots and renders).
var _seed := 0
var _visits := true
## The parts of the window that catch the mouse; everything else is click-through.
var hit := SceneHitRegions.new()
## The control strip (scene mode only; none in clips and bare test scenes).
var controls: SceneControls
## The camera's viewfinder (scene mode only, issue 176).
var viewfinder: SceneViewfinder
## Whether a letter is due to be read on the log (issue 270; the game sets it): once you sit at the log, the end of
## your first rest is reading it. Never set without a waiting letter.
var letter_due := false:
	set(v):
		letter_due = v
		if v:
			_load_letter()
## While reading, a click on the reader opens the journal at the letter.
signal letter_clicked
## The sitter took the letter out (the game marks it read on the log; it still waits in the journal).
signal letter_started
const LETTER_REGION := "letter_read"
var _letter_ready := false
var _extras_ready := false
var _letter_region := false
## The letter on the scene while you read it (scene mode only, issue 314).
var letter_card: SceneLetterCard
## The steps of reading in which he holds the letter open (the card shows through them).
const LETTER_OPEN_ANIMS := ["log_letter_open", "log_letter_read", "log_letter_look_up", "log_letter_look_down"]
## The demo's morning card (the demo build in scene mode only, issue 268).
var demo_card: SceneDemoCard
## The see-through circle round the cursor while on top (scene mode only, issue 428).
var mouse_clear: SceneMouseClear
## Started and not manual: the window draws every frame (see `resume_drawing`).
var draws_always := false
## How many times drawing was handed back (tests).
var resumed := 0


## `pt_scale` is window units per scene point (the screen's scale, times the player's size);
## `draw_scale`, when larger, is the whole scale it is drawn at before being shrunk to `pt_scale`.
func setup(scene_tuning: Dictionary, phases: DayPhases, pt_scale: float, avatar_id: String, seed: int, draw_scale: float = 0.0) -> void:
	tuning = scene_tuning
	_rng.seed = seed
	_seed = seed
	kit = SceneKit.load_scene(String(tuning["scene_id"]))
	for problem in kit.problems():
		push_warning("VibeNature: scene kit %s: %s" % [kit.id, problem])
	density = maxf(kit.art_scale, 0.01)
	size_pt = Vector2(kit.size) / density
	frame_pt = Rect2(kit.frame_rect().position / density, kit.frame_rect().size / density)
	view_pt = Rect2(Vector2.ZERO, size_pt)
	scale_px = pt_scale
	render_scale = maxf(draw_scale, pt_scale)
	title = "VibeNature"
	WindowChrome.configure(self, Vector2i((view_pt.size * scale_px).round()))
	# Only the hit regions (the control strip, issue 169) catch the mouse; with none, every click
	# goes through to whatever is behind the scene.
	hit.apply(self)
	world.name = "World"
	world.scale = Vector2(render_scale, render_scale)
	_apply_view()
	if SharpShrink.needed(scale_px, render_scale):
		shrink = SharpShrink.new()
		shrink.build(self, world, Vector2i((view_pt.size * render_scale).round()), size)
	else:
		add_child(world)
	for zone in kit.zones:
		_zones.append(_zone_in_points(zone))
	env = SceneEnvironment.new(tuning, phases, size_pt.x, seed)
	sway = SceneSway.new(tuning["sway"])
	_build_shared()
	sky.edge_keep = edge_keep
	sky_edge.setup(size_pt, frame_pt, tuning["sky"].get("dissolve", {}), kit.id, _margin_art() if kit.has_margin() else null)
	sky.edge_shape = sky_edge
	sky.setup(size_pt, tuning["sky"], seed + 3, density, frame_pt)
	world.add_child(sky)
	_build_bands(avatar_id, seed)
	_link_followers()
	edge_fade.setup(size_pt, tuning["edges"]["fade"], kit.id)
	_apply_edges()
	drops.setup(self, tuning["edges"]["drop"], seed + 31)
	rain.setup(size_pt, tuning["rain"], seed + 11, water_rows().x, kit.cut_y() / density)
	rain.edge_keep = edge_keep
	# The rain comes out of the cloud line's underside, lumps and all (issue 477).
	rain.deck_under = func(x: float) -> float:
		var base := sky.deck_base(x, env)
		return frame_pt.position.y + base - sky.deck_lump() if base > 0.0 else 0.0
	world.add_child(rain)
	fireflies.setup(tuning["fireflies"], seed + 17)
	fireflies.position = frame_pt.position
	world.add_child(fireflies)
	_update_shared()


## A new size in place (issue 307): the same
## animals, sitter, van and weather go on where they are (everything is in points); only how many
## window units a point is changes, and whether the world is drawn larger and shrunk (`SharpShrink`).
## A flight out over the desktop stops (its line was planned in screen units); an open viewfinder closes.
func rescale(pt_scale: float, draw_scale: float = 0.0, at_smallest: bool = false, at_largest: bool = true) -> void:
	scale_px = pt_scale
	render_scale = maxf(draw_scale, pt_scale)
	_refit(at_smallest, at_largest)


## The window to the view's size at the current scale, the world drawn into it, and everything placed
## in window units following (the strip, the cards, the hit regions).
func _refit(at_smallest: bool, at_largest: bool) -> void:
	var px := Vector2i((view_pt.size * scale_px).round())
	min_size = Vector2i.ZERO
	max_size = Vector2i.ZERO
	size = px
	min_size = px
	max_size = px
	if shrink != null:
		shrink.viewport.remove_child(world)
		shrink.viewport.queue_free()
		shrink.view.queue_free()
		remove_child(shrink.viewport)
		remove_child(shrink.view)
		shrink = null
	elif world.get_parent() == self:
		remove_child(world)
	world.scale = Vector2(render_scale, render_scale)
	_apply_view()
	if SharpShrink.needed(scale_px, render_scale):
		shrink = SharpShrink.new()
		shrink.build(self, world, Vector2i((view_pt.size * render_scale).round()), size)
		move_child(shrink.viewport, 0)
		move_child(shrink.view, 1)
	else:
		add_child(world)
		move_child(world, 0)
	sitter.snap_step = 1.0 / maxf(1.0, float(tuning["sitter"]["scale"]) * render_scale)
	flights.rescale()
	if viewfinder != null:
		viewfinder.cancel()
		viewfinder.scale_px = scale_px
	if viewfinder != null:
		viewfinder.bounds = shown_rect(frame_pt if frame_pt.has_area() else Rect2(Vector2.ZERO, size_pt))
	if controls != null:
		_place_controls()
		controls.resized(Vector2(size), at_smallest, at_largest)
	if demo_card != null:
		demo_card.resized()
	if letter_card != null:
		letter_card.reader = letter_window_rect()
		letter_card.keep_clear = controls.strip_rect() if controls != null else Rect2()
		letter_card.resized()
	if _letter_region:
		hit.set_region(LETTER_REGION, letter_window_rect())
	hit.apply(self)
	resume_drawing()


func _zone_in_points(zone: Dictionary) -> Dictionary:
	var out := zone.duplicate(true)
	for key in ["polygon", "lane"]:
		if out.has(key):
			var points: Array = []
			for p in out[key]:
				points.append([float(p[0]) / density, float(p[1]) / density])
			out[key] = points
	return out


func _build_shared() -> void:
	var cols := ceili(size_pt.x / float(tuning["gust_column_px"])) + 1
	_gust_image = Image.create_empty(cols, 1, false, Image.FORMAT_RF)
	_gust_texture = ImageTexture.create_from_image(_gust_image)
	var mask_file := String(kit.water.get("mask", ""))
	if mask_file != "":
		_mask_image = kit.image(mask_file)
	if _mask_image == null or _mask_image.is_empty():
		_mask_image = Image.create_empty(kit.size.x, kit.size.y, false, Image.FORMAT_RGBA8)
		var top := int(kit.water.get("surface_top", kit.water.get("surface_y", 0)))
		_mask_image.fill_rect(Rect2i(0, top, kit.size.x, int(kit.water.get("bottom_y", top)) - top), Color.WHITE)
	_mask_image.convert(Image.FORMAT_RGBA8)
	_mask_texture = ImageTexture.create_from_image(_mask_image)


## Where the far waterline and the nearest water are, in points.
func water_rows() -> Vector2:
	var top := float(kit.water.get("surface_top", kit.water.get("surface_y", 0))) / density
	var bottom := float(kit.water.get("bottom_y", kit.water.get("surface_y", 0))) / density
	return Vector2(top, maxf(bottom, top + 1.0))


## Each band's plates and pieces in z order, its actor layer at z 0 (or the seat's z), and the
## mist layers, the seat and the water's rings where they belong.
func _build_bands(avatar_id: String, seed: int) -> void:
	var by_band := {}
	for band in kit.band_ids():
		by_band[band] = []
		var host := Node2D.new()
		host.name = "Band_" + band
		world.add_child(host)
		_bands[band] = host
		var actors := Node2D.new()
		actors.name = "Actors_" + band
		actors.y_sort_enabled = true
		_actors[band] = actors
		by_band[band].append({"z": float(tuning["actor_z"].get(band, 0.0)), "node": actors})
	# Extra layers inside a band (`actor_layers`): a bird among the oak's leaves draws behind the crowns.
	var extra: Dictionary = tuning.get("actor_layers", {})
	for layer in extra:
		var spec: Dictionary = extra[layer]
		if not by_band.has(String(spec["band"])):
			continue
		var actors := Node2D.new()
		actors.name = "Actors_" + String(layer)
		actors.y_sort_enabled = true
		_actors[String(layer)] = actors
		by_band[String(spec["band"])].append({"z": float(spec["z"]), "node": actors})
	for entry in kit.draw_order():
		var spec: Dictionary = entry["spec"]
		var band := String(spec.get("band", ""))
		if not by_band.has(band):
			continue
		var node := _make_plate(spec, band) if entry["what"] == "plate" else _make_piece(spec, band)
		if node != null:
			by_band[band].append({"z": float(entry["z"]), "node": node})
		if entry["what"] == "piece" and node != null:
			var stalks := _make_submerged(spec, band)
			if stalks != null:
				by_band[band].append({"z": float(tuning["submerged"]["z"]), "node": stalks})
	var seat_band := String(kit.seat.get("band", kit.band_ids()[-1]))
	if by_band.has(seat_band) and kit.seat.has("at"):
		sitter.seat_supports = kit.seat.get("supports", [])
		sitter.setup(avatar_id, Vector2(SceneKit._vec2i(kit.seat["at"])) / density, kit.band_scale(seat_band), tuning["sitter"], SHADER, seed + 5)
		sitter.snap_step = 1.0 / maxf(1.0, float(tuning["sitter"]["scale"]) * render_scale)
		_materials.append_array(sitter.materials)
		by_band[seat_band].append({"z": float(kit.seat.get("z", 0)), "node": sitter})
	visitors.setup(self, tuning["visitors"], SHADER, seed + 7)
	world.add_child(visitors)
	behaviour.setup(self, tuning["behaviour"], seed + 23)
	world.add_child(behaviour)
	van.setup(tuning["day"], density)
	actor_layer(String(tuning["day"]["van"]["band"])).add_child(van)
	shelter = SceneShelter.new(tuning["day"]["shelter"])
	flights.setup(self, seed + 29)
	add_child(flights)
	water_fx.setup(tuning["water"])
	water_fx.floor_y = kit.cut_y() / density
	var water_band := _band_of_kind("water_surface")
	if by_band.has(water_band):
		by_band[water_band].append({"z": 100000.0, "node": water_fx})
	var rows := water_rows()
	for mist in tuning["mist_layers"]:
		var band := String(mist["after_band"])
		if not by_band.has(band):
			continue
		var rect := ColorRect.new()
		rect.name = "Mist_" + band
		rect.size = size_pt
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var m := ShaderMaterial.new()
		m.shader = MIST_SHADER
		m.set_shader_parameter("size", size_pt)
		m.set_shader_parameter("center_y", rows.x + float(mist["offset_y"]))
		m.set_shader_parameter("above", float(mist["above_px"]))
		m.set_shader_parameter("below", float(mist["below_px"]))
		m.set_shader_parameter("fade_left", float(tuning["sky"]["fade_left_px"]) + frame_pt.position.x)
		m.set_shader_parameter("max_alpha", float(mist["max_alpha"]))
		rect.material = m
		by_band[band].append({"z": 200000.0, "node": rect})
		_mists.append({"material": m, "spec": mist})
	for band in kit.band_ids():
		var items: Array = by_band[band]
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["z"]) < float(b["z"]))
		for item in items:
			(_bands[band] as Node2D).add_child(item["node"])


func _band_of_kind(kind: String) -> String:
	for zone in kit.zones_of(kind):
		return String(zone.get("band", ""))
	return kit.band_ids()[-1] if not kit.bands.is_empty() else ""


func _lit(origin_pt: Vector2, depth: float, water: bool, texel_density: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("origin", origin_pt)
	m.set_shader_parameter("density", texel_density)
	m.set_shader_parameter("depth", depth)
	m.set_shader_parameter("water", 1.0 if water else 0.0)
	m.set_shader_parameter("pixel_snap", kit.is_pixel())
	_materials.append(m)
	return m


func _depth_of(band: String) -> float:
	var n := maxi(1, kit.bands.size() - 1)
	return float(kit.band_index(band)) / float(n)


func _make_plate(spec: Dictionary, band: String) -> Sprite2D:
	var image := kit.image(String(spec["file"]))
	if image == null or image.is_empty():
		return null
	var sprite := Sprite2D.new()
	sprite.name = String(spec.get("id", "plate"))
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(image)
	var at := Vector2(SceneKit._vec2i(spec.get("at", [0, 0]))) / density
	sprite.position = at
	sprite.scale = Vector2.ONE / density
	sprite.texture_filter = _kit_filter()
	sprite.material = _lit(at, _depth_of(band), true, density)
	return sprite


## Painted kits sample smoothly, so a bend moves a stroke by a fraction of a pixel instead of
## breaking it into steps; pixel-art kits (`style: pixel`, or one art px or more per point) are
## sampled nearest and the shader moves them by whole art px, so a bend never softens an edge.
func _kit_filter() -> CanvasItem.TextureFilter:
	if kit.is_pixel() or density <= 1.0:
		return CanvasItem.TEXTURE_FILTER_NEAREST
	return CanvasItem.TEXTURE_FILTER_LINEAR


const _BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


## The submerged part of a stalk standing in the water (a cattail, a reed bed): the kit draws it
## down to where it meets the surface; under the surface, in the cut-away, it carries on, dimmer
## and bluer with depth, then thinning out until the water hides it. Built once from the piece's own foot: every
## column whose lowest drawn pixel is at the foot runs straight down in that column's colour.
## Rigid, like the foot it hangs from. A pixel kit fades by an ordered dither (alpha stays 0 or 1).
## Null for anything not rooted in open water above the cut.
func _make_submerged(spec: Dictionary, band: String) -> Sprite2D:
	var sub: Dictionary = tuning["submerged"]
	if not (sub["kinds"] as Array).has(String(spec.get("kind", ""))):
		return null
	var image: Image = _piece_images.get(String(spec["id"]))
	var under := kit.underwater_rect()
	if image == null or under.size.y <= 0.0:
		return null
	var at := SceneKit._vec2i(spec["at"])
	var pivot: Array = spec.get("pivot", [image.get_width() / 2, image.get_height()])
	var foot := int(pivot[1])
	var cut := int(kit.cut_y())
	if at.y + foot >= cut or not is_water(Vector2(at.x + int(pivot[0]), at.y + foot) / density):
		return null
	var reach := int(float(sub["foot_pt"]) * density)
	var sample_up := int(float(sub["sample_up_pt"]) * density)
	var bottoms := PackedInt32Array()
	var colors: Array[Color] = []
	var top := image.get_height()
	for x in image.get_width():
		var bottom := -1
		for y in range(image.get_height() - 1, -1, -1):
			if image.get_pixel(x, y).a > 0.5:
				bottom = y
				break
		var color := Color(0, 0, 0, 0)
		if bottom >= 0 and bottom >= foot - reach and at.x + x >= int(under.position.x) and at.x + x < int(under.end.x):
			var up := image.get_pixel(x, maxi(0, bottom - sample_up))
			color = up if up.a > 0.5 else image.get_pixel(x, bottom)
			top = mini(top, bottom + 1)
		else:
			bottom = -1
		bottoms.append(bottom)
		colors.append(color)
	if top >= image.get_height():
		return null
	var depth := int(float(sub["depth_pt"]) * density)
	var height := cut + depth - (at.y + top)
	if height <= 0:
		return null
	var waterline: Array = sub["waterline_pt"]
	var line_above := int(float(waterline[0]) * density)
	var line_below := int(float(waterline[1]) * density)
	var tint := Color(String(sub["tint"]))
	var steps := float(maxi(1, int(sub["tint_steps"])))
	var pixel := kit.is_pixel()
	var out := Image.create_empty(image.get_width(), height, false, Image.FORMAT_RGBA8)
	for x in image.get_width():
		if bottoms[x] < 0:
			continue
		for row in range(bottoms[x] + 1 - top, height):
			var y := at.y + top + row
			if y >= cut - line_above and y < cut + line_below:
				continue
			var alpha: float
			var k: float
			if y < cut:
				alpha = float(sub["gap_alpha"])
				k = float(sub["gap_tint"])
			else:
				var f := clampf(float(y - cut) / float(maxi(depth, 1)), 0.0, 1.0)
				var solid := float(sub["solid_until"])
				alpha = clampf((1.0 - f) / maxf(1.0 - solid, 0.01), 0.0, 1.0)
				k = lerpf(float(sub["tint_near"]), float(sub["tint_far"]), f)
			if pixel:
				k = ceilf(k * steps) / steps
				var threshold := (float(_BAYER[(y % 4) * 4 + ((at.x + x) % 4)]) + 0.5) / 16.0
				alpha = 1.0 if threshold < alpha else 0.0
			if alpha <= 0.0:
				continue
			var c := colors[x].lerp(tint, clampf(k, 0.0, 1.0))
			c.a = alpha
			out.set_pixel(x, row, c)
	var origin := Vector2(at.x, at.y + top) / density
	var sprite := Sprite2D.new()
	sprite.name = String(spec["id"]) + "_submerged"
	sprite.centered = false
	sprite.texture = ImageTexture.create_from_image(out)
	sprite.position = origin
	sprite.scale = Vector2.ONE / density
	sprite.texture_filter = _kit_filter()
	sprite.material = _lit(origin, _depth_of(band), true, density)
	return sprite


func _make_piece(spec: Dictionary, band: String) -> Sprite2D:
	var image := kit.image(String(spec["file"]))
	if image == null or image.is_empty():
		return null
	image.convert(Image.FORMAT_RGBA8)
	_piece_images[String(spec["id"])] = image
	var at := Vector2(SceneKit._vec2i(spec["at"])) / density
	var sprite := Sprite2D.new()
	sprite.name = String(spec["id"])
	sprite.centered = false
	sprite.scale = Vector2.ONE / density
	sprite.texture_filter = _kit_filter()
	var kind := String(spec.get("kind", ""))
	var full := spec.duplicate()
	full["size"] = Vector2(image.get_size())
	var m: ShaderMaterial
	var parent := kit.piece(SceneKit.parent_of(spec))
	if SceneKit.bends(full) or (not parent.is_empty() and SceneKit.bends(parent)):
		var pad := ceili(float(tuning["sway"]["pad_px"]) * density)
		var padded := Image.create_empty(image.get_width() + pad * 2, image.get_height() + pad * 2, false, Image.FORMAT_RGBA8)
		padded.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i(pad, pad))
		sprite.texture = ImageTexture.create_from_image(padded)
		sprite.position = at - Vector2(pad, pad) / density
		m = _lit(at, _depth_of(band), kind == "lily", density)
		var pivot: Array = spec.get("pivot", [image.get_width() / 2, image.get_height()])
		m.set_shader_parameter("pad", float(pad))
		if SceneKit.bends(full):
			sway.add({"id": spec["id"], "kind": kind, "tree": spec.get("tree", ""), "sway": spec.get("sway", {}), "at": [at.x, at.y],
					"size": Vector2(image.get_size()) / density, "pivot": [float(pivot[0]) / density, float(pivot[1]) / density]})
			var tex := ImageTexture.create_from_image(sway.image_for(String(spec["id"])))
			_sway_textures[String(spec["id"])] = tex
			m.set_shader_parameter("sways", true)
			m.set_shader_parameter("sway_tex", tex)
			m.set_shader_parameter("sway_cols", float(sway.entries[String(spec["id"])]["cols"]))
		m.set_shader_parameter("piece_size", Vector2(image.get_size()))
		m.set_shader_parameter("pivot_y", float(pivot[1]))
		m.set_shader_parameter("bend_power", _bend_power(spec))
		m.set_shader_parameter("flutter", float(tuning["sway"]["flutter"].get(kind, 0.0)))
		if kind == "far_tree":
			var far := _far_type(spec)
			var shimmer: Dictionary = tuning["sway"]["far_tree"]["shimmer"]
			m.set_shader_parameter("shimmer", float(far["shimmer"]))
			m.set_shader_parameter("shimmer_calm", float(tuning["sway"]["far_tree"]["calm_wind"]))
			m.set_shader_parameter("shimmer_rate", float(shimmer["rate_hz"]))
			m.set_shader_parameter("shimmer_from", float(shimmer["from_h"]))
	else:
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.position = at
		m = _lit(at, _depth_of(band), kind == "lily", density)
	sprite.material = m
	_piece_materials[String(spec["id"])] = m
	return sprite




## Edge pieces bend with the piece they continue (kit `follows`): the parent's sway texture and
## shape go to the follower's shader, which takes the parent's bend where it stands and adds its
## own only away from the old frame (Skypatch issue 137).
func _link_followers() -> void:
	var frame := kit.frame_rect()
	var frame_pt := Vector4(frame.position.x, frame.position.y, frame.size.x, frame.size.y) / density
	for spec in kit.pieces:
		var parent_id := SceneKit.parent_of(spec)
		var m: ShaderMaterial = _piece_materials.get(String(spec["id"]))
		if parent_id == "" or m == null or not sway.entries.has(parent_id):
			continue
		var parent := kit.piece(parent_id)
		var image: Image = _piece_images[parent_id]
		var pivot: Array = parent.get("pivot", [image.get_width() / 2, image.get_height()])
		m.set_shader_parameter("follows", true)
		m.set_shader_parameter("follow_tex", _sway_textures[parent_id])
		m.set_shader_parameter("follow_delta", Vector2(SceneKit._vec2i(spec["at"]) - SceneKit._vec2i(parent["at"])))
		m.set_shader_parameter("follow_size", Vector2(image.get_size()))
		m.set_shader_parameter("follow_cols", float(sway.entries[parent_id]["cols"]))
		m.set_shader_parameter("follow_pivot_y", float(pivot[1]))
		m.set_shader_parameter("follow_power", _bend_power(parent))
		m.set_shader_parameter("frame_rect", frame_pt)
		m.set_shader_parameter("follow_ramp", float(tuning["edges"]["follow_ramp_pt"]))


## Puts the control strip in the window's top-right corner at `ui_scale` window units per point
## (the screen's scale, so the strip is one size at every scene size). `smallest`/`largest`: the
## scene is at that end of its sizes (that magnifier is greyed out).
func add_controls(controls_tuning: Dictionary, ui_scale: float, smallest: bool = false, largest: bool = true) -> SceneControls:
	controls = SceneControls.new()
	controls.ui_scale = ui_scale
	_place_controls()
	controls.setup(controls_tuning, self, hit, ui_scale, smallest, largest)
	add_child(controls)
	return controls


## The camera's viewfinder over the scene (closed until the strip's 📷 opens it).
func add_viewfinder(photo_tuning: Dictionary) -> SceneViewfinder:
	viewfinder = SceneViewfinder.new()
	viewfinder.setup(photo_tuning, self)
	add_child(viewfinder)
	return viewfinder


## The demo's morning card (issue 268) at the top of the window, hidden until `show_card`. Like the strip,
## drawn at `ui_scale` window units per point.
func add_demo_card(card_tuning: Dictionary, ui_scale: float) -> SceneDemoCard:
	demo_card = SceneDemoCard.new()
	demo_card.setup(card_tuning, self, hit, ui_scale)
	add_child(demo_card)
	return demo_card


## Mouse clear (issue 428): off until the scene is on top (`mouse_clear.set_on`), then a soft see-through circle
## follows the cursor over the window, drawn last. `ui_scale` window units per point, like the strip.
func add_mouse_clear(mouse_tuning: Dictionary, ui_scale: float) -> SceneMouseClear:
	mouse_clear = SceneMouseClear.new()
	mouse_clear.setup(mouse_tuning, self, hit, ui_scale)
	add_child(mouse_clear)
	return mouse_clear


## The letter card (issue 314), hidden until he unfolds a letter on the log. Drawn at `ui_scale` window units per point.
func add_letter_card(card_tuning: Dictionary, ui_scale: float) -> SceneLetterCard:
	letter_card = SceneLetterCard.new()
	letter_card.setup(card_tuning, self, hit, ui_scale)
	add_child(letter_card)
	return letter_card


## The look reading the letter (`AvatarLook.letter_sheet`), recoloured once, when a letter is first due.
func _load_letter() -> void:
	if _letter_ready or not sitter.ok:
		return
	_letter_ready = true
	if not sitter.letter_started.is_connected(_on_letter_started):
		sitter.letter_started.connect(_on_letter_started)
	sitter.use_letter(AvatarLook.letter_sheet(avatar_look) if not avatar_look.is_empty() else {})


## The look's seated activity sheets (issue 123: thermos, paperback, the looking-down heads, fidgets), recoloured
## once. `ground` stands the thermos beside the log at once: you were already sitting there (the app started with you
## on the log); arriving by the van, the unpack stands it there.
func _load_extras(ground: bool) -> void:
	if _extras_ready or not sitter.ok:
		return
	_extras_ready = true
	sitter.use_extras(AvatarLook.extra_sheets(avatar_look) if not avatar_look.is_empty() else {}, ground)


func _on_letter_started() -> void:
	letter_due = false
	letter_started.emit()


## The reader and the letter in the window's units (the click target while reading).
func letter_window_rect() -> Rect2:
	var r: Rect2 = shown_rect(world.get_global_transform().affine_inverse() * sitter.letter_rect_global())
	return Rect2(r.position * scale_px, r.size * scale_px)


## A click at `at` (window units) on the reader: the journal opens at the letter.
func click_letter(at: Vector2) -> bool:
	if not _letter_region or not letter_window_rect().has_point(at):
		return false
	letter_clicked.emit()
	return true


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT and click_letter(button.position):
		set_input_as_handled()


func _letter_step(dt: float) -> void:
	var present := van.here() and not sitter.standing()
	if present and sitter.away:
		sitter.sit_down()
	sitter.away = not present
	sitter.letter_due = letter_due
	sitter.letter_pending = letter_due and van.here() and not sitter.standing() and van.sitter_alpha >= 0.99
	var show := sitter.reading() and van.sitter_alpha >= 0.99
	if letter_card != null:
		letter_card.keep_clear = controls.strip_rect() if controls != null else Rect2()
		letter_card.step(dt, show and sitter.step_anim() in LETTER_OPEN_ANIMS, letter_window_rect() if show else letter_card.reader)
	if show == _letter_region:
		return
	_letter_region = show
	if show:
		hit.set_region(LETTER_REGION, letter_window_rect())
	else:
		hit.clear(LETTER_REGION)
	hit.apply(self)


func start() -> void:
	set_process(not manual)
	if not manual:
		Pace.start_moving()
		draws_always = true
	resume_drawing()


## The scene draws every frame once started (unless manual). Anything that switches the window to
## draw once (a photo's render, WindowChrome.redraw) must hand back through here, or the scene
## freezes on that frame (issue 176: the viewfinder stuck after the first photo).
func resume_drawing() -> void:
	resumed += 1
	if draws_always:
		RenderingServer.viewport_set_update_mode(get_viewport_rid(), RenderingServer.VIEWPORT_UPDATE_ALWAYS)
	else:
		WindowChrome.redraw(self)


func _process(delta: float) -> void:
	if manual:
		return
	var m := minute
	if clock_minute.is_valid():
		m = float(clock_minute.call())
	advance(minf(delta, 0.1), m)


## Moves everything on by `dt` seconds with the day at `minute_of_day`.
func advance(dt: float, minute_of_day: float) -> void:
	t += dt
	minute = minute_of_day
	env.step(dt, minute_of_day)
	if env.rain > 0.05:
		var taps := float(tuning["rain"]["patter_per_sec"]) * env.rain * dt
		var n := int(taps) + (1 if _rng.randf() < taps - floorf(taps) else 0)
		sway.patter(n, float(tuning["rain"]["patter_push"]), _rng)
	sway.step(dt, env)
	drops.step(dt, env)
	behaviour.step(dt)
	flights.step(dt)
	visitors.step(dt)
	var seen: Variant = visitors.focus()
	var near: Variant = behaviour.focus_near(sitter.seat, float(tuning["sitter"].get("near_pt", 130.0)))
	sitter.near = near
	sitter.interest = seen if seen != null else behaviour.focus()
	sitter.step(dt, env)
	_shelter_step(dt)
	van.step(dt, light_tint())
	golden_lean = van.golden
	_place_sitter()
	if not _extras_ready:
		_load_extras(van.here() and not sitter.standing() and van.sitter_alpha >= 0.99)
	_letter_step(dt)
	rain.step(t, dt, env, _on_drop)
	water_fx.step(t)
	fireflies.step(t, env)
	sky.step(t, env)
	if shading:
		_update_shared()
	if beacon != null:
		beacon.tick(t, visible)
	if sound != null:
		sound.step(dt)
		if sound.output == null:
			sound.queue_free()
			sound = null
	stepped.emit()


## The Sound switch (issue 413): on makes the engine (`SceneSound`) with the game's buses, or `output`
## (the off-screen render); off fades it out and lets go of every bus and stream. Off by default: until
## this is called with true, nothing is read, decoded or played.
func set_sound(on: bool, output: Object = null) -> void:
	if not on:
		if sound != null:
			sound.close()
		return
	if sound != null and not sound.closing:
		return
	if sound != null:
		sound.close(true)
		sound.queue_free()
	sound = SceneSound.new()
	if output == null:
		output = SoundBuses.new()
		sound.add_child(output)
	add_child(sound)
	# Its own dice from the scene's seed: a pinned seed in every run would play the same calls at the same times.
	sound.setup(self, tuning["sound"], output, _seed + 41)


func _on_drop(at: Vector2, layer: int) -> void:
	if is_water(at):
		if _rng.randf() < float(tuning["rain"]["ring_chance"][layer]):
			var rows := water_rows()
			var near := clampf((at.y - rows.x) / (rows.y - rows.x), 0.0, 1.0)
			water_fx.ring(at, _rng.randf_range(0.05, 0.3) * (0.5 + near * 1.5), 0.6 + 0.2 * float(layer))
	elif _rng.randf() < float(tuning["rain"]["splash_chance"]):
		rain.splash(at)


## The scene's colour of light right now: the time of day, dimmed and cooled by cloud and rain.
func light_tint() -> Color:
	var look_tint: Color = env.look["tint"]
	var l: Dictionary = tuning["light_weather"]
	var dim := 1.0 - float(l["cloud_dim"]) * pow(env.cloud, 1.3) - float(l["rain_dim"]) * env.rain
	var cool := Color.WHITE.lerp(Color(String(l["overcast_tint"])), clampf(env.cloud, 0.0, 1.0))
	var out := look_tint * cool
	if golden_lean > 0.0:
		var day: Dictionary = tuning["day"]
		out = out.lerp(out * Color(String(day["golden_tint"])), golden_lean * float(day["golden_strength"]))
	return Color(out.r * dim, out.g * dim, out.b * dim, 1.0)


func _update_shared() -> void:
	var step_pt := float(tuning["gust_column_px"])
	for i in _gust_image.get_width():
		_gust_image.set_pixel(i, 0, Color(env.gust_at(float(i) * step_pt), 0, 0))
	_gust_texture.update(_gust_image)
	for id in _sway_textures:
		(_sway_textures[id] as ImageTexture).update(sway.image_for(String(id)))
	var tint := light_tint()
	var day := env.daylight()
	var c := env.cloud
	var patchy := smoothstep(0.03, 0.3, c) * (1.0 - smoothstep(0.72, 0.98, c))
	var shadow := float(tuning["light_weather"]["shadow_strength"]) * day * patchy
	var look_tint: Color = env.look["tint"]
	var fog_color: Color = Color(String(tuning["sky"]["fog_color"])) * look_tint.lerp(Color.WHITE, 0.5)
	var under := kit.underwater_rect()
	under = Rect2(under.position / density, under.size / density)
	var rows := water_rows()
	var moon := 0.0 if env.moon_t < 0.0 else (1.0 - c) * 0.6
	var sky_cover := maxf(c, float(tuning["sky"].get("fair_clouds", 0.0)) * (1.0 - env.fog))
	var living: Dictionary = tuning["sky"].get("living", {})
	var reflect := float(living.get("reflect", 0.0)) * clampf(day + 0.15, 0.0, 1.0) * (1.0 - env.fog)
	var frame_r := frame_pt if frame_pt.has_area() else Rect2(Vector2.ZERO, size_pt)
	var frame_v := Vector4(frame_r.position.x, frame_r.position.y, frame_r.size.x, frame_r.size.y)
	var reflect_color := Color(String(tuning["sky"]["cloud_lit"]))
	var all := _materials.duplicate()
	all.append_array(visitors.materials)
	for i in all.size():
		if int((all[i] as ShaderMaterial).get_meta("edge_version", -1)) != _edge_version:
			_edge_material(all[i], i)
	for m: ShaderMaterial in all:
		m.set_shader_parameter("time", t)
		m.set_shader_parameter("tint", tint)
		m.set_shader_parameter("shadow_strength", shadow)
		m.set_shader_parameter("cloud_cover", c)
		m.set_shader_parameter("cloud_offset", env.cloud_offset)
		m.set_shader_parameter("cloud_time", env.cloud_time)
		m.set_shader_parameter("cloud_front", env.cloud_front)
		m.set_shader_parameter("sky_cover", sky_cover)
		m.set_shader_parameter("reflect_strength", reflect)
		m.set_shader_parameter("frame_rect", frame_v)
		m.set_shader_parameter("cloud_evolve", float(living.get("evolve", 1.0)))
		m.set_shader_parameter("front_gain", float(living.get("front_gain", 0.35)))
		m.set_shader_parameter("sky_horizon", float(tuning["sky"]["horizon_y"]))
		m.set_shader_parameter("reflect_stretch", float(living.get("reflect_stretch", 2.5)))
		m.set_shader_parameter("reflect_color", reflect_color)
		m.set_shader_parameter("fog", env.fog)
		m.set_shader_parameter("fog_color", fog_color)
		m.set_shader_parameter("wet", env.wet)
		m.set_shader_parameter("sunshine", env.sunshine())
		m.set_shader_parameter("moonlight", moon)
		m.set_shader_parameter("gust_tex", _gust_texture)
		m.set_shader_parameter("water_mask", _mask_texture)
		m.set_shader_parameter("scene_size", size_pt)
		m.set_shader_parameter("water_top", rows.x)
		m.set_shader_parameter("water_bottom", rows.y)
		m.set_shader_parameter("under_rect", Vector4(under.position.x, under.position.y, under.size.x, under.size.y))
		m.set_shader_parameter("wind_dir", env.wind.direction)
		m.set_shader_parameter("wind_mean", env.wind.mean)
		m.set_shader_parameter("rain", env.rain)
	for mist in _mists:
		var m: ShaderMaterial = mist["material"]
		var spec: Dictionary = mist["spec"]
		var amount := maxf(env.mist * float(spec["mist"]), env.fog * float(spec["fog"])) + env.rain * float(spec.get("rain", 0.0))
		m.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))
		m.set_shader_parameter("time", t)
		m.set_shader_parameter("drift", env.wind.direction * (float(spec["drift_px_per_sec"]) + env.wind.mean * 10.0))
		var mc: Color = Color(String(tuning["sky"]["mist_color"])) * look_tint.lerp(Color.WHITE, 0.35)
		mc.a = 1.0
		m.set_shader_parameter("color", mc)
	rain.tint = tint.lerp(Color.WHITE, 0.3)
	water_fx.tint = tint.lerp(Color.WHITE, 0.2)


func _exit_tree() -> void:
	if beacon != null:
		beacon.stop()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and beacon != null:
		beacon.tick(t, visible, true)


# --- Hooks (scene points) ---------------------------------------------------------------------

func actor_layer(band: String) -> Node2D:
	return _actors.get(band, _actors[kit.band_ids()[-1]] if _actors.has(kit.band_ids()[-1]) else _actors.values()[-1])


## Every perch: [{"piece", "at" (points), "band"}]. A perch the kit put in the air just above
## a stem or a branch is settled onto the first drawn pixel below it; one with nothing under it
## is left out (a bird would sit on nothing).
func perches() -> Array:
	if not _perches.is_empty():
		return _perches
	var reach := int(float(tuning["visitors"]["perch_settle_pt"]) * density)
	for perch in kit.perches():
		var p: Dictionary = perch.duplicate()
		var at: Vector2 = perch["at"]
		var image: Image = _piece_images.get(String(perch["piece"]))
		if image != null:
			var local := Vector2i(at) - SceneKit._vec2i(kit.piece(String(perch["piece"]))["at"])
			var found := -1
			for dy in reach:
				var q := local + Vector2i(0, dy)
				if q.x < 0 or q.y < 0 or q.x >= image.get_width() or q.y >= image.get_height():
					break
				if image.get_pixelv(q).a > 0.5:
					found = dy
					break
			if found < 0:
				continue
			at.y += float(found)
		p["at"] = at / density
		_perches.append(p)
	return _perches


## A piece's pixels (kit art px, the piece's own frame at its `at`), or null: for finding where
## something small can stand on it (a dragonfly on a lily pad).
func piece_image(piece_id: String) -> Image:
	return _piece_images.get(piece_id)


## A push on the piece at a perch: a landing (`push.y` > 0) dips it, a take-off lifts it.
func perch_impulse(piece_id: String, at: Vector2, push: Vector2) -> bool:
	return sway.impulse(piece_id, at, push)


## A bird's weight resting on a perch (`key` names the bird): the piece leans by `push` (points:
## sideways, down) while it sits, and springs back on `perch_release`.
func perch_hold(piece_id: String, key: String, at: Vector2, push: Vector2) -> bool:
	return sway.hold(piece_id, key, at, push)


func perch_release(piece_id: String, key: String) -> void:
	sway.release(piece_id, key)


## How far the piece has carried the perch at `at` from where it is drawn (points).
func perch_offset(piece_id: String, at: Vector2) -> Vector2:
	var spec := kit.piece(piece_id)
	if spec.is_empty() or not sway.entries.has(piece_id):
		return Vector2.ZERO
	var pivot := SceneKit.pivot_of(spec) / density
	var size := Vector2(SceneKit._vec2i(spec.get("size", [0, 0]))) / density
	var pivot_local := float(spec.get("pivot", [0, 1])[1]) / density
	var far_end := pivot_local if pivot_local > size.y * 0.5 else size.y - pivot_local
	var h := clampf(absf(pivot.y - at.y) / maxf(far_end, 1.0), 0.0, 1.0)
	return sway.bend_at(piece_id, at.x) * pow(h, _bend_power(spec))


## How a piece's bend grows toward its far end: by kind, or by type for a far tree.
func _bend_power(spec: Dictionary) -> float:
	var kind := String(spec.get("kind", ""))
	if kind == "far_tree":
		return float(_far_type(spec)["bend_power"])
	return float(tuning["sway"]["bend_power"].get(kind, tuning["sway"]["bend_power"]["default"]))


func _far_type(spec: Dictionary) -> Dictionary:
	var types: Dictionary = tuning["sway"]["far_tree"]
	return types.get(String(spec.get("tree", "")), types["broadleaf"])


## Zones of `kind` in points: [{id, kind, band, polygon|lane}].
func zones_of(kind: String) -> Array:
	return _zones.filter(func(z: Dictionary) -> bool: return String(z.get("kind", "")) == kind)


func in_zone(zone: Dictionary, point: Vector2) -> bool:
	return SceneKit.in_zone(zone, point)


## Whether `at` (points) is open water.
func is_water(at: Vector2) -> bool:
	var p := Vector2i((at * density).round())
	if p.x < 0 or p.y < 0 or p.x >= _mask_image.get_width() or p.y >= _mask_image.get_height():
		return false
	var c := _mask_image.get_pixelv(p)
	return c.a * maxf(c.r, maxf(c.g, c.b)) > 0.5


func ring(at: Vector2, size: float = 1.0, strength: float = 1.0, scale: float = 1.0) -> void:
	if edge_fade_keep(at) < 0.5:
		return
	water_fx.ring(at, size, strength, scale)


func splash(at: Vector2, size: float = 1.0, scale: float = 1.0) -> void:
	if edge_fade_keep(at) < 0.5:
		return
	water_fx.splash(at, size, scale)


func wake(at: Vector2, velocity: Vector2, scale: float = 1.0) -> void:
	if edge_fade_keep(at) < 0.5:
		return
	water_fx.wake(at, velocity, scale)


## Stops the director sending animals (clips that script their own, tests).
func set_random_visits(on: bool) -> void:
	_visits = on
	behaviour.on = on


## How much of the game's own painting (sky, rain) is left at `at` (points): 1 in the frame, falling
## to 0 across the margin where the sky ends (`SceneSkyEdge`; smooth here, the sky dithers it).
func edge_keep(at: Vector2) -> float:
	return sky_edge.keep(at, env.cloud_offset.x if env != null else 0.0) * edge_fade_keep(at)


## Every plate and piece of the kit composed where it stands, for where the margin has art.
func _margin_art() -> Image:
	var art := Image.create(kit.size.x, kit.size.y, false, Image.FORMAT_RGBA8)
	for item in kit.draw_order():
		var spec: Dictionary = item["spec"]
		var img := kit.image(String(spec["file"]))
		if img == null or img.is_empty():
			continue
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		var at: Array = spec.get("at", [0, 0])
		art.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(int(at[0]), int(at[1])))
	return art


## How far a piece has carried the point `at` of it from where it is drawn (points): its own bend
## and, for an edge piece, the bend of the piece it continues (as the shader moves it).
func piece_offset(piece_id: String, at: Vector2) -> Vector2:
	var spec := kit.piece(piece_id)
	var parent := SceneKit.parent_of(spec)
	if parent == "" or not sway.entries.has(parent):
		return perch_offset(piece_id, at)
	var outside := maxf(maxf(frame_pt.position.x - at.x, frame_pt.position.y - at.y), maxf(at.x - frame_pt.end.x, at.y - frame_pt.end.y))
	var ramp := smoothstep(0.0, float(tuning["edges"]["follow_ramp_pt"]), maxf(outside, 0.0))
	return perch_offset(parent, at) + perch_offset(piece_id, at) * ramp


func art_to_screen(point: Vector2) -> Vector2:
	return Vector2(position) + shown(point) * scale_px


## Draws the picture mirrored or as made (Config's own switch since issue 424, in any corner).
func set_mirrored(on: bool) -> void:
	set_corner(corner, on)


## The corner the window holds and whether the picture is mirrored (issue 424): the two edges against the
## screen are straight (a grown margin there is cut off: the window shows the frame's own edge), the two
## open ones dissolve. The window takes the view's size; everything goes on where it is.
func set_corner(corner_name: String, mirror: bool) -> void:
	var name := corner_name if corner_name in ["bottom_right", "bottom_left", "top_left", "top_right"] else "bottom_right"
	if name == corner and mirror == mirrored and view_pt.has_area():
		return
	corner = name
	mirrored = mirror
	var frame := frame_pt if frame_pt.has_area() else Rect2(Vector2.ZERO, size_pt)
	var lo := Vector2(frame.position.x if world_left_flush() else 0.0, frame.position.y if on_top() else 0.0)
	var hi := Vector2(size_pt.x if world_left_flush() else frame.end.x, size_pt.y if on_top() else frame.end.y)
	view_pt = Rect2(lo, hi - lo)
	_apply_edges()
	flights.rescale()
	if viewfinder != null:
		viewfinder.cancel()
	if is_inside_tree() or size != Vector2i.ZERO:
		_refit(controls.smallest if controls != null else false, controls.largest if controls != null else true)


## The window holds a top corner of the screen.
func on_top() -> bool:
	return corner.begins_with("top")


## The window holds a left corner of the screen.
func on_left() -> bool:
	return corner.ends_with("left")


## The world's left side is the one against the screen (the window's left, or its right while mirrored).
func world_left_flush() -> bool:
	return on_left() != mirrored


func _apply_view() -> void:
	var s := absf(world.scale.y)
	world.scale.x = -s if mirrored else s
	world.position = Vector2(view_pt.end.x * s if mirrored else -view_pt.position.x * s, -view_pt.position.y * s)


## The strip in the window's top corner on the screen's side, below an open top's margin, so it sits on the art.
func _place_controls() -> void:
	if controls == null:
		return
	controls.left = on_left()
	var top_margin := frame_pt.position.y - view_pt.position.y if frame_pt.has_area() else 0.0
	controls.top_inset_pt = maxf(top_margin, 0.0) * scale_px / maxf(controls.ui_scale, 0.01)


## The open edges (issue 424): the side and bottom bands' dissolve (`SceneEdgeFade`) on every lit layer (each
## its own threshold), the sky's sides (one outline with the ground), the mist and the animals' sheets. An open
## top is the sky's own dissolve, the canopy deciding the corner, as before.
func _apply_edges() -> void:
	var fade: Dictionary = tuning["edges"]["fade"]
	edge_fade.band = Vector2(float(fade["right_pt"]) if world_left_flush() else 0.0, float(fade["bottom_pt"]) if on_top() else 0.0)
	edge_fade.left = 0.0 if world_left_flush() else float(fade["left_pt"])
	_edge_version += 1
	var all := _materials.duplicate()
	all.append_array(visitors.materials)
	for i in all.size():
		_edge_material(all[i], i)
	if sky.get_parent() != null or kit != null:
		sky._param("fade_right_pt", edge_fade.band.x)
		sky._param("fade_left_pt", edge_fade.left)
		sky._param("fade_profile", edge_fade.profile_texture())
		sky._param("fade_period", float(SceneSkyEdge.PERIOD))
	for mist in _mists:
		(mist["material"] as ShaderMaterial).set_shader_parameter("fade_band", edge_fade.band)
		(mist["material"] as ShaderMaterial).set_shader_parameter("fade_left_band", edge_fade.left)
	SceneSheet.fade_world = world
	SceneSheet.fade_edges = Vector4(edge_fade.left, edge_fade.band.x, edge_fade.band.y, size_pt.x)
	SceneSheet.fade_h = size_pt.y
	SceneSheet.fade_soft = SceneSkyEdge._pair(fade.get("life", [0.3, 0.85]))


func _edge_material(m: ShaderMaterial, i: int) -> void:
	m.set_shader_parameter("fade_band", edge_fade.band)
	m.set_shader_parameter("fade_left", edge_fade.left)
	m.set_shader_parameter("fade_profile", edge_fade.profile_texture())
	m.set_shader_parameter("fade_period", float(SceneSkyEdge.PERIOD))
	m.set_shader_parameter("fade_seed", fposmod(float(i) * 0.6180339, 1.0))
	m.set_meta("edge_version", _edge_version)


## How much of the art is left at `at` (points) by the open edges' dissolve (smooth; the shader dithers it):
## rings, splashes and wakes are thrown only where the water is still drawn.
func edge_fade_keep(at: Vector2) -> float:
	return edge_fade.keep(at)


## A world point as the window shows it (points), and back.
func shown(at: Vector2) -> Vector2:
	return Vector2(view_pt.end.x - at.x, at.y - view_pt.position.y) if mirrored else at - view_pt.position


func unshown(at: Vector2) -> Vector2:
	return Vector2(view_pt.end.x - at.x, at.y + view_pt.position.y) if mirrored else at + view_pt.position


func shown_rect(r: Rect2) -> Rect2:
	if mirrored:
		return Rect2(view_pt.end.x - r.end.x, r.position.y - view_pt.position.y, r.size.x, r.size.y)
	return Rect2(r.position - view_pt.position, r.size)


func unshown_rect(r: Rect2) -> Rect2:
	if mirrored:
		return Rect2(view_pt.end.x - r.end.x, r.position.y + view_pt.position.y, r.size.x, r.size.y)
	return Rect2(r.position + view_pt.position, r.size)


## -1 while mirrored: a facing or a velocity's x in the world is the other way on screen.
func shown_sign() -> float:
	return -1.0 if mirrored else 1.0


## What a photo is cut from: the full-size render at the in-between sizes (sharper than the shrunk
## window), else the window's own. Its units per point are `photo_scale()`.
func photo_texture() -> Texture2D:
	return shrink.viewport.get_texture() if shrink != null else get_texture()


func photo_scale() -> float:
	return render_scale


## Window units per drawn unit: 1, or under 1 at the in-between sizes.
func shown_ratio() -> float:
	return scale_px / render_scale


## What `DailyRhythm` decided (issue 198): the van and the avatar play it; at the wrap-up he stands and stretches.
func day(what: String) -> void:
	if what in ["arrive", "arrive_first", "leave", "invite", "stay"]:
		_load_day()
	van.dark = SceneVan.lamps_due(tuning["day"]["lamps"], env.light.day_phases, float(clock_minute.call()) if clock_minute.is_valid() else minute)
	van.play(what)
	if what == "invite" and not van.walks():
		sitter.rouse()
		sitter._start("stretch")
	_place_sitter()


## Real rain sends you to shelter in the van and you come back once it is over (issue 476, `SceneShelter`). Only
## while the van is parked with you seated (never mid-letter or mid-pour, never during the first run's welcome);
## whenever the rhythm moves the van, the count starts over.
func _shelter_step(dt: float) -> void:
	if shelter == null:
		return
	if not (van.state in ["parked", "sheltering", "sheltered", "returning"]) or van.hold_at >= 0.0:
		shelter.reset()
		return
	if shelter.inside and van.state == "parked":
		shelter.reset()
	var can_go := van.can_shelter() and not sitter.standing() and not (sitter.mode in ["thermos", "letter"])
	match shelter.step(dt, env.rain, can_go, van.can_unshelter()):
		"go":
			_load_day()
			van.dark = SceneVan.lamps_due(tuning["day"]["lamps"], env.light.day_phases, minute)
			van.shelter()
		"back":
			van.unshelter()


## The first run's welcome is done (issue 199): you walk on from the van's door to the log and sit.
func release_first() -> void:
	_load_day()
	van.release()
	_place_sitter()


## A new look (the picker): its day actions are baked again the next time the route plays. While you wait at
## the van's door (the welcome), you are shown in the new look at once.
func use_look(look: Dictionary) -> void:
	avatar_look = look
	_day_ready = false
	var had_letter := _letter_ready
	_letter_ready = false
	if had_letter:
		_load_letter()
	if _extras_ready:
		_extras_ready = false
		_load_extras(sitter.thermos_down)
	if van.hold_at >= 0.0:
		_load_day()
		van.rehold()
		_place_sitter()


## The look's day actions, recoloured once (`AvatarLook.day_sheets`; {} for a look without them, which fades).
func _load_day() -> void:
	if _day_ready:
		return
	_day_ready = true
	var sheets := AvatarLook.day_sheets(avatar_look) if not avatar_look.is_empty() else {}
	sitter.use_day(sheets)
	van.use_day(sheets, sitter.feet_pt())


## You on the log (faded by the van's alpha) or standing and walking near it (`van.near`).
func _place_sitter() -> void:
	sitter.stand(van.near)
	sitter.modulate.a = 1.0 if sitter.standing() else van.sitter_alpha


func debug_actions() -> Array:
	var out: Array = []
	for phase in env.weather.order():
		out.append(["Weather: " + String(phase), func() -> void: env.force_weather(String(phase), false)])
	out.append(["Gust now", func() -> void: env.wind.spawn_gust(1.1)])
	out.append(["Mist on/off", func() -> void:
		if env.overrides.has("mist"):
			env.overrides.erase("mist")
		else:
			env.overrides["mist"] = 0.8])
	out.append(["Fog on/off", func() -> void:
		if env.overrides.has("fog"):
			env.overrides.erase("fog")
		else:
			env.overrides["fog"] = 0.7])
	out.append(["A bird lands", func() -> void:
		var options := perches()
		if not options.is_empty():
			visitors.visit(String(tuning["visitors"]["species"][0]), options[_rng.randi() % options.size()])])
	out.append(["Avatar dozes (drowsy where the seat does not support it)", func() -> void: sitter._start("doze")])
	for kind in ["out_back", "out", "in"]:
		out.append(["Desktop flight: " + kind, func() -> void: flights.start(kind)])
	out.append_array(flights.debug_actions())
	out.append_array(behaviour.debug_actions())
	return out
