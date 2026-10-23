class_name SceneHeron
extends RefCounted

## The great blue heron's ways (issue 238): how it
## comes (the glide-in across the pond, or walking in along the shallows from the far side) and how it
## hunts (slow steps along the shallows, a freeze in the S-neck crouch, a stab that sometimes misses, a
## frog or a small fish brought up wiggling, flipped head-first and swallowed, then preening and a
## shake before it hunts again or takes off). Builds beats for `SceneCreature`; every number is the
## species data's (`hunt`, `glide`, `walk_in`) and every place the places file's (`heron_shallows`,
## `heron_walk_in`, `heron_glide`). The prey is drawn into the bench's frames; nothing here draws.

## Metres of leg under the surface while it wades.
const WADE := 0.13


## Metres of leg under water where it stands (the places' `heron_shallows.wade_m`, else WADE): at the
## right bank's wet edge (issue 237) the water in front of the strip is only a few art px deep in
## the picture, so it stands ankle-deep at the edge rather than knee-deep.
static func wade_m(beh: SceneBehaviour) -> float:
	return float(beh.places.get("heron_shallows", {}).get("wade_m", WADE))


## How far short of the cut-away's glass its feet stay (points; `heron_shallows.glass_pt`, else 4).
static func glass_pt(beh: SceneBehaviour) -> float:
	return float(beh.places.get("heron_shallows", {}).get("glass_pt", 4.0))


static func hunt_data(c: SceneCreature) -> Dictionary:
	return c.sp.data.get("hunt", {})


## The shallows a heron may stand in, as polygons in points.
static func areas(beh: SceneBehaviour) -> Array:
	var out: Array = []
	for area in beh.places.get("heron_shallows", {}).get("areas", []):
		var poly := PackedVector2Array()
		for raw in area["poly"]:
			poly.append(beh.uv(raw))
		out.append(poly)
	return out


static func in_shallows(beh: SceneBehaviour, q: Vector2) -> bool:
	var all := areas(beh)
	if all.is_empty():
		return beh.scene.is_water(q) and q.y < beh.cut_y() - glass_pt(beh)
	# The areas are drawn on the water; the mask's gaps at the cattail stems in them are stems a
	# heron stands among, not dry ground.
	for poly in all:
		if Geometry2D.is_point_in_polygon(q, poly):
			return q.y < beh.cut_y() - glass_pt(beh)
	return false


## Somewhere in the shallows to land or stand (issue 272: an area, not a point): anywhere in the
## shallows' polygons (each as likely as it is wide), at least `heron_shallows.apart_pt` from the
## director's last few heron landings, which it then remembers. Without areas, the wading spot.
static func landing_spot(beh: SceneBehaviour) -> Dictionary:
	var polys := areas(beh)
	if polys.is_empty():
		return beh.wade_spot()
	var widths: Array = []
	var total := 0.0
	for poly in polys:
		var box := Rect2((poly as PackedVector2Array)[0], Vector2.ZERO)
		for q in poly:
			box = box.expand(q)
		widths.append(box.size.x)
		total += box.size.x
	var sample := func() -> Variant:
		var roll := beh.rng.randf() * total
		var poly: PackedVector2Array = polys[-1]
		for i in polys.size():
			roll -= float(widths[i])
			if roll <= 0.0:
				poly = polys[i]
				break
		for i in 10:
			var q := beh.point_in(poly)
			if in_shallows(beh, q):
				return q
		return null
	var gap := float(beh.places.get("heron_shallows", {}).get("apart_pt", 30.0))
	var found: Variant = SceneVariety.apart(sample, beh.recent_places("heron_land"), gap)
	if found == null:
		return beh.wade_spot()
	beh.remember_place("heron_land", found)
	return {"at": found, "band": "water"}


## Points per metre as the heron is drawn at `y` (larger than life across the pond).
static func drawn_ppm(c: SceneCreature, y: float) -> float:
	var p := c.beh.ppm("water", y)
	return p * c.sp.show_scale("water", p * c.beh.scene.density)


## The bill tip in the strike pose, metres ahead of and above the feet (as drawn).
static func tip_m(c: SceneCreature) -> Vector2:
	var h := hunt_data(c)
	var px: Array = h.get("bill_tip_px", [196, 192])
	return _px_m(c, Vector2(float(px[0]), float(px[1])))


