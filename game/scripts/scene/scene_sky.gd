class_name SceneSky
extends Node2D

## The sky the game draws behind the kit (contract §7): a whole sky by the time of day with its
## clouds (a shader on `glow`, Skypatch issue 112), and here the sun crossing the day and sinking behind the trees, the moon
## across the night, and stars that come out with the dark and twinkle. Clouds hide them.
##
## In a kit that grew past its frame (Skypatch issue 137)
## the node sits at the frame's top-left, so every tuned row and column is the frame's as before; the
## sky reaches out under the margin art and dissolves across it into the desktop, by a wandering
## ordered dither, so its end never sits on a line.

var tuning: Dictionary = {}
var glow := ColorRect.new()
## The clouds again in front of the sun, the moon and the stars this node draws (issue 380): the same
## shader with `clouds_only`, so a cloud passes in front of the sun, never behind it.
var cover := ColorRect.new()
var _material := ShaderMaterial.new()
var _stars: Array = []
var _env: SceneEnvironment
var _t := 0.0
var _fade := 0.0
## How much sky is left at a scene point (points), set by the scene: 1 in the frame, 0 past the dissolve.
var edge_keep: Callable = func(_at: Vector2) -> float: return 1.0
## Where the sky ends in the margin (set before `setup`; without one, a profile with no kit seed and no cover).
var edge_shape: SceneSkyEdge
## The frame's size (points), for where across it a front has reached.
var _frame_size := Vector2.ONE
## The cover now, scene-wide (as the shader is given it).
var _cover := 0.0


## `size` is the whole scene; `frame` the old composition inside it (points; empty: all of it).
func setup(size: Vector2, sky_tuning: Dictionary, seed: int, art_px_per_pt: float = 1.0, frame := Rect2()) -> void:
	tuning = sky_tuning
	name = "Sky"
	if not frame.has_area():
		frame = Rect2(Vector2.ZERO, size)
	position = frame.position
	_frame_size = frame.size
	_fade = float(sky_tuning["fade_left_px"])
	var rows := int(sky_tuning["glow_rows"])
	glow.name = "Glow"
	glow.position = -frame.position
	glow.size = Vector2(size.x, rows + frame.position.y)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# The sky is opaque now: the stars, moon and sun this node draws go in front of it.
	glow.show_behind_parent = true
	_material.shader = preload("res://scripts/scene/scene_sky.gdshader")
	_material.set_shader_parameter("size", glow.size)
	_material.set_shader_parameter("horizon_y", float(sky_tuning["horizon_y"]))
	_material.set_shader_parameter("fade_left", _fade)
	_material.set_shader_parameter("px", art_px_per_pt)
	_material.set_shader_parameter("sky_alpha", float(sky_tuning.get("sky_alpha", 1.0)))
	_material.set_shader_parameter("frame_origin", frame.position)
	_material.set_shader_parameter("frame_size", frame.size)
	_material.set_shader_parameter("margins", Vector4(frame.position.x, frame.position.y,
			size.x - frame.end.x, size.y - frame.end.y))
	var dissolve: Dictionary = sky_tuning.get("dissolve", {})
	if edge_shape == null:
		edge_shape = SceneSkyEdge.new()
		edge_shape.setup(size, frame, dissolve, "")
	_material.set_shader_parameter("scene_size", size)
	_material.set_shader_parameter("edge_profile", edge_shape.profile_texture())
	_material.set_shader_parameter("edge_cover", edge_shape.cover_texture())
	_material.set_shader_parameter("edge_period", float(SceneSkyEdge.PERIOD))
	_material.set_shader_parameter("dissolve_wobble", float(dissolve.get("wobble", 0.06)))
	_material.set_shader_parameter("dissolve_wobble_pt", float(dissolve.get("wobble_pt", 14.0)))
	_material.set_shader_parameter("dissolve_cloud_carry", float(dissolve.get("cloud_carry", 0.25)))
	_material.set_shader_parameter("dissolve_cover", edge_shape.cover_band)
	_material.set_shader_parameter("dissolve_pale", float(dissolve.get("pale", 0.0)))
	_material.set_shader_parameter("dissolve_below_pt", float(dissolve.get("below_pt", 20.0)))
	_material.set_shader_parameter("dissolve_dark_overcast", float(dissolve.get("dark_overcast", 0.0)))
	var living: Dictionary = sky_tuning.get("living", {})
	_material.set_shader_parameter("cloud_evolve", float(living.get("evolve", 1.0)))
	_material.set_shader_parameter("cirrus_cut", float(living.get("cirrus_cut", 0.6)))
	_material.set_shader_parameter("front_gain", float(living.get("front_gain", 0.35)))
	_material.set_shader_parameter("cloud_heavy", float(living.get("heavy", 0.3)))
	glow.material = _material
	add_child(glow)
	cover.name = "CloudCover"
	cover.position = glow.position
	cover.size = glow.size
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cm := _material.duplicate() as ShaderMaterial
	cm.set_shader_parameter("clouds_only", true)
	cover.material = cm
	add_child(cover)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var star_rows: Array = sky_tuning["star_rows"]
	for i in int(sky_tuning["stars"]):
		_stars.append({
			"at": Vector2(rng.randi_range(int(_fade - frame.position.x), int(frame.size.x) - 4),
					rng.randi_range(int(float(star_rows[0]) - frame.position.y), int(star_rows[1]))),
			"needs": rng.randf(), "thin": rng.randf(), "big": rng.randf() < 0.12, "phase": rng.randf() * TAU, "rate": rng.randf_range(0.6, 2.2)})


