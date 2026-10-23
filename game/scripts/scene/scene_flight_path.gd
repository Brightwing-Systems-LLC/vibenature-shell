class_name SceneFlightPath
extends RefCounted

## The way a bird crosses the desktop (Skypatch issue 120,
## Skypatch issue 134), planned whole before it leaves, in
## screen units (window coordinates), sampled at `STEP`.
##
## Flown, not drawn: a body with a heading and a speed steers toward a few waypoints, turning no
## tighter than its turn radius (a few body lengths), with a little wander, slower climbing and
## faster going down. So every bend is an arc and a turn-back is a wide loop, never a corner. Over
## that line the bird flies as a songbird does: bursts of wingbeats that lift it, then wings folded
## and a short ballistic dip (bounding flight); going down, on the approach, and now and then on the
## level it glides on open wings instead. A waypoint may hold it in a hover (a hummingbird at a
## point in the open, a sparrow fluttering for a beat); a leg may be one long glide.
##
## Kinds: `out` (from a perch, out over the scene's edge, across, and off the screen), `out_back`
## (out, over the open desktop, and back into the scene to land), `in` (from off the screen into the
## scene to land). Each flight takes a shape, by chance with the weights in the tuning's `shapes`:
## a long `crossing` to the far side of the open desktop and back, a wide `figure_eight`, a
## `climb_glide` high up the screen and a long glide home, a quick `dart` out and back, a lazy
## `wander` with a hover in the open, or `other_side`: off one edge of the screen and back in from
## another. The open desktop is wherever the scene is not (left, above, right, below it, as the
## scene's real place and the real screen allow), never a fixed box. Company flies `follow`ed paths
## (a second bird chasing, a few swirling round each other and splitting to land), kept within one
## window of the leader. Rare crossers that never land (`plan_crosser`): a hawk circling on a
## thermal high up, a V of geese across the whole screen. Seeded. Pure.

const STEP := 1.0 / 60.0
const FLAP := 0
const BOUND := 1
const GLIDE := 2
const TAKEOFF := 3
const HOVER := 4

const SHAPES := ["crossing", "figure_eight", "climb_glide", "dart", "wander", "other_side"]

var kind := "out"
var shape := ""
## "off_screen" or "home" (back in the scene, for the flock to land it).
var ends := "off_screen"
## Reached its end within `max_sec` (else it was cut there).
var complete := false
var points := PackedVector2Array()
var modes := PackedByteArray()
## The line flown before the bounding is added (for tests: its turn rate).
var guide := PackedVector2Array()
## Which waypoint it was flying to at each point (for probes and tests).
var legs := PackedByteArray()
var waypoints: Array = []
## Window units per second, the most the planner let it fly (for tests).
var top_speed := 0.0
## The tightest turn allowed, radians per second at top speed (for tests).
var turn_radius := 0.0
## Goes off the screen and comes back on purpose (`other_side`).
var leaves_screen := false


func duration() -> float:
	return float(maxi(0, points.size() - 1)) * STEP


func at(time: float) -> Vector2:
	if points.is_empty():
		return Vector2.ZERO
	var f := clampf(time / STEP, 0.0, float(points.size() - 1))
	var i := mini(int(f), points.size() - 1)
	var j := mini(i + 1, points.size() - 1)
	return points[i].lerp(points[j], f - float(i))


## Turns a path planned upside down the right way up, about `axis` (the desktop's top plus bottom): a scene in
## a top corner is planned as if it held the bottom one, so the open desktop below it is "above" for the
## steering, its floor and ceiling (issue 424).
func flip_y(axis: float) -> void:
	for i in points.size():
		points[i] = Vector2(points[i].x, axis - points[i].y)
	for i in guide.size():
		guide[i] = Vector2(guide[i].x, axis - guide[i].y)
	for i in waypoints.size():
		if waypoints[i] is Vector2:
			waypoints[i] = Vector2(waypoints[i].x, axis - waypoints[i].y)


static func flip_rect(r: Rect2, axis: float) -> Rect2:
	return Rect2(r.position.x, axis - r.end.y, r.size.x, r.size.y)


func mode_at(time: float) -> int:
	if modes.is_empty():
		return GLIDE
	return modes[clampi(int(time / STEP), 0, modes.size() - 1)]


## Screen units per second along the drawn path at `time`.
func velocity_at(time: float) -> Vector2:
	if points.size() < 2:
		return Vector2.ZERO
	var i := clampi(int(time / STEP), 0, points.size() - 2)
	return (points[i + 1] - points[i]) / STEP