static func _px_m(c: SceneCreature, px: Vector2) -> Vector2:
	var anchor := Vector2(110, 200)
	var ppm_sheet := 120.0
	if c.look.sheet != null:
		anchor = c.look.sheet.sets["side"]["master"]["anchor"]
		ppm_sheet = c.look.sheet.master_ppm
	return (px - anchor) / ppm_sheet


## Whether a stab from `at` facing `face` lands its bill in the water.
static func bill_in_water(c: SceneCreature, at: Vector2, face: float) -> bool:
	var reach := tip_m(c).x * drawn_ppm(c, at.y)
	# At the waterline, where the bill goes in (its feet are wade_m under it).
	var q := Vector2(at.x + face * reach, at.y - wade_m(c.beh) * drawn_ppm(c, at.y))
	return c.beh.scene.is_water(q) and q.y < c.beh.cut_y() - 1.0


## A slow step's end from `from`, mostly the way it faces, staying in the shallows; null if none.
static func step(c: SceneCreature, from: Vector2, face: float, dist_m: Vector2) -> Variant:
	var rng := c._rng
	var pd := drawn_ppm(c, from.y)
	for i in 10:
		var dir := face if rng.randf() < 0.75 else -face
		var d := rng.randf_range(dist_m.x, dist_m.y) * pd
		var q := from + Vector2(dir * d, rng.randf_range(-0.12, 0.12) * d)
		if in_shallows(c.beh, q):
			return q
	return null


## How long the sheet's `anim` lasts played once (`fallback` without a sheet).
static func anim_sec(c: SceneCreature, anim: String, fallback: float) -> float:
	if c.look.sheet == null:
		return fallback
	var a: Dictionary = c.look.sheet.anims.get("side", {}).get(anim, {})
	if a.is_empty():
		return fallback
	return float((a.get("frames", []) as Array).size()) / maxf(1.0, float(a.get("fps", 8)))


static func _r(rng: RandomNumberGenerator, h: Dictionary, key: String, fallback: Array) -> float:
	var r: Array = h.get(key, fallback)
	return rng.randf_range(float(r[0]), float(r[1]))


static func _ri(rng: RandomNumberGenerator, h: Dictionary, key: String, fallback: Array) -> int:
	var r: Array = h.get(key, fallback)
	return rng.randi_range(int(r[0]), int(r[1]))


