class_name ScenePlan
extends RefCounted

## A flight or swim planned whole in metres (a shell body, contract §8): waypoints joined by Catmull-Rom
## legs or straight lines, each leg with its speed at either end changing evenly between, so nothing
## jumps; `pose_at` says where it is at any time, `peaks` and `overs` measure it as the scene's speed
## meter does. Pure. The big moments in a scene package build their plans with it (`Builder`), so it is
## part of the `PackageBody` API (`body_api` 1). Moved as it was from the hawk pass (the spline,
## issue 311), the osprey (`Builder`, issue 362), the
## geese (`row_secs`, issue 356) and the kingfisher (`centre_on`, `parse`, issue 364).

const ARC_N := 32


## Cumulative length along leg `i` of the spline at ARC_N + 1 even steps of its parameter.
static func arc_lengths(pts: Array, i: int) -> Array:
	var out: Array = [0.0]
	var prev := spline(pts, i, 0.0)
	for n in range(1, ARC_N + 1):
		var q := spline(pts, i, float(n) / float(ARC_N))
		out.append(float(out[-1]) + q.distance_to(prev))
		prev = q
	return out


static func spline(pts: Array, i: int, k: float) -> Vector3:
	var p1: Vector3 = pts[i]
	var p2: Vector3 = pts[i + 1]
	var p0: Vector3 = pts[i - 1] if i > 0 else p1 * 2.0 - p2
	var p3: Vector3 = pts[i + 2] if i + 2 < pts.size() else p2 * 2.0 - p1
	var k2 := k * k
	var k3 := k2 * k
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * k + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * k2 + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * k3)


## Where a spline plan is at `time` (s): {p (metres), a (action), view, alpha, leg}.
static func spline_pose_at(p: Dictionary, time: float) -> Dictionary:
	var legs: Array = p["legs"]
	var u := clampf(time, 0.0, float(p["dur"]))
	var i := 0
	while i < legs.size() - 1 and u > float(legs[i]["dur"]):
		u -= float(legs[i]["dur"])
		i += 1
	var leg: Dictionary = legs[i]
	var dur := maxf(float(leg["dur"]), 0.001)
	var v0 := float(leg["v0"])
	var v1 := float(leg["v1"])
	var dist := clampf(v0 * u + 0.5 * (v1 - v0) / dur * u * u, 0.0, float(leg["len"]))
	var arc: Array = leg["arc"]
	var n := 1
	while n < arc.size() - 1 and float(arc[n]) < dist:
		n += 1
	var seg := maxf(float(arc[n]) - float(arc[n - 1]), 0.0001)
	var k := (float(n - 1) + clampf((dist - float(arc[n - 1])) / seg, 0.0, 1.0)) / float(ARC_N)
	var at := spline(p["pts"], i, k)
	# The line may swing under the low point between waypoints: never into the water.
	at.y = maxf(at.y, float(p.get("min_y", 0.0)))
	var alpha := 1.0
	if float(p["fade_from"]) >= 0.0 and time > float(p["fade_from"]):
		alpha = clampf(1.0 - (time - float(p["fade_from"])) / maxf(float(p["dur"]) - float(p["fade_from"]), 0.01), 0.0, 1.0)
	return {"p": at, "a": String(leg["a"]), "view": String(leg["view"]), "alpha": alpha, "leg": i}


## The view a flight leg's chord is seen from: side, three-quarters or straight on, toward or away.
static func view_of(d: Vector3) -> String:
	var off := rad_to_deg(atan2(absf(d.z), maxf(absf(d.x), 0.001)))
	if off < 35.0:
		return "side"
	var way := "toward" if d.z < 0.0 else "away"
	return ("3q_" + way) if off < 65.0 else way


