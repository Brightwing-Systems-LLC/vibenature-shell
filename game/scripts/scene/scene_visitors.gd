class_name SceneVisitors
extends Node2D

## Placeholder visitors until the behaviour engine and the bench's wildlife land
## (Skypatch issue 100): a songbird that flies in on a
## curve, flares and lands on one of the kit's perches (the perch dips under it and springs back),
## sits a while, and flies off. It exists to exercise the perch impulse hook and give the avatar
## something to follow with his eyes. The engine will replace the scheduling, not the hooks.

signal landed(perch: Dictionary)
signal left_perch(perch: Dictionary)

var tuning: Dictionary = {}
var scene: Node
var birds: Array = []
var _rng := RandomNumberGenerator.new()
var _shader: Shader
var materials: Array[ShaderMaterial] = []


func setup(owner_scene: Node, visitor_tuning: Dictionary, shader: Shader, seed: int) -> void:
	scene = owner_scene
	tuning = visitor_tuning
	_shader = shader
	name = "Visitors"
	_rng.seed = seed


## A bird of `species` flies to `perch` ({piece, at, band}) and stays `stay_sec`.
func visit(species: String, perch: Dictionary, stay_sec: float = -1.0) -> bool:
	var layer := "back" if String(perch.get("band", "")) == "far" else "mid"
	var meta := AssetLibrary.load_meta("fauna", species)
	if not meta.has("layers") or not meta["layers"].has(layer):
		return false
	var spec: Dictionary = meta["layers"][layer]
	var file := "res://assets/fauna/%s/%s_%s.png" % [species, species, layer]
	if not ResourceLoader.exists(file):
		return false
	var sheet := load(file) as Texture2D
	var sprite := Sprite2D.new()
	sprite.texture = sheet
	sprite.hframes = maxi(1, sheet.get_width() / int(spec["frame_w"]))
	sprite.centered = false
	sprite.offset = -Vector2(AssetLibrary.vec2i(spec["anchor"]))
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("depth", 0.4 if layer == "back" else 0.6)
	sprite.material = m
	materials.append(m)
	var host: Node2D = scene.actor_layer(String(perch.get("band", "")))
	host.add_child(sprite)
	var at: Vector2 = perch["at"]
	var from_left := at.x > float(scene.size_pt.x) * 0.5 if _rng.randf() < 0.7 else _rng.randf() < 0.5
	var start := Vector2(-30.0 if from_left else float(scene.size_pt.x) + 30.0, _rng.randf_range(-20.0, 30.0))
	var stay := stay_sec if stay_sec > 0.0 else _rng.randf_range(float(tuning["stay_sec"][0]), float(tuning["stay_sec"][1]))
	var fly: Array = spec["animations"].get("fly", {"frames": [0]})["frames"]
	var idle: Array = spec["animations"].get("idle", {"frames": [0]})["frames"]
	var bird := {"sprite": sprite, "perch": perch, "state": "in", "t": 0.0, "stay": stay, "from": start, "fly": fly, "idle": idle,
			"dur": start.distance_to(at) / float(tuning["speed_px_per_sec"]), "flap": 0.0, "pos": start}
	birds.append(bird)
	_place(bird, start, at)
	return true


## Where the birds are (scene px): what the avatar's eyes follow.
func focus() -> Variant:
	for b in birds:
		if String(b["state"]) in ["in", "out"]:
			return b["pos"]
	for b in birds:
		return b["pos"]
	return null


func step(dt: float) -> void:
	for b in birds.duplicate():
		b["t"] += dt
		var perch: Dictionary = b["perch"]
		var at: Vector2 = perch["at"]
		var sprite: Sprite2D = b["sprite"]
		match String(b["state"]):
			"in":
				var u := clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
				# Fast across, then a flare: slows hard over the last stretch.
				var s := 1.0 - pow(1.0 - u, 2.4)
				var from: Vector2 = b["from"]
				var c1 := from.lerp(at, 0.4) + Vector2(0, -40)
				var c2 := at + Vector2((from.x - at.x) * 0.15, -28)
				var p := _bezier(from, c1, c2, at, s)
				_place(b, p, at)
				_flap(b, dt, 1.0 if u < 0.85 else 1.6)
				if u >= 1.0:
					b["state"] = "perched"
					b["t"] = 0.0
					sprite.frame = int(b["idle"][0])
					scene.perch_impulse(String(perch["piece"]), at, Vector2(0, float(tuning["landing_push"])))
					landed.emit(perch)
			"perched":
				# It rides the perch as it dips and springs back.
				sprite.position = (at + scene.perch_offset(String(perch["piece"]), at)).round()
				# Now and then a look the other way.
				if fposmod(float(b["t"]), 3.7) < dt:
					sprite.flip_h = not sprite.flip_h if _rng.randf() < 0.5 else sprite.flip_h
				if float(b["t"]) >= float(b["stay"]):
					b["state"] = "out"
					b["t"] = 0.0
					b["from"] = at
					var right := _rng.randf() < 0.5
					b["to"] = Vector2(float(scene.size_pt.x) + 40.0 if right else -40.0, _rng.randf_range(-40.0, 10.0))
					b["dur"] = at.distance_to(b["to"]) / float(tuning["speed_px_per_sec"])
					scene.perch_impulse(String(perch["piece"]), at, Vector2(0, float(tuning["takeoff_push"])))
					left_perch.emit(perch)
			"out":
				var u := clampf(float(b["t"]) / float(b["dur"]), 0.0, 1.0)
				var s := pow(u, 1.6)
				var to: Vector2 = b["to"]
				var p := _bezier(at, at + Vector2(0, -18), to.lerp(at, 0.5) + Vector2(0, -30), to, s)
				_place(b, p, to)
				_flap(b, dt, 1.4)
				if u >= 1.0:
					sprite.queue_free()
					materials.erase(sprite.material)
					birds.erase(b)


func _place(b: Dictionary, p: Vector2, toward: Vector2) -> void:
	var sprite: Sprite2D = b["sprite"]
	var prev: Vector2 = b["pos"]
	b["pos"] = p
	sprite.position = p.round()
	if absf(p.x - prev.x) > 0.05:
		# The sheets face left.
		sprite.flip_h = p.x > prev.x
	elif String(b["state"]) == "in":
		sprite.flip_h = toward.x > p.x
	var m := sprite.material as ShaderMaterial
	m.set_shader_parameter("origin", sprite.position + sprite.offset)


func _flap(b: Dictionary, dt: float, rate: float) -> void:
	var fly: Array = b["fly"]
	b["flap"] = float(b["flap"]) + dt * float(tuning["flap_fps"]) * rate
	(b["sprite"] as Sprite2D).frame = int(fly[int(b["flap"]) % fly.size()])


static func _bezier(a: Vector2, b: Vector2, c: Vector2, d: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return a * u * u * u + b * 3.0 * u * u * t + c * 3.0 * u * t * t + d * t * t * t