## Slows a party's paths (the leader's and its followers', one point per STEP each) wherever any of
## them would pass `top` m/s or `accel` m/s², measured over `win` steps (0.2 s) on the line as it
## will be flown, the way `SceneSpeedMeter` measures it, with `per_m` screen units to the metre
## (issue 334). Never squeezes: each stretch of the line takes longer, the same for every bird so
## the party stays together, eased in and out, and the line is resampled at STEP. Returns how much
## longer the flight became.
static func fit(paths: Array, per_m: float, top: float, accel: float, win: int = 12) -> float:
	var lead: SceneFlightPath = paths[0]
	var n := lead.points.size()
	if n < 3 or per_m <= 0.0 or top <= 0.0 or accel <= 0.0:
		return 1.0
	top *= 0.95
	accel *= 0.9
	var raw := PackedFloat32Array()
	raw.resize(n - 1)
	for i in n - 1:
		var r := 0.0
		for p in paths:
			r = maxf(r, ((p as SceneFlightPath).points[i + 1] - (p as SceneFlightPath).points[i]).length())
		raw[i] = maxf(0.5, r / per_m / STEP)
	var w := PackedFloat32Array()
	w.resize(n - 1)
	w.fill(1.0)
	var times := _times(w)
	for _pass in 60:
		var need := PackedFloat32Array()
		need.resize(n - 1)
		need.fill(1.0)
		var over := false
		var segs := _segments(times, int(ceil(times[n - 1] / STEP)) + 1)
		for p in paths:
			var q := _resample((p as SceneFlightPath).points, times, segs)
			for k in q.size() - win:
				var v := (q[k + win] - q[k]) / per_m / (win * STEP)
				var f := 1.0
				if v.length() > top:
					f = v.length() / top
				var span := win
				if k + 2 * win < q.size():
					var v2 := (q[k + 2 * win] - q[k + win]) / per_m / (win * STEP)
					var a := (v2 - v).length() / (win * STEP)
					if a > accel:
						f = maxf(f, sqrt(a / accel))
						span = 2 * win
				if f > 1.0:
					over = true
					for j in range(segs[k], segs[mini(k + span, segs.size() - 1)] + 1):
						need[mini(j, n - 2)] = maxf(need[mini(j, n - 2)], minf(1.2, f))
		if not over:
			break
		for i in n - 1:
			w[i] *= need[i]
		# Eases into and out of each slowed stretch: the slowing itself changes the speed by at most
		# half the acceleration allowed (forward, then backward; only ever slower).
		for i in range(1, n - 1):
			var most := 1.0 / w[i - 1] + accel * 0.5 * STEP * w[i - 1] / raw[i]
			if 1.0 / w[i] > most:
				w[i] = 1.0 / most
		for i in range(n - 3, -1, -1):
			var most := 1.0 / w[i + 1] + accel * 0.5 * STEP * w[i + 1] / raw[i]
			if 1.0 / w[i] > most:
				w[i] = 1.0 / most
		times = _times(w)
	var total := times[n - 1]
	if total <= lead.duration() + STEP * 0.5:
		return 1.0
	var segs := _segments(times, int(ceil(total / STEP)) + 1)
	for p in paths:
		var path: SceneFlightPath = p
		if path.guide.size() == n:
			path.guide = _resample(path.guide, times, segs)
		if path.modes.size() == n:
			path.modes = _pick_at(path.modes, segs)
		if path.legs.size() == n:
			path.legs = _pick_at(path.legs, segs)
		path.points = _resample(path.points, times, segs)
	return total / lead.duration()


## The time each point is reached when each step `i` takes STEP × `w[i]`.
static func _times(w: PackedFloat32Array) -> PackedFloat32Array:
	var times := PackedFloat32Array()
	times.resize(w.size() + 1)
	for i in w.size():
		times[i + 1] = times[i] + STEP * w[i]
	return times