## Legs from waypoints, each with its end speed, built at `done`. A leg with `fixed` seconds (a sheet
## row) lasts that long, its end speed whatever covers its length from the speed it came in at (never
## below 0: it ends sooner and holds its last frame); an `even` leg moves evenly (the splash sinking); a
## `line` leg is straight (the hover, the dive); a hold stands still. A long spline leg is cut into
## pieces no longer than half again its neighbours (a Catmull-Rom leg beside a much shorter one bulges
## and its speed jumps), its speed changing evenly with distance across them.
class Builder:
	var pts: Array = []
	var specs: Array = []
	var marks := {}
	var _v0 := 0.0

	func start(p: Vector3, v: float) -> void:
		pts = [p]
		_v0 = v

	func mark(key: String) -> void:
		marks[key] = specs.size()

	func to(p: Vector3, a: String, g: String, v1: float, fixed: float = -1.0, back: bool = false, even: bool = false, line: bool = false) -> void:
		specs.append({"from": pts[-1], "p": p, "a": a, "g": g, "v1": v1, "fixed": fixed, "back": back, "even": even, "line": line or even, "hold": -1.0})
		pts.append(p)

	## Stands still at the last point for `sec` playing `a`.
	func hold(a: String, g: String, sec: float) -> void:
		specs.append({"from": pts[-1], "p": pts[-1], "a": a, "g": g, "v1": 0.0, "fixed": -1.0, "back": false, "even": false, "line": true, "hold": sec})
		pts.append(pts[-1])

	func done() -> Dictionary:
		# Cut long spline legs, so no spline leg sits beside one much shorter.
		var cut: Array = []
		for i in specs.size():
			var s: Dictionary = specs[i]
			var chord := (s["from"] as Vector3).distance_to(s["p"])
			if bool(s["line"]) or float(s["fixed"]) > 0.0 or float(s["hold"]) >= 0.0 or chord < 0.01:
				cut.append([i, 1])
				continue
			var near := INF
			for j in [i - 1, i + 1]:
				if j >= 0 and j < specs.size():
					var o: Dictionary = specs[j]
					var oc := (o["from"] as Vector3).distance_to(o["p"])
					if oc > 0.01:
						near = minf(near, oc)
			var piece := clampf(1.5 * near, 2.0, 8.0) if near < INF else 8.0
			cut.append([i, maxi(1, int(ceil(chord / piece)))])
		var all_pts: Array = [pts[0]]
		var parts: Array = []
		for entry in cut:
			var s: Dictionary = specs[int(entry[0])]
			var n := int(entry[1])
			for k in range(1, n + 1):
				var u := float(k) / float(n)
				all_pts.append((s["from"] as Vector3).lerp(s["p"], u))
				parts.append({"si": int(entry[0]), "u1": u})
		var legs: Array = []
		var total := 0.0
		var v := _v0
		var times := {}
		for idx in parts.size():
			var part: Dictionary = parts[idx]
			var s: Dictionary = specs[int(part["si"])]
			if not times.has(int(part["si"])):
				times[int(part["si"])] = total
			var arc: Array
			if float(s["hold"]) >= 0.0:
				arc = []
				arc.resize(ScenePlan.ARC_N + 1)
				arc.fill(0.0)
			elif bool(s["line"]):
				var ln := (all_pts[idx] as Vector3).distance_to(all_pts[idx + 1])
				arc = []
				for k in ScenePlan.ARC_N + 1:
					arc.append(ln * float(k) / float(ScenePlan.ARC_N))
			else:
				arc = ScenePlan.arc_lengths(all_pts, idx)
			var length := float(arc[-1])
			var v0 := v
			var v1 := float(s["v1"])
			var dur := 0.0
			var fixed := float(s["fixed"])
			if float(s["hold"]) >= 0.0:
				dur = float(s["hold"])
				v0 = 0.0
				v1 = 0.0
			elif bool(s["even"]):
				dur = fixed
				v0 = length / maxf(dur, 0.001)
				v1 = v0
			elif fixed > 0.0:
				dur = fixed
				v1 = 2.0 * length / dur - v0
				if v1 < 0.0:
					v1 = 0.0
					dur = 2.0 * length / maxf(v0, 0.01)
			else:
				# Speed changing evenly with distance over the whole spec, cut or not.
				var sv0: float = s.get("v0_in", v0)
				s["v0_in"] = sv0
				v1 = sqrt(maxf(0.0, sv0 * sv0 + (float(s["v1"]) * float(s["v1"]) - sv0 * sv0) * float(part["u1"])))
				dur = 2.0 * length / maxf(v0 + v1, 0.01)
			var d: Vector3 = (all_pts[idx + 1] as Vector3) - (all_pts[idx] as Vector3)
			legs.append({"dur": dur, "len": length, "a": String(s["a"]), "g": String(s["g"]), "back": bool(s["back"]), "line": bool(s["line"]),
					"view": "side", "arc": arc, "v0": v0, "v1": v1, "face": 1.0 if d.x >= 0.0 else -1.0, "row": fixed if fixed > 0.0 else -1.0})
			total += dur
			v = v1
		times[specs.size()] = total
		var p := {"pts": all_pts, "legs": legs, "dur": total, "fade_from": -1.0, "min_y": -10.0}
		for k in marks:
			p[k] = float(times.get(int(marks[k]), total))
		return p


