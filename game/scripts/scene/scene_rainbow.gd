class_name SceneRainbow
extends Node2D

## The rainbow after a passing shower (issue 380):
## a light effect, the one thing in the beat drawn in code (as the ticket allows). The primary bow from
## violet (inside) to red (outside) at about 41-42° round the point opposite the sun, and a faint second
## bow at about 50-54° with its colours the other way round, both in the sky behind the far trees (its
## layer is the far band's back). Brightness wanders along the arc (the rain curtain is thicker in some
## places than others) and fades where the sky dissolves into the desktop. Built once per bow; the
## shower's beat fades the whole of it in and out through `modulate`.

## The spectrum from outside (red) to inside (violet), soft and a little warm, as a bow reads against a
## clearing grey sky.
const SPECTRUM := ["ff5a48", "ff9a3c", "ffe066", "8fe070", "5cb8f0", "6a7ce8", "a070e0"]
const BANDS := 14

var _runs: Array = []


## Builds the bow for `geo` (the weather beats body's `bow_geometry`: centre, deg, horizon) with the tuning
## `r` (`rainbow`), its wandering brightness drawn from `seed`.
func build(scene: LivingScene, geo: Dictionary, r: Dictionary, seed: int) -> void:
	_runs.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var legs: Array = r["legs"]
	var wander := [rng.randf() * TAU, rng.randf() * TAU, rng.randf_range(1.5, 3.5), rng.randf_range(4.0, 7.0)]
	var a := float(r["band_alpha"])
	_bow(scene, geo, r["primary_deg"], false, a, legs, wander)
	_bow(scene, geo, r["secondary_deg"], true, a * float(r["secondary_share"]), legs, wander)
	queue_redraw()


func _bow(scene: LivingScene, geo: Dictionary, span_deg: Array, reversed: bool, alpha: float, legs: Array, wander: Array) -> void:
	var c: Vector2 = geo["centre"]
	var deg := float(geo["deg"])
	var horizon := float(geo["horizon"])
	var size := scene.size_pt
	var inner := float(span_deg[0])
	var outer := float(span_deg[1])
	var px := 1.0 / scene.density
	for j in BANDS:
		var u := (float(j) + 0.5) / float(BANDS)
		var radius := lerpf(outer, inner, u) * deg
		var width := (outer - inner) * deg / float(BANDS) + px * 0.5
		var col := _spectrum(1.0 - u if reversed else u)
		var step := maxf(1.0, px * 4.0) / radius
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		var phi := 0.0
		while phi <= PI:
			var at := c + Vector2(cos(phi), -sin(phi)) * radius
			var inside := at.x >= -4.0 and at.x <= size.x + 4.0 and at.y >= -4.0 and at.y <= horizon
			if inside:
				var leg := lerpf(float(legs[0]), float(legs[1]), 0.5 + 0.25 * sin(phi * float(wander[2]) + float(wander[0])) + 0.25 * sin(phi * float(wander[3]) + float(wander[1])))
				var keep := scene.edge_keep(at)
				pts.append(at)
				cols.append(Color(col.r, col.g, col.b, alpha * leg * keep))
			elif pts.size() > 1:
				_runs.append({"pts": pts, "cols": cols, "width": width})
				pts = PackedVector2Array()
				cols = PackedColorArray()
			else:
				pts.clear()
				cols.clear()
			phi += step
		if pts.size() > 1:
			_runs.append({"pts": pts, "cols": cols, "width": width})


## The colour `u` of the way from outside (red, 0) to inside (violet, 1).
static func _spectrum(u: float) -> Color:
	var f := clampf(u, 0.0, 1.0) * float(SPECTRUM.size() - 1)
	var i := mini(int(f), SPECTRUM.size() - 2)
	return Color(SPECTRUM[i]).lerp(Color(SPECTRUM[i + 1]), f - float(i))


## How much of the bow is in the picture (points of arc), for tests and the probe.
func shown_length() -> float:
	var total := 0.0
	for run in _runs:
		var pts: PackedVector2Array = run["pts"]
		for k in range(1, pts.size()):
			total += pts[k].distance_to(pts[k - 1])
	return total / float(BANDS * 2)


func _draw() -> void:
	for run in _runs:
		draw_polyline_colors(run["pts"], run["cols"], float(run["width"]))