static func _pick(rng: RandomNumberGenerator, weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	for k in weights:
		roll -= float(weights[k])
		if roll <= 0.0:
			return String(k)
	return String(weights.keys()[-1])


# --- The hunt -----------------------------------------------------------------------------------

## A hunting spell: bouts of a few slow steps (the foot held up between them), a freeze facing the
## water, then a stab or it straightens and moves on. A catch ends the spell with its tail.
static func hunt(c: SceneCreature) -> Array:
	var h := hunt_data(c)
	var rng := c._rng
	var beats: Array = []
	var at := c._last_to()
	var face := c.facing
	var speed := c.sp.speed("stalk")
	for bout in _ri(rng, h, "bouts", [2, 5]):
		for s in _ri(rng, h, "steps", [1, 3]):
			var q: Variant = step(c, at, face, Vector2(float(h.get("step_m", [0.25, 0.7])[0]), float(h.get("step_m", [0.25, 0.7])[1])))
			if q == null:
				break
			var to: Vector2 = q
			if absf(to.x - at.x) > 0.5:
				face = signf(to.x - at.x)
			beats.append({"a": "stalk", "to": to, "speed": speed, "gait": "walk", "wade": wade_m(c.beh), "max_sec": 20.0, "fx": "step"})
			# Between steps it stands on one foot, the stalk's frame held.
			beats.append({"a": "stalk", "sec": _r(rng, h, "step_pause_sec", [0.4, 1.4])})
			at = to
		if not bill_in_water(c, at, face):
			if not bill_in_water(c, at, -face):
				continue
			face = -face
			beats.append({"a": "idle", "sec": 0.6, "face": face})
		beats.append({"a": "freeze", "sec": _r(rng, h, "freeze_sec", [3, 14]), "face": face, "fx": "freeze"})
		if rng.randf() < float(h.get("strike_chance", 0.5)):
			var caught := false
			var strike := strike_beats(c, false)
			for b in strike:
				caught = caught or (b as Dictionary).has("prey")
			beats.append_array(strike)
			if caught:
				beats.append_array(after_catch(c))
				return beats
		else:
			# Nothing came: it straightens out of the crouch and moves on.
			beats.append({"a": "freeze", "sec": anim_sec(c, "freeze", 1.1), "backwards": true})
			if rng.randf() < float(h.get("turn_chance", 0.2)):
				face = -face
				beats.append({"a": "idle", "sec": 0.6, "face": face})
	return beats


## The stab from the freeze (with a short freeze first when `from_standing`): a catch or a miss.
static func strike_beats(c: SceneCreature, from_standing: bool) -> Array:
	var h := hunt_data(c)
	var rng := c._rng
	var beats: Array = []
	if from_standing:
		beats.append({"a": "freeze", "sec": rng.randf_range(1.2, 2.2)})
	beats.append({"a": "strike_fast", "sec": anim_sec(c, "strike_fast", 0.25), "fx": "strike"})
	if rng.randf() < float(h.get("catch_chance", 0.5)):
		var prey := _pick(rng, h.get("prey", {"fish": 1.0}))
		beats.append({"a": "catch_" + prey, "sec": anim_sec(c, "catch_" + prey, 0.7), "fx": "lift", "prey": prey})
		var wiggle := anim_sec(c, "wiggle_" + prey, 0.8) * float(_ri(rng, h, "wiggles", [2, 3]))
		beats.append({"a": "wiggle_" + prey, "sec": wiggle, "fx": "drip" if rng.randf() < float(h.get("drip_chance", 0.5)) else "", "prey": prey})
		beats.append({"a": "flip_" + prey, "sec": anim_sec(c, "flip_" + prey, 0.75), "prey": prey})
		beats.append({"a": "swallow_" + prey, "sec": anim_sec(c, "swallow_" + prey, 1.6), "fx": "swallow", "prey": prey})
		beats.append({"a": "idle", "sec": _r(rng, h, "settle_sec", [1.0, 2.5])})
	else:
		# Up out of the stab with nothing: the slow strike's way back up, from its lowest frame.
		var whole := anim_sec(c, "strike", 1.4)
		var from := int(h.get("miss_from_frame", 8))
		var fps := 12.0
		if c.look.sheet != null:
			fps = float(c.look.sheet.anims["side"].get("strike", {}).get("fps", 12))
		beats.append({"a": "strike", "sec": maxf(0.2, whole - float(from) / fps), "anim_sec": whole, "from": from, "fx": "miss"})
		beats.append({"a": "idle", "sec": _r(rng, h, "after_miss_sec", [1.0, 2.5])})
	return beats


## After a catch, the tail: it settles, preens one or two areas, shakes its feathers, stands a while,
## and now and then takes off.
static func after_catch(c: SceneCreature) -> Array:
	var h := hunt_data(c)
	var rng := c._rng
	var beats := preen(c, _ri(rng, h, "preens", [1, 2]))
	if rng.randf() < float(h.get("shake_chance", 0.8)):
		beats.append({"a": "shake", "sec": anim_sec(c, "shake", 1.1), "fx": "shake"})
	beats.append({"a": "idle", "sec": _r(rng, h, "after_preen_sec", [1.0, 3.0])})
	if rng.randf() < float(h.get("takeoff_chance", 0.3)):
		beats.append({"a": "idle", "sec": 0.3, "leave": true})
	return beats


## `n` preens: into the pose, the loop for a while, out of it.
static func preen(c: SceneCreature, n: int) -> Array:
	var h := hunt_data(c)
	var rng := c._rng
	var beats: Array = []
	var last := ""
	for i in n:
		var weights: Dictionary = h.get("preen_areas", {"breast": 1.0}).duplicate()
		if weights.size() > 1:
			weights.erase(last)
		var area := _pick(rng, weights)
		last = area
		var a := "preen_" + area
		beats.append({"a": a + "_in", "sec": anim_sec(c, a + "_in", 1.1), "fx": "preen"})
		beats.append({"a": a, "sec": _r(rng, h, "preen_loop_sec", [2.0, 5.0])})
		beats.append({"a": a + "_out", "sec": anim_sec(c, a + "_out", 1.1)})
		beats.append({"a": "idle", "sec": _r(rng, h, "between_preens_sec", [0.6, 1.6])})
	return beats


# --- Ways in --------------------------------------------------------------------------------------

## Which way it comes: the hand-off's big moment always glides in (a walk-in is never a big moment).
static func entrance(c: SceneCreature, why: String) -> String:
	if c.beh.next_entrance != "":
		var named := c.beh.next_entrance
		c.beh.next_entrance = ""
		return named
	if why == "moment":
		return "glide"
	var e: Dictionary = c.sp.data.get("entrances", {})
	var w := {"glide": float(e.get("glide", 1.0)), "walk": float(e.get("walk", 0.0))}
	if c.beh.places.get("heron_walk_in", {}).get("path", []).is_empty():
		w["walk"] = 0.0
	return _pick(c._rng, w)


## The glide-in (issue 272: one of a family, never the same line twice running): an approach from
## the places' `heron_glide.approaches` (high or low from the left over the trees, dropping in from
## above, or out of the distance over the far trees toward the viewer), fresh against the director's
## last few; each waypoint drawn from its own box, the last stretch `approach_m` back and up from a
## landing spot of its own, and the wingbeats and glides at shares of the flight of their own.
static func glide_in(c: SceneCreature) -> Array:
	var beh := c.beh
	var rng := c._rng
	var g: Dictionary = c.sp.data.get("glide", {})
	var spec: Dictionary = beh.places.get("heron_glide", {})
	c._spot = landing_spot(beh)
	var at: Vector2 = c._spot["at"]
	var family: Dictionary = spec.get("approaches", {})
	var weights := {}
	for k in family:
		weights[k] = float((family[k] as Dictionary).get("weight", 1.0))
	var kind := SceneVariety.pick_fresh(rng, weights, beh.recent_places("heron_entry")) if not weights.is_empty() else ""
	if beh.next_approach != "" and family.has(beh.next_approach):
		kind = beh.next_approach
	beh.next_approach = ""
	if kind != "":
		beh.remember_place("heron_entry", kind)
	var app: Dictionary = family.get(kind, {})
	var pd := drawn_ppm(c, at.y)
	var p_at := beh.ppm("water", at.y)
	var dur := _r(rng, g, "dur_sec", [5.2, 6.8]) * float(app.get("dur_mult", 1.0))
	var land := anim_sec(c, "land", 1.4)
	var before := float(g.get("land_sec_before", 0.5))
	var first: Dictionary
	if bool(app.get("from_far", false)):
		dur *= float(app.get("far_dur_mult", 1.3))
		var acts := glide_acts(rng, g, dur)
		acts.append([1.0 - before / dur, "land", land])
		first = _glide_from_far(c, app, at, dur, acts)
	else:
		var acts := glide_acts(rng, g, dur)
		acts.append([1.0 - before / dur, "land", land])
		var froms: Array = app.get("from", spec.get("from", [[-0.07, 0.05]]))
		var start := _in_box(beh, rng, froms[rng.randi() % froms.size()])
		var dir := 1.0 if at.x > start.x else -1.0
		var points: Array = [start]
		for raw in app.get("via", spec.get("via", [])):
			var v := _in_box(beh, rng, raw)
			# Never behind the waypoint before, nor past the landing.
			if (v.x - (points[-1] as Vector2).x) * dir > 4.0 and (at.x - v.x) * dir > 4.0:
				points.append(v)
		var ap := Vector2(_r(rng, spec, "approach_m", [1.6, 1.6]), _r(rng, spec, "approach_up_m", [1.1, 1.1]))
		points.append(at + Vector2(-dir * ap.x * pd, -ap.y * pd))
		points.append(at)
		var from_ppm := p_at * _r(rng, g, "ppm_from", [0.6, 0.6])
		c.pos = start
		c.facing = dir
		c._fly_ppm = from_ppm
		first = {"a": "fly", "path": [], "line": spline(points), "dur": dur, "ppm": [from_ppm, p_at], "ease": "glide",
				"acts": acts, "bank": deg_to_rad(_r(rng, g, "bank_deg", [10.0, 10.0])), "wade": 0.0, "approach": kind}
	return [
		first,
		{"a": "land", "sec": maxf(0.2, land - before), "anim_sec": land, "fx": "splash", "wade": wade_m(c.beh)},
		{"a": "idle", "sec": rng.randf_range(1.0, 2.0)},
		{"a": "look", "sec": rng.randf_range(1.5, 3.5)},
	]


## When its wings beat and when it glides, as shares of a `dur`-second glide-in (issue 272): a few
## deep beats to start (`beats_share`), the long glide, a burst or two of beats on the way (`bursts`,
## each `burst_share` long) and the glide in to land. Every share its own, inside the species' ranges.
## Species data without `beats_share` keeps its fixed `acts`.
static func glide_acts(rng: RandomNumberGenerator, g: Dictionary, dur: float) -> Array:
	if not g.has("beats_share"):
		return (g.get("acts", [[0.0, "fly"]]) as Array).duplicate(true)
	var acts: Array = [[0.0, "fly"]]
	var u := _r(rng, g, "beats_share", [0.14, 0.26])
	acts.append([u, "glide"])
	var bursts := _ri(rng, g, "bursts", [1, 2])
	var room := 1.0 - float(g.get("land_sec_before", 0.5)) / dur - 0.1
	for i in bursts:
		var at := lerpf(u + 0.1, room, (float(i) + rng.randf_range(0.3, 0.8)) / float(bursts))
		var len := _r(rng, g, "burst_share", [0.07, 0.14])
		if at <= u + 0.08 or at + len >= room:
			continue
		acts.append([at, "fly"])
		acts.append([at + len, "glide"])
		u = at + len
	return acts


## A point in a box of the places file ([u0, v0, u1, v1], fractions of the frame), or the point [u, v].
static func _in_box(beh: SceneBehaviour, rng: RandomNumberGenerator, raw: Array) -> Vector2:
	if raw.size() < 4:
		return beh.uv(raw)
	return beh.uv([rng.randf_range(float(raw[0]), float(raw[2])), rng.randf_range(float(raw[1]), float(raw[3]))])


## Out of the distance (issue 272): from over the far treeline, high, toward the viewer and across,
## coming down over the open pond, then the last stretch side-on into the landing (so it lands in
## the side view it is drawn landing in). A line in metres (across, away, up) sampled evenly by
## distance in the world like `fly_away`; drawn at the landing spot's larger-than-life share, so it
## grows as it comes. It fades in over the treeline.
static func _glide_from_far(c: SceneCreature, app: Dictionary, at: Vector2, dur: float, acts: Array) -> Dictionary:
	var beh := c.beh
	var rng := c._rng
	var p := beh.ppm("water", at.y)
	var cx := beh.scene.size_pt.x * 0.5
	var z_end := beh.depth_of(p)
	var end := Vector3((at.x - cx) / p, z_end, (beh.ground_y(z_end) - at.y) / p)
	# Where over the far treeline it first shows (`far_u`, a share of the width), well to one side of
	# the landing, so it comes steadily one way across the picture and never doubles back.
	var z_far := _r(rng, app, "far_m", [55.0, 75.0])
	var sx := at.x
	for i in 8:
		sx = beh.scene.size_pt.x * _r(rng, app, "far_u", [0.25, 0.8])
		if absf(at.x - sx) > 60.0:
			break
	var dir := 1.0 if at.x >= sx else -1.0
	var side := minf(_r(rng, app, "side_m", [3.0, 6.0]), 0.4 * absf(at.x - sx) / p)
	var near := end + Vector3(-dir * side, _r(rng, app, "near_m", [1.0, 2.5]), _r(rng, app, "near_up_m", [1.0, 2.0]))
	var far := Vector3((sx - cx) / beh.ppm_at_depth(z_far), z_far, _r(rng, app, "high_m", [1.5, 3.5]))
	var mid := far.lerp(near, 0.6) + Vector3(0.0, 0.0, -_r(rng, app, "sag_m", [0.5, 2.0]))
	var pts := [far, mid, near, end]
	var fine: Array = []
	var lengths: Array = [0.0]
	for i in 121:
		var t := float(i) / 120.0
		var u := 1.0 - t
		var q: Vector3 = pts[0] * u * u * u + pts[1] * 3.0 * u * u * t + pts[2] * 3.0 * u * t * t + pts[3] * t * t * t
		if not fine.is_empty():
			lengths.append(float(lengths[-1]) + (q - (fine[-1] as Vector3)).length())
		fine.append(q)
	var total := float(lengths[-1])
	var line := PackedVector2Array()
	var ppms := PackedFloat32Array()
	var j := 0
	for i in 61:
		var want := total * float(i) / 60.0
		while j < fine.size() - 2 and float(lengths[j + 1]) < want:
			j += 1
		var q: Vector3 = (fine[j] as Vector3).lerp(fine[j + 1], clampf((want - float(lengths[j])) / maxf(float(lengths[j + 1]) - float(lengths[j]), 0.0001), 0.0, 1.0))
		var pz := beh.ppm_at_depth(q.y)
		line.append(Vector2(cx + q.x * pz, beh.ground_y(q.y) - q.z * pz))
		ppms.append(pz)
	line[line.size() - 1] = at
	ppms[ppms.size() - 1] = p
	c.pos = line[0]
	c.facing = dir
	c._fly_ppm = ppms[0]
	c.alpha = 0.0
	return {"a": "fly", "path": [], "pts": line, "ppms": ppms, "dur": dur, "ppm": [ppms[0], p], "ease": "glide", "acts": acts, "fade": 1.0,
			"show": c.sp.show_scale("water", p * beh.scene.density), "wade": 0.0, "approach": "far"}


## The walk-in along the shallows from the far side, out of the frame's edge, fading in over the
## first part; then it stands and looks before it hunts.
static func walk_in(c: SceneCreature) -> Array:
	var beh := c.beh
	var rng := c._rng
	var w: Dictionary = c.sp.data.get("walk_in", {})
	var path: Array = beh.places.get("heron_walk_in", {}).get("path", [])
	var pts: Array = []
	for raw in path:
		pts.append(beh.uv(raw))
	c.pos = pts[0]
	c.alpha = 0.0
	c.facing = signf((pts[1] as Vector2).x - (pts[0] as Vector2).x)
	c._spot = {"at": pts[-1], "band": "water"}
	var beats: Array = []
	for i in range(1, pts.size()):
		var b := {"a": "walk", "to": pts[i], "gait": "walk", "wade": wade_m(c.beh), "max_sec": 40.0}
		if i == 1:
			b["fade"] = 1.0
		beats.append(b)
	beats.append({"a": "idle", "sec": rng.randf_range(0.8, 1.6)})
	beats.append({"a": "look", "sec": _r(rng, w, "look_sec", [1.5, 3.5])})
	return beats


## A takeoff from where it stands: the crouch and wings up standing in the water, then the deep
## downstrokes lift it clear (a splash as the feet leave), then away on the flight path.
static func takeoff(c: SceneCreature, dir: float, hurry: bool) -> Array:
	var len := anim_sec(c, "takeoff", 1.6)
	var stand := len * (0.3 if hurry else 0.4)
	var pd := drawn_ppm(c, c.pos.y)
	var p := c.ppm()
	var lift := c.pos + Vector2(dir * 1.6 * pd, -1.2 * pd)
	return [
		{"a": "takeoff", "sec": stand, "anim_sec": len, "face": dir, "fx": "alarm" if hurry else "", "wade": wade_m(c.beh)},
		{"a": "takeoff", "path": [c.pos, c.pos + Vector2(dir * 0.1 * pd, -0.5 * pd), lift + Vector2(-dir * 0.6 * pd, 0.0), lift],
				"dur": len - stand, "ppm": [p, p], "ease": "in", "anim_sec": len, "fx": "lift_off", "wade": 0.0},
	]


## Away over the pond after a takeoff (issue 237): a short leg across, then it swings away from the
## viewer and flies low over the water into the scene, climbing slowly, smaller and smaller toward
## the far bank, and fades as it reaches the treeline. A line in metres (across, away, up) sampled
## evenly by distance in the world, so its speed is steady however far it is; its drawn size keeps
## the share larger than life it had where it stood, so it shrinks with distance.
static func fly_away(c: SceneCreature, from: Vector2, dir: float, hurry: bool) -> Dictionary:
	var beh := c.beh
	var rng := c._rng
	var a: Dictionary = c.sp.data.get("fly_away", {})
	var p := c.ppm()
	var cx := beh.scene.size_pt.x * 0.5
	var z0 := beh.depth_of(p)
	var start := Vector3((from.x - cx) / p, z0, (beh.ground_y(z0) - from.y) / p)
	var z1 := _r(rng, a, "far_m", [70.0, 85.0])
	var h1 := start.z + _r(rng, a, "climb_m", [5.0, 9.0])
	var x1 := start.x + dir * _r(rng, a, "across_m", [8.0, 16.0])
	var leg := _r(rng, a, "leg_m", [4.0, 7.0])
	var pts := [start, start + Vector3(dir * leg, 0.6, 0.8), Vector3(x1, z0 + (z1 - z0) * 0.3, lerpf(start.z, h1, 0.55)), Vector3(x1, z1, h1)]
	var fine: Array = []
	var lengths: Array = [0.0]
	for i in 121:
		var t := float(i) / 120.0
		var u := 1.0 - t
		var q: Vector3 = pts[0] * u * u * u + pts[1] * 3.0 * u * u * t + pts[2] * 3.0 * u * t * t + pts[3] * t * t * t
		if not fine.is_empty():
			lengths.append(float(lengths[-1]) + (q - (fine[-1] as Vector3)).length())
		fine.append(q)
	var total := float(lengths[-1])
	var line := PackedVector2Array()
	var ppms := PackedFloat32Array()
	var j := 0
	for i in 61:
		var want := total * float(i) / 60.0
		while j < fine.size() - 2 and float(lengths[j + 1]) < want:
			j += 1
		var q: Vector3 = (fine[j] as Vector3).lerp(fine[j + 1], clampf((want - float(lengths[j])) / maxf(float(lengths[j + 1]) - float(lengths[j]), 0.0001), 0.0, 1.0))
		var pz := beh.ppm_at_depth(q.y)
		line.append(Vector2(cx + q.x * pz, beh.ground_y(q.y) - q.z * pz))
		ppms.append(pz)
	var speed := c.sp.speed("fly") * (1.3 if hurry else 1.0)
	return {"a": "fly", "path": [], "pts": line, "ppms": ppms, "dur": clampf(total / maxf(speed, 0.1), 6.0, 16.0), "ppm": [p, ppms[-1]], "face": dir,
			"show": c.sp.show_scale("water", p * beh.scene.density), "fade_at": float(a.get("fade_from", 0.8)), "wade": 0.0}


# --- Paths ---------------------------------------------------------------------------------------

## A smooth line through `points` (Catmull-Rom), densely sampled.
static func spline(points: Array, per_segment: int = 24) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := points.size()
	for i in n - 1:
		var p0: Vector2 = points[maxi(0, i - 1)]
		var p1: Vector2 = points[i]
		var p2: Vector2 = points[i + 1]
		var p3: Vector2 = points[mini(n - 1, i + 2)]
		for k in per_segment:
			var t := float(k) / float(per_segment)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3))
	out.append(points[-1])
	return out


