class_name SceneRain
extends Node2D

## Rain in three depths: fine slow streaks far back, longer faster ones close. The wind slants
## them. Each layer lands in its share of the rows from the far waterline down to the edge-on
## waterline (`ground` 0..1), never below it: under that line the scene is the pond in
## cross-section, and rain stops at the surface. Where a drop reaches open water it leaves a ring;
## on the bank a pixel of splash. How
## much falls follows the environment's `rain`, so a front's rain starts as a few drops.
## Drops come out of the underside of the sky's cloud line (issue 477, `deck_under`), fading in over
## `fade_rows` below it, never out of the open sky above it.

## Rain at or under this draws no drops (the first drops show just above it; `SceneShelter` goes on them).
const VISIBLE := 0.01

var tuning: Dictionary = {}
var tint := Color.WHITE
## How much of the scene is left at a point (points): 1 in the frame, 0 out past the margin's dissolve.
var edge_keep: Callable = func(_at: Vector2) -> float: return 1.0
## The row (points) the rain comes out of above x: the cloud line's underside, set by the scene.
var deck_under: Callable = func(_x: float) -> float: return 0.0
var drops: Array = []
var splashes: Array = []
var _rng := RandomNumberGenerator.new()
var _top := 0.0
## The rows drops land on (points): the far waterline and the edge-on waterline.
var _ground_from := 0.0
var _ground_to := 0.0
var _size := Vector2.ZERO
var _amount := 0.0
var _wind := 0.0
var _t := 0.0


## `water_top` and `cut` (points): the far waterline and the waterline seen edge-on.
func setup(size: Vector2, rain_tuning: Dictionary, seed: int, water_top: float, cut: float) -> void:
	tuning = rain_tuning
	name = "Rain"
	_rng.seed = seed
	_size = size
	_top = float(tuning["top_y"])
	_ground_from = water_top
	_ground_to = maxf(cut, water_top)
	for layer in tuning["layers"]:
		for i in int(layer["count"]):
			var d := {"layer": layer, "share": _rng.randf()}
			_respawn(d, true)
			drops.append(d)


func _respawn(d: Dictionary, anywhere: bool) -> void:
	var layer: Dictionary = d["layer"]
	var ground: Array = layer["ground"]
	d["x"] = _rng.randf_range(-40.0, _size.x + 40.0)
	d["ground"] = lerpf(_ground_from, _ground_to, _rng.randf_range(float(ground[0]), float(ground[1])))
	d["y"] = _rng.randf_range(_top - 60.0, float(d["ground"])) if anywhere else _top - _rng.randf_range(0.0, 60.0)
	d["speed"] = float(layer["speed_px_per_sec"]) * _rng.randf_range(0.85, 1.15)
	d["len"] = _rng.randf_range(float(layer["len_px"][0]), float(layer["len_px"][1]))


## Advances the drops; `on_ground(at, layer_index)` is called where each one lands.
func step(t: float, dt: float, env: SceneEnvironment, on_ground: Callable) -> void:
	_t = t
	_amount = env.rain
	_wind = env.wind_at(_size.x * 0.5)
	splashes = splashes.filter(func(s: Dictionary) -> bool: return t - float(s["born"]) < float(tuning["splash_sec"]))
	if _amount <= VISIBLE and splashes.is_empty():
		queue_redraw()
		return
	var slant := float(tuning["slant_per_wind"]) * _wind
	for d in drops:
		var active := float(d["share"]) < _amount
		d["y"] += float(d["speed"]) * dt
		d["x"] += slant * float(d["speed"]) * dt
		if float(d["y"]) >= float(d["ground"]):
			if active:
				on_ground.call(Vector2(float(d["x"]), float(d["ground"])), tuning["layers"].find(d["layer"]))
			_respawn(d, false)
	queue_redraw()


## The row the rain starts from above `x` (points): the cloud line's underside, never above `top_y`.
func top_at(x: float) -> float:
	return maxf(_top, float(deck_under.call(x)))


## The lowest row any drop reaches (points).
func floor_y() -> float:
	return _ground_to


func splash(at: Vector2) -> void:
	splashes.append({"at": at.round(), "born": _t})


func _draw() -> void:
	if _amount <= VISIBLE and splashes.is_empty():
		return
	var slant := float(tuning["slant_per_wind"]) * _wind
	var base := Color(String(tuning["color"])) * tint
	var fade := float(tuning["fade_rows"])
	for d in drops:
		if float(d["share"]) >= _amount:
			continue
		var layer: Dictionary = d["layer"]
		var head := Vector2(float(d["x"]), float(d["y"])).round()
		var length := float(d["len"])
		var tail := (head - Vector2(slant * length, length)).round()
		var c := base
		c.a = float(layer["alpha"]) * clampf((head.y - top_at(head.x)) / fade, 0.0, 1.0) * float(edge_keep.call(head))
		if c.a <= 0.0:
			continue
		draw_line(tail, head, c, 1.0)
	var sc := base.lightened(0.3)
	for s in splashes:
		var age := (_t - float(s["born"])) / float(tuning["splash_sec"])
		sc.a = 0.7 * (1.0 - age)
		var at: Vector2 = s["at"]
		draw_rect(Rect2(at + Vector2(-1, -1 - roundf(age * 2.0)), Vector2.ONE), sc)
		draw_rect(Rect2(at + Vector2(1, -1 - roundf(age * 2.0)), Vector2.ONE), sc)