## A shader parameter on the sky and on the clouds over the sun alike.
func _param(key: String, value: Variant) -> void:
	_material.set_shader_parameter(key, value)
	(cover.material as ShaderMaterial).set_shader_parameter(key, value)


func step(t: float, env: SceneEnvironment) -> void:
	_t = t
	_env = env
	var look := env.look
	_param("glow_low", look["glow_low"])
	_param("glow_high", look["glow_high"])
	_param("glow", float(look["glow"]))
	# Fair-weather clouds: a clear day still has a few, drifting (the ground's shadows stay as they were).
	_cover = maxf(env.cloud, float(tuning.get("fair_clouds", 0.0)) * (1.0 - env.fog))
	_param("cloud_cover", _cover)
	_param("cloud_offset", env.cloud_offset)
	# The living clouds (Skypatch issue 146): shapes that change,
	# cirrus high up in fair weather, a front that comes from upwind.
	var living: Dictionary = tuning.get("living", {})
	_param("cloud_time", env.cloud_time)
	_param("high_offset", env.high_offset)
	_param("cirrus", float(living.get("cirrus", 0.0)) * (1.0 - smoothstep(0.45, 0.85, env.cloud)) * (1.0 - env.fog))
	_param("front", env.cloud_front)
	_param("wind_dir", env.wind.direction)
	_param("edge_shift", env.cloud_offset.x * edge_shape.drift)
	var day := env.daylight()
	var overcast := clampf((env.cloud - 0.35) / 0.65, 0.0, 1.0) * float(tuning["overcast_veil"]) * (0.35 + 0.65 * day)
	_param("overcast_strength", overcast)
	var tint: Color = look["tint"]
	var low: Color = look["glow_low"]
	var lit := Color(String(tuning["cloud_lit"])).lerp(low, clampf(float(look["glow"]), 0.0, 1.0) * 0.7) * tint
	lit.a = 1.0
	var dark := Color(String(tuning["cloud_dark"])) * tint
	dark.a = 1.0
	_param("cloud_lit", lit)
	_param("cloud_dark", dark)
	var over := Color(String(tuning["overcast"])) * Color(tint.r, tint.g, tint.b).lerp(Color.WHITE, 0.4)
	over.a = 1.0
	_param("overcast", over)
	_param("fog", env.fog)
	_param("fog_color", Color(String(tuning["fog_color"])) * tint.lerp(Color.WHITE, 0.5))
	_glow_through(env)
	_deck(env)
	queue_redraw()