## For each of `count` points at STEP apart, the step of `times` it falls in.
static func _segments(times: PackedFloat32Array, count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var seg := 0
	for k in count:
		var t := float(k) * STEP
		while seg < times.size() - 2 and times[seg + 1] < t:
			seg += 1
		out.append(seg)
	return out


static func _resample(pts: PackedVector2Array, times: PackedFloat32Array, segs: PackedInt32Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in segs.size():
		var seg := segs[k]
		var t := minf(float(k) * STEP, times[times.size() - 1])
		var u := clampf((t - times[seg]) / maxf(1e-6, times[seg + 1] - times[seg]), 0.0, 1.0)
		out.append(pts[seg].lerp(pts[seg + 1], u))
	return out


static func _pick_at(values: PackedByteArray, segs: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	for seg in segs:
		out.append(values[seg])
	return out


## `start`: where it is now (the perch, or ignored for `in`). `land`: the perch it will land on
## (`out_back`, `in`). `scene` and `desktop`: the scene's window and the usable desktop, screen
## units. `bl`: its body length in screen units. `box`: what it covers around its feet (position
## relative to them, and size), to know when it is in or out. `tuning`: the `path` block, already
## bent by the species' style. `want_shape` forces a shape ("" picks by `shapes` weights).
static func plan(path_kind: String, start: Vector2, land: Vector2, scene: Rect2, desktop: Rect2, bl: float, box: Rect2, tuning: Dictionary, seed: int,
		want_shape: String = "") -> SceneFlightPath:
	var p := SceneFlightPath.new()
	p.kind = path_kind
	p.ends = "off_screen" if path_kind == "out" else "home"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	# Like its speed, its turn is a sparrow's: a dove is not half as nimble for being twice as long.
	var r := bl * _rr(rng, tuning["turn_radius_bl"]) * float(tuning.get("speed_scale", 1.0))
	p.turn_radius = r
	var shape := want_shape if want_shape != "" else _pick(tuning.get("shapes", {"crossing": 1.0}), rng)
	p.shape = shape
	var off := float(tuning["off_screen_bl"]) * bl + box.size.length()
	var low := (minf(start.y, land.y) if path_kind != "in" else land.y) - bl * 3.0
	var open := open_areas(scene, desktop, bl, r, low)
	var pts: Array = []
	var holds := {}
	var glides := {}
	if open.is_empty():
		open = [{"side": "top", "rect": Rect2(desktop.position + Vector2(r, r), Vector2(maxf(desktop.size.x - 2.0 * r, 1.0), maxf(scene.position.y - desktop.position.y - 2.0 * r, bl)))}]
	# Out of the scene: up over its top edge (or out its open side when it has no sky above it).
	if path_kind != "in":
		pts.append(_exit_point(start, scene, desktop, bl, open, tuning, rng))
	else:
		start = _edge_point(_pick_edge(scene, desktop, open, "", rng), scene, desktop, off, low, rng)
	var speed_k := _rr(rng, tuning.get("pace", [1.0, 1.0]))
	var wander_k := 1.0
	match shape:
		"crossing":
			var area := _farthest(open, start)
			var rect: Rect2 = area["rect"]
			var far := _far_point(rect, start, rng)
			pts.append(far)
			if path_kind != "out":
				# Turn back with room for the loop: toward the side with more desktop.
				var down := 1.0 if far.y - desktop.position.y < r * 2.5 else (-1.0 if rng.randf() < 0.4 else 1.0)
				var back := -signf(far.x - start.x) if absf(far.x - start.x) > 1.0 else 1.0
				pts.append(_clamp_in(far + Vector2(back * r * 0.4, down * r * 1.7), desktop.grow(-r), low))
		"figure_eight":
			var area := _largest(open)
			var rect: Rect2 = area["rect"]
			var c := rect.get_center() + Vector2(rng.randf_range(-0.2, 0.2) * rect.size.x, rng.randf_range(-0.15, 0.15) * rect.size.y)
			var big := maxf(rect.size.x, rect.size.y * 1.6)
			var rx := clampf(big * rng.randf_range(0.18, 0.26), r * 2.2, maxf(r * 2.2, rect.size.x * 0.5 - r * 0.5))
			var ry := clampf(rx * rng.randf_range(0.45, 0.7), r * 1.6, maxf(r * 1.6, rect.size.y * 0.5 - r * 0.2))
			c.x = clampf(c.x, desktop.position.x + rx * 2.0 + r, maxf(desktop.position.x + rx * 2.0 + r, desktop.end.x - rx * 2.0 - r))
			c.y = clampf(c.y, desktop.position.y + ry + r, maxf(desktop.position.y + ry + r, low - ry - r))
			var turn := 1.0 if rng.randf() < 0.5 else -1.0
			for k in [[-1.0, -1.0], [-2.0, 0.0], [-1.0, 1.0], [0.0, 0.0], [1.0, -1.0], [2.0, 0.0], [1.0, 1.0], [0.0, 0.0]]:
				pts.append(_clamp_in(c + Vector2(float(k[0]) * rx * turn, float(k[1]) * ry), desktop.grow(-r * 0.6), low))
		"climb_glide":
			var top := Vector2(lerpf(start.x, desktop.position.x + desktop.size.x * rng.randf_range(0.2, 0.8), rng.randf_range(0.3, 0.8)),
					desktop.position.y + r * rng.randf_range(1.1, 1.6))
			top.x = clampf(top.x, desktop.position.x + r * 2.0, desktop.end.x - r * 2.0)
			pts.append(top)
			if path_kind != "out":
				# Round at the top, then the long glide home.
				var round := Vector2(top.x + (r * 1.8 if top.x < scene.get_center().x else -r * 1.8), top.y + r * 1.2)
				pts.append(_clamp_in(round, desktop.grow(-r), low))
				glides[pts.size()] = true
		"dart":
			var area := _nearest(open, start)
			var rect: Rect2 = area["rect"]
			var q := _clamp_in(rect.get_center().lerp(start, rng.randf_range(0.4, 0.75)) + Vector2(rng.randf_range(-1.0, 1.0) * r * 2.0, 0.0), rect, low)
			# Far enough out that all of it leaves the scene.
			if scene.grow(box.size.length()).has_point(q):
				q.y = minf(q.y, scene.position.y - box.end.y - r * 1.2)
			pts.append(q)
			speed_k *= float(tuning.get("dart_speed", 1.2))
			if rng.randf() < float(tuning.get("hold_chance", 0.0)):
				holds[pts.size() - 1] = _rr(rng, tuning.get("hold_sec", [0.6, 1.2]))
		"wander":
			speed_k *= float(tuning.get("wander_speed", 0.75))
			wander_k = 2.0
			var n := rng.randi_range(2, 4)
			var hold_at := rng.randi_range(0, n - 1)
			var from := start
			for i in n:
				var area: Dictionary = open[rng.randi() % open.size()] if rng.randf() < 0.5 else _nearest(open, from)
				var rect: Rect2 = area["rect"]
				var q := Vector2(rng.randf_range(rect.position.x, rect.end.x), rng.randf_range(rect.position.y, rect.end.y))
				if from.distance_to(q) < r * 3.0:
					q = _clamp_in(from + (q - from).normalized() * r * 3.5 if q != from else from + Vector2(-r * 3.5, 0), rect, low)
				pts.append(q)
				if i == hold_at or rng.randf() < float(tuning.get("hold_chance", 0.0)):
					holds[pts.size() - 1] = _rr(rng, tuning.get("hold_sec", [0.6, 1.4]))
				from = q
		"other_side":
			var a := _pick_edge(scene, desktop, open, "", rng)
			var b := _pick_edge(scene, desktop, open, a, rng) if path_kind != "out" else a
			var away := _edge_point(a, scene, desktop, off * 1.6, low, rng)
			pts.append(away)
			if path_kind != "out":
				p.leaves_screen = true
				if a != b:
					pts.append(_corner_between(a, b, desktop, off * 3.0))
				pts.append(_edge_point(b, scene, desktop, off * 1.6, low, rng))
				var area := _area_of(open, b)
				var rect: Rect2 = area["rect"]
				pts.append(_clamp_in(rect.get_center() + Vector2(rng.randf_range(-0.3, 0.3) * rect.size.x, rng.randf_range(-0.3, 0.3) * rect.size.y), rect, low))
	if path_kind == "out":
		if shape != "other_side":
			# On and off the screen at the edge it is heading for.
			var last: Vector2 = pts[-1]
			var edge := _nearest_edge(last, scene, desktop, open)
			pts.append(_edge_point(edge, scene, desktop, off, low, rng, last))
	else:
		# Back in over the scene's top edge (or its open side), not low through its bank.
		var last_from: Vector2 = pts[-1] if not pts.is_empty() else start
		var entry := Vector2(lerpf(clampf(last_from.x, scene.position.x, scene.end.x), land.x, 0.45), scene.position.y - bl * 1.5)
		if scene.position.y - desktop.position.y < bl * 4.0:
			entry = Vector2(scene.position.x - bl * 1.5 if last_from.x < scene.position.x else scene.end.x + bl * 1.5, minf(land.y - bl * 3.0, scene.position.y + bl * 4.0))
		pts.append(entry)
		# Then down across the scene's air to just short of the perch, coming at it from the side
		# it is flying from (the perch is above the water, so the line is too).
		var side := signf(land.x - entry.x) if absf(land.x - entry.x) > 1.0 else 1.0
		var short := land + Vector2(-side * bl * 2.5, -bl * 1.5)
		# Where all of it is inside the scene, so it can be handed back there.
		var m := float(tuning["home_margin_bl"]) * bl + bl * 0.5
		short.x = clampf(short.x, scene.position.x - box.position.x + m, scene.end.x - box.end.x - m)
		short.y = clampf(short.y, scene.position.y - box.position.y + m, scene.end.y - box.end.y - m)
		pts.append(short)
	p.waypoints = pts
	_fly(p, start, pts, scene, desktop, bl, box, r, tuning, rng, {"holds": holds, "glides": glides, "speed": speed_k, "wander": wander_k, "floor": low})
	return p


## A rare crosser that never lands: `thermal` (a hawk comes in high, circles slowly on a thermal,
## drifting, then glides off another edge) or `straight` (a V of geese right across the screen).
static func plan_crosser(cross_kind: String, scene: Rect2, desktop: Rect2, bl: float, box: Rect2, tuning: Dictionary, seed: int) -> SceneFlightPath:
	var p := SceneFlightPath.new()
	p.kind = "cross"
	p.shape = cross_kind
	p.ends = "off_screen"
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var r := bl * _rr(rng, tuning["turn_radius_bl"])
	p.turn_radius = r
	var off := float(tuning["off_screen_bl"]) * bl + box.size.length()
	var high := desktop.position.y + desktop.size.y * _rr(rng, tuning.get("height", [0.08, 0.3]))
	var from_left := rng.randf() < 0.5
	var start := Vector2(desktop.position.x - off if from_left else desktop.end.x + off, high + rng.randf_range(-0.05, 0.05) * desktop.size.y)
	var pts: Array = []
	if cross_kind == "thermal":
		var rc := r * _rr(rng, tuning.get("circle_r", [1.2, 1.6]))
		# The circle seen at a slant (flattened), its top near `high`.
		var c := Vector2(desktop.position.x + desktop.size.x * rng.randf_range(0.25, 0.75), high + rc * 0.55)
		var turns := rng.randi_range(2, 3)
		var dir := 1.0 if from_left else -1.0
		var drift := Vector2(rng.randf_range(-0.6, 0.6), rng.randf_range(-0.2, 0.0)) * rc
		for k in turns * 8:
			var a := (PI if from_left else 0.0) + dir * float(k) / 8.0 * TAU
			pts.append(c + Vector2(cos(a), sin(a) * 0.55) * rc + drift * float(k) / 8.0)
		pts.append(Vector2(desktop.end.x + off if from_left else desktop.position.x - off, high + rng.randf_range(-0.08, 0.06) * desktop.size.y))
	else:
		pts.append(Vector2(desktop.end.x + off if from_left else desktop.position.x - off, start.y + rng.randf_range(-0.06, 0.06) * desktop.size.y))
	p.waypoints = pts
	_fly(p, start, pts, scene, desktop, bl, box, r, tuning, rng, {"holds": {}, "glides": {}, "speed": 1.0, "wander": 1.0})
	return p


## A companion's line beside `leader`'s: `role` {kind: "chase" (a second bird a beat behind,
## weaving), "swirl" (a few round each other, spreading apart and coming together, splitting to
## land), "v" (a goose's place in the V); k (its number, from 0), n (how many follow)}. It starts
## from its own `start` and stays within `half` of the leader at every moment (so one window holds
## them all), ending inside the scene when the leader lands.
static func follow(leader: SceneFlightPath, start: Vector2, role: Dictionary, scene: Rect2, bl: float, box: Rect2, half: Vector2, tuning: Dictionary,
		seed: int) -> SceneFlightPath:
	var f := SceneFlightPath.new()
	f.kind = leader.kind
	f.shape = leader.shape
	f.ends = leader.ends
	f.complete = leader.complete
	f.turn_radius = leader.turn_radius
	f.top_speed = leader.top_speed
	f.leaves_screen = leader.leaves_screen
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var k := int(role.get("k", 0))
	var n := maxi(1, int(role.get("n", 1)))
	var what := String(role.get("kind", "chase"))
	var lag := rng.randf_range(0.14, 0.26) if what == "chase" else (0.04 + 0.05 * float(k) if what == "swirl" else 0.0)
	var lag_i := int(lag / STEP)
	var count := leader.points.size()
	var dur := leader.duration()
	var phase := rng.randf() * TAU
	var weave := rng.randf_range(2.0, 3.4)
	var spin := (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(1.6, 2.6)
	var slot := TAU * float(k) / float(n + 1) + rng.randf_range(-0.3, 0.3)
	var split_at := rng.randf_range(0.35, 0.6) * dur
	var m := float(tuning.get("home_margin_bl", 1.0)) * bl + bl * 0.5
	var home := Rect2(scene.position - box.position + Vector2(m, m), scene.size - box.size - Vector2(m, m) * 2.0)
	var blend := float(tuning.get("takeoff_sec", 0.45))
	var max_step := (leader.top_speed * 2.0 + bl * 12.0) * STEP
	var pos := start if leader.kind != "in" and leader.kind != "cross" else leader.points[0] + _offset(what, 0.0, k, slot, phase, weave, spin, split_at, dur, Vector2.RIGHT, bl, half)
	for i in count:
		var t := float(i) * STEP
		var j := maxi(0, i - lag_i)
		var lead := leader.points[i]
		var base := leader.points[j]
		var vel := leader.velocity_at(float(j) * STEP)
		var fwd := vel.normalized() if vel.length() > 1.0 else Vector2.RIGHT
		var target := base + _offset(what, t, k, slot, phase, weave, spin, split_at, dur, fwd, bl, half)
		var rel := target - lead
		target = lead + Vector2(clampf(rel.x, -half.x, half.x), clampf(rel.y, -half.y, half.y))
		if leader.kind != "in" and leader.kind != "cross" and t < blend:
			var u := t / blend
			target = start.lerp(target, u * u * (3.0 - 2.0 * u))
		if leader.ends == "home" and t > dur - 1.0:
			# Coming down: each to its own place inside the scene, apart (they split to land).
			var spread := (target + Vector2(cos(slot), sin(slot) * 0.3) * bl * 1.5).clamp(home.position, home.end)
			target = target.lerp(spread, clampf((t - (dur - 1.0)) / 0.6, 0.0, 1.0))
		var step := target - pos
		pos += step.limit_length(max_step) if i > 0 else step
		# Out of the scene it is always within the leader's window.
		if not scene.encloses(Rect2(pos + box.position, box.size)):
			var d := pos - lead
			pos = lead + Vector2(clampf(d.x, -half.x, half.x), clampf(d.y, -half.y, half.y))
		f.points.append(pos)
		f.guide.append(pos)
		f.modes.append(leader.modes[j])
	return f


static func _offset(what: String, t: float, k: int, slot: float, phase: float, weave: float, spin: float, split_at: float, dur: float,
		fwd: Vector2, bl: float, half: Vector2) -> Vector2:
	var side := Vector2(-fwd.y, fwd.x)
	match what:
		"chase":
			return side * sin(t * weave + phase) * bl * 1.2 - fwd * bl * 0.6
		"swirl":
			# Round each other, and halfway out they spread wide for a few seconds, then close up.
			var spread := 1.0 + 1.6 * exp(-pow((t - split_at) / 1.6, 2.0))
			var a := slot + t * spin
			var rr := bl * (1.4 + 0.5 * sin(t * 0.9 + phase)) * spread
			return Vector2(cos(a) * minf(rr, half.x), sin(a) * minf(rr * 0.6, half.y))
		"v":
			var rank := float(k / 2 + 1)
			var s := 1.0 if k % 2 == 0 else -1.0
			return -fwd * rank * bl * 1.3 + side * s * rank * bl * 0.8 + Vector2(0, sin(t * 1.3 + float(k)) * bl * 0.08)
	return Vector2.ZERO


## The open desktop around the scene: [{side, rect}] for each side with room (left, top, right,
## bottom of the scene), shrunk so a turn fits, and never lower than `low` beside the scene (the
## bird does not cross back low through the scene's ground or water).
static func open_areas(scene: Rect2, desktop: Rect2, bl: float, r: float, low: float) -> Array:
	var out: Array = []
	var m := r * 1.1 + bl
	var cand := {
		"left": Rect2(desktop.position.x, desktop.position.y, scene.position.x - desktop.position.x, minf(desktop.size.y, low - desktop.position.y)),
		"right": Rect2(scene.end.x, desktop.position.y, desktop.end.x - scene.end.x, minf(desktop.size.y, low - desktop.position.y)),
		"top": Rect2(desktop.position.x, desktop.position.y, desktop.size.x, scene.position.y - desktop.position.y),
	}
	for side in cand:
		var rect: Rect2 = cand[side]
		var inner := rect.grow(-m)
		if inner.size.x >= bl * 2.0 and inner.size.y >= bl * 2.0:
			out.append({"side": side, "rect": inner})
	return out


static func _exit_point(start: Vector2, scene: Rect2, desktop: Rect2, bl: float, open: Array, tuning: Dictionary, rng: RandomNumberGenerator) -> Vector2:
	var free_h := scene.position.y - desktop.position.y
	if free_h >= bl * 6.0:
		var toward := _nearest(open, start)
		var dir := signf((toward["rect"] as Rect2).get_center().x - start.x)
		var x := start.x + dir * scene.size.x * rng.randf_range(0.05, 0.25)
		var y := maxf(scene.position.y - free_h * _rr(rng, tuning["exit_rise"]), desktop.position.y + bl * 3.0)
		return Vector2(x, y)
	# No sky above the scene: out of its open side, at the perch's height.
	var left := scene.position.x - desktop.position.x > desktop.end.x - scene.end.x
	return Vector2(scene.position.x - bl * 4.0 if left else scene.end.x + bl * 4.0, start.y - bl * 2.0)


static func _pick_edge(scene: Rect2, desktop: Rect2, open: Array, not_edge: String, rng: RandomNumberGenerator) -> String:
	var edges: Array = []
	for a in open:
		if String(a["side"]) != not_edge:
			edges.append(String(a["side"]))
	if edges.is_empty():
		return "top" if not_edge != "top" else "left"
	return edges[rng.randi() % edges.size()]


## A point just off the screen past `edge`, at a height (or across) the open desktop allows.
static func _edge_point(edge: String, scene: Rect2, desktop: Rect2, off: float, low: float, rng: RandomNumberGenerator, near: Variant = null) -> Vector2:
	var y := rng.randf_range(desktop.position.y + desktop.size.y * 0.05, minf(low, desktop.end.y) - off * 0.2)
	var x := rng.randf_range(desktop.position.x + desktop.size.x * 0.05, desktop.end.x - desktop.size.x * 0.05)
	if near is Vector2:
		y = lerpf(y, (near as Vector2).y, 0.6)
		x = lerpf(x, (near as Vector2).x, 0.6)
	match edge:
		"left":
			return Vector2(desktop.position.x - off, y)
		"right":
			return Vector2(desktop.end.x + off, y)
	return Vector2(x, desktop.position.y - off)


static func _corner_between(a: String, b: String, desktop: Rect2, off: float) -> Vector2:
	var x := desktop.get_center().x
	var y := desktop.position.y - off
	if "left" in [a, b]:
		x = desktop.position.x - off
	elif "right" in [a, b]:
		x = desktop.end.x + off
	if not "top" in [a, b]:
		y = desktop.position.y - off
	return Vector2(x, y)


static func _nearest_edge(q: Vector2, scene: Rect2, desktop: Rect2, open: Array) -> String:
	var best := "top"
	var best_d := q.y - desktop.position.y
	for a in open:
		var side := String(a["side"])
		var d := q.x - desktop.position.x if side == "left" else (desktop.end.x - q.x if side == "right" else q.y - desktop.position.y)
		if d < best_d:
			best_d = d
			best = side
	return best


static func _area_of(open: Array, side: String) -> Dictionary:
	for a in open:
		if String(a["side"]) == side:
			return a
	return open[0]


static func _largest(open: Array) -> Dictionary:
	var best: Dictionary = open[0]
	for a in open:
		if (a["rect"] as Rect2).get_area() > (best["rect"] as Rect2).get_area():
			best = a
	return best


static func _nearest(open: Array, q: Vector2) -> Dictionary:
	var best: Dictionary = open[0]
	var best_d := INF
	for a in open:
		var rect: Rect2 = a["rect"]
		var d := q.distance_to(q.clamp(rect.position, rect.end))
		if d < best_d:
			best_d = d
			best = a
	return best


static func _farthest(open: Array, q: Vector2) -> Dictionary:
	var best: Dictionary = open[0]
	var best_d := -1.0
	for a in open:
		var rect: Rect2 = a["rect"]
		var far := Vector2(rect.position.x if absf(rect.position.x - q.x) > absf(rect.end.x - q.x) else rect.end.x, rect.get_center().y)
		var d := q.distance_to(far)
		if d > best_d:
			best_d = d
			best = a
	return best


## The far end of `rect` from `from`, somewhere along it.
static func _far_point(rect: Rect2, from: Vector2, rng: RandomNumberGenerator) -> Vector2:
	var x_far := rect.position.x if absf(rect.position.x - from.x) > absf(rect.end.x - from.x) else rect.end.x
	var x := lerpf(x_far, rect.get_center().x, rng.randf_range(0.0, 0.25))
	return Vector2(x, rng.randf_range(rect.position.y, rect.end.y))


static func _clamp_in(q: Vector2, rect: Rect2, low: float) -> Vector2:
	var hi := minf(rect.end.y, low)
	return Vector2(clampf(q.x, rect.position.x, maxf(rect.position.x, rect.end.x)), clampf(q.y, rect.position.y, maxf(rect.position.y, hi)))


static func _pick(weights: Dictionary, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for k in weights:
		total += float(weights[k])
	var roll := rng.randf() * total
	var last := ""
	for k in weights:
		last = String(k)
		roll -= float(weights[k])
		if roll <= 0.0:
			return last
	return last


static func _fly(p: SceneFlightPath, start: Vector2, pts: Array, scene: Rect2, desktop: Rect2, bl: float, box: Rect2, r: float,
		tuning: Dictionary, rng: RandomNumberGenerator, legs: Dictionary) -> void:
	var dt := STEP
	var holds: Dictionary = legs["holds"]
	var glides: Dictionary = legs["glides"]
	# Speeds are in body lengths of a sparrow-sized bird (`speed_scale`: that over this bird's
	# length), so a dove is not twice as fast for being twice as long.
	var v0 := bl * _rr(rng, tuning["speed_bl_per_sec"]) * float(legs["speed"]) * float(tuning.get("speed_scale", 1.0))
	var floor_y := float(legs.get("floor", INF))
	p.top_speed = v0 * (1.0 + float(tuning["dive_fast"]))
	var pos := start
	var first: Vector2 = pts[0]
	var dir := (first - pos).normalized()
	if p.kind == "out" or p.kind == "out_back":
		# Up off the perch first, then round toward the way out.
		dir = dir.lerp(Vector2.UP, 0.55).normalized()
	var heading := dir.angle()
	var i := 0
	var t := 0.0
	var max_t := float(tuning["max_sec"])
	var takeoff := float(tuning["takeoff_sec"]) if p.kind == "out" or p.kind == "out_back" else 0.0
	var phase1 := rng.randf() * TAU
	var phase2 := rng.randf() * TAU
	var wander := float(tuning["wander_rad_per_sec"]) * float(legs["wander"])
	var mode := FLAP
	var mode_left := _rr(rng, tuning["flap_sec"])
	var glide_left := 0.0
	var flapped := 0.0
	var h := bl * _rr(rng, tuning["bound_bl"])
	var rise := h / mode_left
	var off := 0.0
	var bound := {}
	var was_out := p.kind == "in" or p.kind == "cross"
	var home := scene.grow(-float(tuning["home_margin_bl"]) * bl)
	var last := pts.size() - 1
	var hover_left := 0.0
	var throttle := 1.0
	var long_glide := 0.0
	var soar := bool(tuning.get("soar", false))
	var seen := false
	while t <= max_t:
		var wp: Vector2 = pts[i]
		var to := wp - pos
		var dist := to.length()
		var forward := Vector2.from_angle(heading)
		if hover_left <= 0.0 and i < last and (dist < r * 0.8 or (to.dot(forward) < 0.0 and dist < r * 1.6)):
			if holds.has(i):
				hover_left = float(holds[i])
				holds.erase(i)
			else:
				i += 1
				continue
		var drawn := pos + Vector2(0.0, off)
		var cover := Rect2(drawn + box.position, box.size)
		if not home.encloses(cover):
			was_out = true
		# Home: on the last leg, inside the scene and near the point short of the perch (the
		# flock lands it from there).
		if p.ends == "home" and i == last and was_out and home.encloses(cover) and (dist < bl * 3.0 or (to.dot(forward) < 0.0 and dist < r)):
			p.complete = true
			break
		if desktop.intersects(cover):
			seen = true
		if p.ends == "off_screen" and i == last and not desktop.intersects(cover) and seen:
			p.complete = true
			break
		# A hover: it slows to a flutter in place, then goes on.
		if hover_left > 0.0:
			hover_left -= dt
			throttle = move_toward(throttle, float(tuning.get("hover_speed", 0.06)), dt * 2.5)
			if hover_left <= 0.0:
				i = mini(i + 1, last)
		else:
			throttle = move_toward(throttle, 1.0, dt * 1.6)
		# Steer: toward the waypoint, no tighter than the turn radius allows, with a little wander.
		var speed := v0 * (1.0 - float(tuning["climb_slow"]) * maxf(0.0, -forward.y) + float(tuning["dive_fast"]) * maxf(0.0, forward.y))
		if takeoff > 0.0:
			speed *= lerpf(float(tuning["takeoff_speed"]), 1.0, clampf(t / (takeoff * 2.0), 0.0, 1.0))
		var landing := p.ends == "home" and i == last
		if landing:
			speed *= clampf(dist / (r * 3.0), 0.35, 1.0)
		speed *= throttle
		var gliding_leg := glides.has(i)
		if gliding_leg:
			speed *= float(tuning.get("glide_leg_speed", 0.85))
		# Hovering it can pivot on the spot; flying it turns no tighter than its radius.
		var max_turn := maxf(speed, v0 * 0.5 if hover_left > 0.0 else 0.0) / r
		if landing:
			# Coming in to land it brakes and banks: slower, so a tighter turn at the same rate.
			max_turn = maxf(max_turn, v0 / r)
		var want := to.angle()
		# Turning back over the scene or under the top of the screen, it turns the way that
		# levels it soonest (over the top of the loop would go out of bounds): 0, or the sign.
		var way := 0.0
		# Over or beside the scene it keeps above the perches' height until the last leg down:
		# it levels off a turn's width above that line rather than dropping through the bank.
		var floor_now := INF if i == last else minf(floor_y, scene.position.y + bl * 2.0)
		if pos.x > scene.position.x - r and pos.x < scene.end.x + r and pos.y > floor_now - r * 1.3 and forward.y > -0.3:
			var across := signf(to.x) if absf(to.x) > 1.0 else signf(forward.x)
			want = Vector2(across, -0.6).angle()
			if forward.y > 0.0:
				way = 1.0 if forward.x < 0.0 else -1.0
		# And under the top of the screen, unless it means to leave over it.
		if p.kind != "cross" and wp.y > desktop.position.y and pos.y < desktop.position.y + minf(r * 1.2, bl * 8.0) and forward.y < 0.3:
			var across2 := signf(to.x) if absf(to.x) > 1.0 else signf(forward.x)
			want = Vector2(across2, 0.6).angle()
			if forward.y < 0.0:
				way = -1.0 if forward.x < 0.0 else 1.0
		var diff := wrapf(want - heading, -PI, PI)
		if way != 0.0 and absf(diff) > 0.3:
			diff = absf(diff) * way
		# A fast, nimble bird steers as hard as it can turn (a slow gain would orbit its mark).
		var turn := clampf(diff * maxf(float(tuning["steer_gain"]), max_turn / 1.2), -max_turn, max_turn)
		turn += wander * (sin(t * 1.3 + phase1) + 0.6 * sin(t * 2.9 + phase2)) / 1.6
		turn = clampf(turn, -max_turn * 1.15, max_turn * 1.15)
		heading += turn * dt
		pos += Vector2.from_angle(heading) * speed * dt
		forward = Vector2.from_angle(heading)
		# How it flies: takeoff, a hover, a glide, or bounding (wingbeats up, wings folded down).
		var gliding := false
		if t < takeoff:
			mode = TAKEOFF
		elif hover_left > 0.0 or throttle < 0.35:
			mode = HOVER
			glide_left = 0.0
		else:
			if glide_left > 0.0:
				glide_left = maxf(0.0, glide_left - dt)
				if glide_left <= 0.0:
					flapped = 0.0
			else:
				flapped += dt
			var approach := p.ends == "home" and i == last and dist < r * 1.2
			# A glide is a few seconds at most, and wingbeats come between glides; on a glide leg
			# (and for a soaring hawk) it is the other way about.
			if glide_left <= 0.0 and mode != BOUND:
				if gliding_leg or soar:
					# Long glides, a few wingbeats now and then to keep up.
					if long_glide < float(tuning.get("long_glide_sec", 3.0)):
						glide_left = 0.25
						long_glide += 0.25
					elif flapped >= float(tuning.get("long_glide_flap_sec", 0.5)):
						long_glide = 0.0
				elif approach:
					glide_left = 0.3
				elif flapped >= float(tuning["flap_between_glides_sec"]):
					if forward.y > float(tuning["glide_slope"]) or (absf(forward.y) < 0.3 and rng.randf() < float(tuning["glide_chance_per_sec"]) * dt):
						glide_left = _rr(rng, tuning["glide_sec"])
			gliding = glide_left > 0.0
			if gliding:
				mode = GLIDE
			else:
				if mode == GLIDE or mode == TAKEOFF or mode == HOVER:
					mode = FLAP
					mode_left = _rr(rng, tuning["flap_sec"])
					h = bl * _rr(rng, tuning["bound_bl"])
					rise = h / mode_left
				mode_left -= dt
				if mode_left <= 0.0:
					if mode == FLAP:
						var b := _rr(rng, tuning["bound_sec"])
						var v_up := -rise
						bound = {"t": 0.0, "dur": b, "off0": off, "v0": v_up, "g": -2.0 * (off + v_up * b) / (b * b)}
						mode = BOUND
						mode_left = b
					else:
						mode = FLAP
						mode_left = _rr(rng, tuning["flap_sec"])
						h = bl * _rr(rng, tuning["bound_bl"])
						rise = h / mode_left
		match mode:
			FLAP:
				off = maxf(off - rise * dt, -h * 1.5)
			BOUND:
				bound["t"] = float(bound["t"]) + dt
				var u := minf(float(bound["t"]), float(bound["dur"]))
				off = float(bound["off0"]) + float(bound["v0"]) * u + 0.5 * float(bound["g"]) * u * u
			HOVER:
				off = move_toward(off, sin(t * 9.0) * bl * 0.05, h * 2.0 * dt)
			_:
				off = move_toward(off, 0.0, h * 2.0 * dt)
		p.guide.append(pos)
		p.points.append(pos + Vector2(0.0, off))
		p.modes.append(mode)
		p.legs.append(mini(i, 255))
		t += dt


static func _rr(rng: RandomNumberGenerator, range_pair: Array) -> float:
	return rng.randf_range(float(range_pair[0]), float(range_pair[1]))
