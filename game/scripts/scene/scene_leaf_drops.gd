class_name SceneLeafDrops
extends RefCounted

## Single leaves at the scene's margin that a gust now and then pulls off (kit `drop`,
## Skypatch issue 137). The leaf leaves its piece where
## the wind has carried it, swings down on the wind like a falling leaf (side to side, flipping
## over as it turns), and dissolves after a short fall; minutes later it grows back through an
## ordered dither, so the crown never thins out for good. Rare: only in a gust strong enough, with
## a long gap between two falls and only one in the air at a time. Pixel art: the falling leaf is
## the piece's own pixels, never rotated, on whole art px.

var scene: LivingScene
var tuning: Dictionary = {}
## {id, spec, band, material, image, state ("on", "falling", "gone", "regrowing"), until, ...}
var leaves: Array = []
var _rng := RandomNumberGenerator.new()
var _since := 0.0
var t := 0.0


func setup(owner: LivingScene, drop_tuning: Dictionary, seed: int) -> void:
	scene = owner
	tuning = drop_tuning
	_rng.seed = seed
	_since = float(tuning["first_after_sec"])
	for spec in scene.kit.pieces:
		var id := String(spec["id"])
		if not SceneKit.drops(spec) or not scene._piece_materials.has(id):
			continue
		leaves.append({"id": id, "spec": spec, "band": String(spec.get("band", "")), "material": scene._piece_materials[id],
				"image": scene.piece_image(id), "state": "on", "until": 0.0})


func falling() -> Array:
	return leaves.filter(func(l: Dictionary) -> bool: return String(l["state"]) == "falling")


func step(dt: float, env: SceneEnvironment) -> void:
	t += dt
	_since += dt
	for leaf in leaves:
		match String(leaf["state"]):
			"falling":
				_fall(leaf, dt, env)
			"gone":
				if t >= float(leaf["until"]):
					leaf["state"] = "regrowing"
					leaf["until"] = t + float(tuning["regrow_fade_sec"])
			"regrowing":
				var k := 1.0 - (float(leaf["until"]) - t) / float(tuning["regrow_fade_sec"])
				(leaf["material"] as ShaderMaterial).set_shader_parameter("reveal", clampf(k, 0.0, 1.0))
				if k >= 1.0:
					leaf["state"] = "on"
	if _since < float(tuning["min_gap_sec"]) or falling().size() >= int(tuning["max_falling"]):
		return
	if env.rain > 0.5:
		return
	var rate := float(tuning["per_min_in_gust"]) / 60.0 * dt
	for leaf in leaves:
		if String(leaf["state"]) != "on":
			continue
		var at := _pivot(leaf)
		var g := env.gust_at(at.x)
		if g < float(tuning["min_gust"]):
			continue
		if _rng.randf() < rate * clampf(g, 0.0, 1.5):
			drop(String(leaf["id"]))
			return


## Lets `id` fall now (the clips and the debug panel call it too). False if it is not on its piece.
func drop(id: String) -> bool:
	for leaf in leaves:
		if String(leaf["id"]) != id or String(leaf["state"]) != "on":
			continue
		var image: Image = leaf["image"]
		if image == null:
			return false
		var at := Vector2(SceneKit._vec2i(leaf["spec"]["at"])) / scene.density
		var carried := scene.piece_offset(id, _pivot(leaf))
		var sprite := Sprite2D.new()
		sprite.name = id + "_falling"
		sprite.centered = false
		sprite.texture = ImageTexture.create_from_image(image)
		sprite.scale = Vector2.ONE / scene.density
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if scene.kit.is_pixel() else CanvasItem.TEXTURE_FILTER_LINEAR
		var m := scene._lit(at, scene._depth_of(String(leaf["band"])), false, scene.density)
		sprite.material = m
		var host: Node2D = scene._bands.get(String(leaf["band"]))
		if host == null:
			return false
		host.add_child(sprite)
		(leaf["material"] as ShaderMaterial).set_shader_parameter("reveal", 0.0)
		var fall: Array = tuning["fall_pt"]
		var speed: Array = tuning["speed_pt_per_sec"]
		leaf["state"] = "falling"
		leaf["sprite"] = sprite
		leaf["fall_material"] = m
		leaf["home"] = at + carried
		leaf["pos"] = at + carried
		leaf["drift"] = 0.0
		leaf["age"] = 0.0
		leaf["phase"] = _rng.randf() * TAU
		leaf["swing_hz"] = float(tuning["swing_hz"]) * _rng.randf_range(0.8, 1.25)
		leaf["fall_to"] = _rng.randf_range(float(fall[0]), float(fall[1]))
		leaf["speed"] = _rng.randf_range(float(speed[0]), float(speed[1]))
		leaf["fade"] = -1.0
		_since = 0.0
		_place(leaf)
		return true
	return false


func _fall(leaf: Dictionary, dt: float, env: SceneEnvironment) -> void:
	leaf["age"] = float(leaf["age"]) + dt
	var age := float(leaf["age"])
	var pos: Vector2 = leaf["pos"]
	# It starts from rest, then swings down: fastest through the bottom of each swing, almost
	# stopping and lifting a little at each end, carried downwind as it goes.
	var start := clampf(age / 0.6, 0.0, 1.0)
	var swing := sin(age * TAU * float(leaf["swing_hz"]) + float(leaf["phase"]))
	var down := float(leaf["speed"]) * start * (0.35 + 0.65 * absf(cos(age * TAU * float(leaf["swing_hz"]) + float(leaf["phase"]))))
	leaf["drift"] = float(leaf["drift"]) + env.wind_at(pos.x) * float(tuning["drift_pt_per_wind"]) * dt
	pos.y += down * dt
	leaf["pos"] = pos
	leaf["swing"] = swing * float(tuning["swing_pt"]) * start
	var sprite: Sprite2D = leaf["sprite"]
	# A leaf turning over at the end of each swing.
	sprite.flip_h = cos(age * TAU * float(leaf["swing_hz"]) + float(leaf["phase"])) < 0.0
	if float(leaf["fade"]) < 0.0 and pos.y - (leaf["home"] as Vector2).y >= float(leaf["fall_to"]):
		leaf["fade"] = age
	if float(leaf["fade"]) >= 0.0:
		var k := 1.0 - (age - float(leaf["fade"])) / float(tuning["fade_sec"])
		(leaf["fall_material"] as ShaderMaterial).set_shader_parameter("reveal", clampf(k, 0.0, 1.0))
		if k <= 0.0:
			sprite.queue_free()
			scene._materials.erase(leaf["fall_material"])
			leaf.erase("sprite")
			leaf["state"] = "gone"
			var regrow: Array = tuning["regrow_sec"]
			leaf["until"] = t + _rng.randf_range(float(regrow[0]), float(regrow[1]))
			return
	_place(leaf)


func _place(leaf: Dictionary) -> void:
	var sprite: Sprite2D = leaf["sprite"]
	var pos: Vector2 = leaf["pos"] + Vector2(float(leaf["drift"]) + float(leaf.get("swing", 0.0)), 0.0)
	# Whole art px, like everything else in a pixel kit.
	var snapped := (pos * scene.density).round() / scene.density
	sprite.position = snapped
	(leaf["fall_material"] as ShaderMaterial).set_shader_parameter("origin", snapped)


func _pivot(leaf: Dictionary) -> Vector2:
	return SceneKit.pivot_of(leaf["spec"]) / scene.density