## The rain's cloud line (issue 477): the deck's settings, and its underside for the rain.
func _deck(env: SceneEnvironment) -> void:
	var d: Dictionary = tuning.get("rain_deck", {})
	if d.is_empty():
		return
	var base: Array = d["base_pt"]
	var cover: Array = d["cover"]
	var tint: Color = env.look["tint"]
	_param("deck_cover", Vector2(float(cover[0]), float(cover[1])))
	_param("deck_base_pt", lerpf(float(base[0]), float(base[1]), env.rain))
	_param("deck_lump_pt", float(d["lump_pt"]))
	_param("deck_lump_wave_pt", float(d["lump_wave_pt"]))
	_param("deck_soft_pt", float(d["soft_pt"]))
	_param("deck_dense", float(d["dense"]))
	_param("deck_layers", float(d["layers"]))
	_param("deck_mix", float(d["mix"]))
	var dark := Color(String(d["dark"])) * tint
	var mid := Color(String(d["mid"])) * tint
	dark.a = 1.0
	mid.a = 1.0
	_param("deck_dark", dark)
	_param("deck_mid", mid)


## Where the deck's underside is above world x `x` (points; rows from the frame's top), without its
## lumps: 0 where there is no deck. The same sum as the shader's.
func deck_base(x: float, env: SceneEnvironment) -> float:
	var d: Dictionary = tuning.get("rain_deck", {})
	if env == null or d.is_empty():
		return 0.0
	var base: Array = d["base_pt"]
	var cover: Array = d["cover"]
	var x01 := (x - position.x) / _frame_size.x
	var upwind := (0.5 - x01) * (-1.0 if env.wind.direction < 0.0 else 1.0)
	var gain := float(tuning.get("living", {}).get("front_gain", 0.35))
	var here := clampf(_cover + env.cloud_front * gain * upwind * 2.0, 0.0, 1.0)
	return lerpf(float(base[0]), float(base[1]), env.rain) * smoothstep(float(cover[0]), float(cover[1]), here)


## How far the deck's lumps reach either side of its underside (points).
func deck_lump() -> float:
	return float(tuning.get("rain_deck", {}).get("lump_pt", 0.0))


## The sun as drawn (in this node's points): x, y, radius, and how strongly it shows (0: not in the window).
## The pond is faced westward (the human, issue 380): the morning sun rises behind the viewer and is
## never in the window before noon; the afternoon's sinks into the trees ahead.
func sun_disc(env: SceneEnvironment) -> Vector4:
	if env == null or env.sun_t < 0.5 or not bool(tuning.get("draw_sun", false)):
		return Vector4.ZERO
	var sx: Array = tuning["sun_x"]
	var at := Vector2(lerpf(float(sx[0]), float(sx[1]), env.sun_t),
			float(tuning["horizon_y"]) + float(tuning["sun_sink_px"]) - sin(PI * env.sun_t) * float(tuning["sun_arc_px"])).round()
	var r := float(tuning["sun_r_px"]) * (1.25 if sun_low(env) else 1.0)
	var a := clampf(1.0 - env.cloud * 1.1, 0.0, 1.0) * (1.0 - env.fog * 0.7)
	# Climbing out of the window's top it fades rather than being cut off by the edge.
	a *= clampf((at.y - r - 4.0) / 30.0, 0.0, 1.0)
	return Vector4(at.x, at.y, r, a)


func sun_low(env: SceneEnvironment) -> bool:
	return env.sun_t < 0.1 or env.sun_t > 0.86


## The moon as drawn: x, y, radius, and how strongly it shows (0 by day).
func moon_disc(env: SceneEnvironment) -> Vector4:
	if env == null or env.moon_t < 0.0:
		return Vector4.ZERO
	var mx: Array = tuning["moon_x"]
	var at := Vector2(lerpf(float(mx[0]), float(mx[1]), env.moon_t),
			float(tuning["horizon_y"]) - sin(PI * env.moon_t) * float(tuning["moon_arc_px"])).round()
	var clear := 1.0 - clampf(env.cloud * 1.15, 0.0, 1.0)
	return Vector4(at.x, at.y, float(tuning["moon_r_px"]), clampf(clear + 0.25, 0.0, 1.0) * (1.0 - env.fog * 0.8))


