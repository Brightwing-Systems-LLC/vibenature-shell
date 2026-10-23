class_name SceneWaterFx
extends Node2D

## Rings on the water: raindrops, something touching the surface, a fish rising, and the wakes of
## whatever swims (each a trail of small rings). Seen at a low angle, so every ring is a flat
## ellipse; drawn pixel by pixel in the water's highlight colour, fading as it spreads.
##
## Splashes: something breaking the surface (a fish clearing it, a turtle coming up, a heron
## landing) throws a few drops that arc and fall back, each leaving a small ring.
##
## Hooks for the behaviour engine: `ring(at, size, strength, scale)`, `wake(at, velocity)` and
## `splash(at, size, scale)`. `scale` is how large the water there is drawn against the nearest
## water (its points per metre over the glass's): a ring or splash out on the pond is that much
## smaller, so a fish rising far out makes a far-out ring.

var tuning: Dictionary = {}
var rings: Array = []
var tint := Color.WHITE
## The waterline seen edge-on (points): rings lie on the surface, so no pixel of one is drawn below it.
var floor_y := INF
var drops: Array = []
var _t := 0.0
var _color := Color.WHITE
var _rng := RandomNumberGenerator.new()


func setup(water_tuning: Dictionary) -> void:
	tuning = water_tuning
	name = "WaterFx"
	_color = Color(String(tuning["ring_color"]))


## A ring opening at `at` (scene px): `size` scales its widest radius, `strength` its brightness,
## `scale` the whole ring for the distance (1 at the nearest water).
func ring(at: Vector2, size: float = 1.0, strength: float = 1.0, scale: float = 1.0) -> void:
	if rings.size() >= int(tuning["max_rings"]):
		rings.pop_front()
	var r: Array = tuning["ring_radius_px"]
	rings.append({"at": at.round(), "born": _t, "life": float(tuning["ring_life_sec"]) * (0.7 + 0.5 * size),
			"r": lerpf(float(r[0]), float(r[1]), clampf(size, 0.0, 1.5)) * clampf(scale, 0.05, 1.0), "a": strength, "double": size > 0.7 and scale > 0.45})


## Water thrown up at `at` (points), on the surface: `size` 0.3 (a fish's snap) to 1.5 (a heron
## landing). Drops arc up and fall back to the surface's row, each leaving a small ring. `scale`
## (the distance, as for `ring`) shrinks the throw: as high and as wide times `scale`, as long in time.
func splash(at: Vector2, size: float = 1.0, scale: float = 1.0) -> void:
	var s: Dictionary = tuning.get("splash", {})
	var k := clampf(scale, 0.05, 1.0)
	var n := int(round(lerpf(float(s.get("drops", [4, 12])[0]), float(s.get("drops", [4, 12])[1]), clampf(size / 1.5, 0.0, 1.0)) * clampf(k * 1.4, 0.4, 1.0)))
	var up: Array = s.get("up_pt_s", [22.0, 48.0])
	var side := float(s.get("side_pt_s", 24.0))
	for i in n:
		drops.append({"p": at + Vector2(_rng.randf_range(-2.0, 2.0) * size * k, 0.0), "base": at.y, "k": k,
				"v": Vector2(_rng.randf_range(-side, side) * size, -_rng.randf_range(float(up[0]), float(up[1])) * sqrt(size)) * k,
				"big": k > 0.6 and _rng.randf() < 0.3})
	ring(at, clampf(size, 0.3, 1.4), 1.0, k)


## Something moving at `velocity` (px/s) through the surface at `at`: a small ring now, and the
## caller calls again as it goes; rings left behind spread into a V. `scale` as for `ring` (the
## distance), so a wake out on the pond is smaller.
func wake(at: Vector2, velocity: Vector2, scale: float = 1.0) -> void:
	var speed := velocity.length()
	ring(at - velocity.normalized() * 2.0, clampf(0.25 + speed / 60.0, 0.25, 0.9), clampf(0.4 + speed / 80.0, 0.4, 0.9), scale)


func step(t: float) -> void:
	var dt := clampf(t - _t, 0.0, 0.1)
	_t = t
	rings = rings.filter(func(r: Dictionary) -> bool: return t - float(r["born"]) < float(r["life"]))
	var g := float(tuning.get("splash", {}).get("gravity_pt_s2", 160.0))
	for d in drops.duplicate():
		d["v"] = (d["v"] as Vector2) + Vector2(0.0, g * float(d.get("k", 1.0)) * dt)
		d["p"] = (d["p"] as Vector2) + (d["v"] as Vector2) * dt
		if (d["v"] as Vector2).y > 0.0 and (d["p"] as Vector2).y >= float(d["base"]):
			drops.erase(d)
			ring(Vector2((d["p"] as Vector2).x, float(d["base"])), 0.15, 0.6, float(d.get("k", 1.0)))
	queue_redraw()


func _draw() -> void:
	var squash := float(tuning["ring_squash"])
	var drop_color := Color(String(tuning.get("splash", {}).get("color", "e8f4f4"))) * tint
	for d in drops:
		# One art px (half a point) per drop, two for the bigger ones, on the art px grid.
		var size := 1.0 if bool(d["big"]) else 0.5
		draw_rect(Rect2(((d["p"] as Vector2) * 2.0).floor() * 0.5, Vector2(size, size)), drop_color)
	for r in rings:
		var age := (_t - float(r["born"])) / float(r["life"])
		var ease := 1.0 - pow(1.0 - age, 2.2)
		var radius := float(r["r"]) * ease + 0.6
		var alpha := float(r["a"]) * pow(1.0 - age, 1.4) * float(tuning["ring_alpha"])
		var color := _color * tint
		color.a = alpha
		_ellipse(r["at"], radius, squash, color)
		if bool(r["double"]) and radius > 3.0:
			color.a = alpha * 0.55
			_ellipse(r["at"], radius * 0.55, squash, color)


func _ellipse(center: Vector2, radius: float, squash: float, color: Color) -> void:
	var points := maxi(8, int(radius * 5.0))
	var seen := {}
	for i in points:
		var a := TAU * float(i) / float(points)
		var p := (center + Vector2(cos(a) * radius, sin(a) * radius * squash)).round()
		if seen.has(p) or p.y >= floor_y:
			continue
		seen[p] = true
		# The near half of the ring catches the light; the far half is fainter.
		var c := color
		if sin(a) < 0.0:
			c.a *= 0.6
		draw_rect(Rect2(p, Vector2.ONE), c)