## Where it is at `time` (s): {p (metres), a, leg}; a `line` leg is straight, a hold stands still.
static func pose_at(p: Dictionary, time: float) -> Dictionary:
	var legs: Array = p["legs"]
	var u := clampf(time, 0.0, float(p["dur"]))
	var i := 0
	while i < legs.size() - 1 and u > float(legs[i]["dur"]):
		u -= float(legs[i]["dur"])
		i += 1
	var leg: Dictionary = legs[i]
	if not bool(leg.get("line", false)):
		return spline_pose_at(p, time)
	var dur := maxf(float(leg["dur"]), 0.001)
	var v0 := float(leg["v0"])
	var v1 := float(leg["v1"])
	var dist := clampf(v0 * u + 0.5 * (v1 - v0) / dur * u * u, 0.0, float(leg["len"]))
	var a: Vector3 = p["pts"][i]
	var b: Vector3 = p["pts"][i + 1]
	var at := a if float(leg["len"]) <= 0.0 else a.lerp(b, dist / float(leg["len"]))
	return {"p": at, "a": String(leg["a"]), "view": "side", "alpha": 1.0, "leg": i}


## The fastest speed (m/s) and hardest acceleration (m/s²) in each leg group of a plan, measured as the
## scene measures it (velocity over a fifth of a second, its change over the next): {group: Vector2}.
## A window is counted to the group of the leg it ends in.
static func peaks(p: Dictionary) -> Dictionary:
	var h := 1.0 / 30.0
	var w := 6
	var ps: Array = []
	var gs: Array = []
	var t := 0.0
	while t <= float(p["dur"]):
		var pose := pose_at(p, t)
		ps.append(pose["p"])
		gs.append(String(p["legs"][int(pose["leg"])]["g"]))
		t += h
	var out := {}
	for i in range(w, ps.size()):
		var v: Vector3 = ((ps[i] as Vector3) - (ps[i - w] as Vector3)) / (w * h)
		var g := String(gs[i])
		var pk: Vector2 = out.get(g, Vector2.ZERO)
		pk.x = maxf(pk.x, v.length())
		if i >= 2 * w:
			var was: Vector3 = ((ps[i - w] as Vector3) - (ps[i - 2 * w] as Vector3)) / (w * h)
			pk.y = maxf(pk.y, (v - was).length() / (w * h))
		out[g] = pk
	return out


## Every moment of a plan over its leg's limits (`legs`: group -> {top, accel}), measured as `peaks`:
## "at <s>: leg <i> <group>/<row> <m/s> <m/s²> <from> -> <to>" (the probe's and the tests' account).
static func overs(p: Dictionary, legs: Dictionary) -> Array:
	var h := 1.0 / 30.0
	var ps: Array = []
	var t := 0.0
	while t <= float(p["dur"]):
		ps.append([t, pose_at(p, t)])
		t += h
	var out: Array = []
	for i in range(12, ps.size()):
		var pose: Dictionary = ps[i][1]
		var v: Vector3 = ((pose["p"] as Vector3) - (ps[i - 6][1]["p"] as Vector3)) / (6.0 * h)
		var was: Vector3 = ((ps[i - 6][1]["p"] as Vector3) - (ps[i - 12][1]["p"] as Vector3)) / (6.0 * h)
		var a := (v - was).length() / (6.0 * h)
		var k := int(pose["leg"])
		var leg: Dictionary = p["legs"][k]
		var lim: Dictionary = legs.get(String(leg["g"]), {"top": INF, "accel": INF})
		if v.length() > float(lim["top"]) + 0.01 or a > float(lim["accel"]) + 0.01:
			out.append("at %.2f s: leg %d %s/%s %.1f m/s %.1f m/s2  %s -> %s" % [ps[i][0], k, leg["g"], leg["a"], v.length(), a,
					(p["pts"][k] as Vector3).snappedf(0.1), (p["pts"][k + 1] as Vector3).snappedf(0.1)])
	return out


## Each one-shot row's length (s): frames over fps.
static func row_secs(anims: Dictionary) -> Dictionary:
	var out := {}
	for a in anims:
		var spec: Dictionary = anims[a]
		out[a] = float((spec.get("frames", []) as Array).size()) / maxf(1.0, float(spec.get("fps", 8)))
	return out


## The body centre (metres) for talons at `talons` facing `f`, from the sheet's perch offset `po`.
static func centre_on(talons: Vector3, po: Vector2, f: float) -> Vector3:
	return Vector3(talons.x - f * po.x, talons.y + po.y, talons.z)


## "row@from#face" -> [row, from frame, face (0: from the velocity)].
static func parse(a: String) -> Array:
	var face_s := a.get_slice("#", 1) if a.contains("#") else "v"
	var head := a.get_slice("#", 0)
	var from := int(head.get_slice("@", 1)) if head.contains("@") else 0
	return [head.get_slice("@", 0), from, 0.0 if face_s == "v" else float(face_s)]