## The light through the clouds in front of the sun and the moon (issue 472): where a cloud's thin
## edge crosses a disc a faint glow shows through, and its rim brightens near it; its thick body
## still hides the disc. Only the cover gets it: the clouds behind them are never seen over them.
func _glow_through(env: SceneEnvironment) -> void:
	var g: Dictionary = tuning.get("glow_through", {})
	var cm := cover.material as ShaderMaterial
	var sun := sun_disc(env)
	var moon := moon_disc(env)
	sun.w *= float(g.get("sun", 0.0))
	moon.w *= float(g.get("moon", 0.0))
	var low := env.sun_t >= 0.0 and sun_low(env)
	cm.set_shader_parameter("sun_disc", sun)
	cm.set_shader_parameter("sun_light", Color(String(g.get("sun_low_color" if low else "sun_color", "fff8ec"))))
	cm.set_shader_parameter("moon_disc", moon)
	cm.set_shader_parameter("moon_light", Color(String(g.get("moon_color", "eef4f0"))))
	cm.set_shader_parameter("glow_disc", float(g.get("disc", 0.5)))
	cm.set_shader_parameter("glow_rim", float(g.get("rim", 0.35)))
	cm.set_shader_parameter("glow_reach", float(g.get("reach", 1.5)))
	cm.set_shader_parameter("glow_thin", float(g.get("thin", 0.12)))


func _draw() -> void:
	if _env == null:
		return
	var clear := 1.0 - clampf(_env.cloud * 1.15, 0.0, 1.0)
	var stars := float(_env.look.get("stars", 0.0)) * clear * (1.0 - _env.fog)
	if stars > 0.03:
		for star in _stars:
			if float(star["needs"]) > stars:
				continue
			# In the margin the stars thin out with the sky: fewer, then fainter, then none.
			var keep := float(edge_keep.call((star["at"] as Vector2) + position))
			if float(star["thin"]) > keep:
				continue
			var twinkle := 0.55 + 0.45 * sin(_t * float(star["rate"]) + float(star["phase"]))
			var color := Color("fbff86") if bool(star["big"]) else Color("ffffff")
			color.a = twinkle * clampf((stars - float(star["needs"])) * 4.0, 0.0, 1.0) * clampf(keep * 1.5, 0.0, 1.0)
			var at: Vector2 = star["at"]
			draw_rect(Rect2(at, Vector2.ONE), color)
			if bool(star["big"]) and twinkle > 0.8:
				draw_rect(Rect2(at + Vector2(-1, 0), Vector2(3, 1)), Color(color, color.a * 0.5))
				draw_rect(Rect2(at + Vector2(0, -1), Vector2(1, 3)), Color(color, color.a * 0.5))
	var moon := moon_disc(_env)
	if moon.w > 0.0:
		var at := Vector2(moon.x, moon.y)
		var r := moon.z
		var a := moon.w
		draw_circle(at, r, Color(Color("c7dcd0"), a))
		draw_circle(at + Vector2(-2, -2), r * 0.7, Color(Color("ffffff"), a))
		draw_circle(at + Vector2(3, 2), 2.0, Color(Color("9babb2"), a))
		draw_circle(at + Vector2(-3, 3), 1.5, Color(Color("9babb2"), a))
	# The sun low in the sky, glowing through the trees; high up it has climbed out of the window.
	var sun := sun_disc(_env)
	if sun.w > 0.02:
		var low := sun_low(_env)
		var at := Vector2(sun.x, sun.y)
		var r := sun.z
		var a := sun.w
		draw_circle(at, r + 3.0, Color(Color("fbff86") if not low else Color("f79617"), a * 0.25))
		draw_circle(at, r, Color(Color("fb6b1d") if low else Color("f9c22b"), a))
		draw_circle(at + Vector2(-r * 0.2, -r * 0.2), r * 0.6, Color(Color("f79617") if low else Color("fbff86"), a))
