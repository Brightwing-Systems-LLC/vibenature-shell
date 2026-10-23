class_name SceneRises
extends Node2D

## Fish rising (ambient, Skypatch issue 104): a ring on
## the water and, for a moment, the dark curve of a back rolling over; now and then a fish clears
## the surface in a short arc and falls back in with a second ring. Sized by how far away the
## water is, so a rise across the pond is a fleck and one in the near shallows is a fish.

var behaviour: SceneBehaviour
var rises: Array = []


func setup(owner: SceneBehaviour) -> void:
	behaviour = owner
	name = "Rises"


## A rise (or, `jump`, a fish clearing the water) by one of `sp` (its colours), somewhere on the surface.
func rise(jump: bool, sp: SceneSpecies = null) -> void:
	var at := behaviour.random_water()
	var p := behaviour.ppm("water", at.y)
	var rng := behaviour.rng
	var length := rng.randf_range(0.12, 0.3)
	var dir := -1.0 if rng.randf() < 0.5 else 1.0
	var c: Dictionary = sp.data.get("colors", {}) if sp != null else {}
	rises.append({"at": at, "ppm": p, "t": 0.0, "life": 1.1 if jump else 0.7, "jump": jump, "len": length, "dir": dir, "ringed": false,
			"color": Color(String(c.get("back", "2c3424"))), "belly": Color(String(c.get("belly", "c9b779")))})
	behaviour.scene.ring(at, clampf(0.25 + p / 140.0, 0.25, 1.1), 0.9)
	behaviour.note("fish %s" % ("jumps" if jump else "rises"), sp.id if sp != null else "fish")
	behaviour.sound_event("fish_jump" if jump else "fish_rise", self, {"pos": at, "species": sp.id if sp != null else "",
			"size": sp.size().x if sp != null else 0.2})


func step(dt: float) -> void:
	for r in rises.duplicate():
		r["t"] = float(r["t"]) + dt
		if bool(r["jump"]) and not bool(r["ringed"]) and float(r["t"]) > 0.62:
			r["ringed"] = true
			var p := float(r["ppm"])
			var back_in := Vector2(r["at"]) + Vector2(float(r["dir"]) * float(r["len"]) * 2.2 * p, 0)
			behaviour.scene.ring(back_in, clampf(0.3 + p / 120.0, 0.3, 1.2), 1.0)
			behaviour.sound_event("fish_reentry", self, {"pos": back_in})
		if float(r["t"]) >= float(r["life"]):
			rises.erase(r)
	modulate = behaviour.scene.light_tint()
	queue_redraw()


func _draw() -> void:
	for r in rises:
		var at: Vector2 = r["at"]
		var p := float(r["ppm"])
		var u := float(r["t"])
		var L := float(r["len"]) * p
		var dir := float(r["dir"])
		var color: Color = r["color"]
		var belly: Color = r["belly"]
		if bool(r["jump"]):
			if u > 0.65:
				continue
			var s := u / 0.65
			var c := at + Vector2(dir * L * 2.2 * s, -sin(PI * s) * L * 1.3)
			var ang := atan2(-cos(PI * s) * 1.3 * PI, dir * 2.2)
			var pts := PackedVector2Array()
			for i in 12:
				var a := TAU * float(i) / 12.0
				pts.append(c + Vector2(cos(a) * L * 0.5, sin(a) * L * 0.17).rotated(ang if dir > 0 else ang + PI))
			draw_colored_polygon(pts, color)
			draw_line(c, c + Vector2(0, L * 0.1), belly, maxf(0.5, L * 0.12), true)
		else:
			if u < 0.08 or u > 0.55:
				continue
			# The back rolling over: an arc that rises and sinks, with the dorsal fin.
			var s := (u - 0.08) / 0.47
			var h := sin(PI * s) * L * 0.22
			var pts := PackedVector2Array()
			for i in 9:
				var a := float(i) / 8.0
				pts.append(at + Vector2((a - 0.5) * L + dir * s * L * 0.4, -sin(PI * a) * h))
			draw_polyline(pts, color, maxf(0.7, L * 0.12), true)
			var top := pts[4]
			draw_colored_polygon(PackedVector2Array([top + Vector2(-L * 0.08, 0), top + Vector2(-dir * L * 0.02, -h * 0.6 - L * 0.05), top + Vector2(L * 0.08, 0)]), color)