## The point `u` (0..1) of the way along `line` by distance.
static func along(line: PackedVector2Array, u: float) -> Vector2:
	if line.size() < 2:
		return line[0] if not line.is_empty() else Vector2.ZERO
	var total := 0.0
	for i in line.size() - 1:
		total += line[i].distance_to(line[i + 1])
	var want := clampf(u, 0.0, 1.0) * total
	for i in line.size() - 1:
		var seg := line[i].distance_to(line[i + 1])
		if want <= seg or i == line.size() - 2:
			return line[i].lerp(line[i + 1], clampf(want / maxf(seg, 0.0001), 0.0, 1.0))
		want -= seg
	return line[-1]


## How far the bird tips at `u` of `line`: nose down as it descends, more through a turn, level
## again as it brakes to land.
static func bank_at(line: PackedVector2Array, u: float, most: float) -> float:
	var a := along(line, maxf(0.0, u - 0.03))
	var b := along(line, u)
	var d := along(line, minf(1.0, u + 0.03))
	var v1 := b - a
	var v2 := d - b
	if v1.length() < 0.01 or v2.length() < 0.01:
		return 0.0
	var pitch := atan2(v2.y, absf(v2.x))
	var turn := absf(wrapf(v2.angle() - v1.angle(), -PI, PI))
	var tilt := clampf(pitch * 0.8 + turn * 2.5 * signf(pitch if absf(pitch) > 0.01 else 1.0), -most, most)
	return tilt * clampf((1.0 - u) / 0.15, 0.0, 1.0)
