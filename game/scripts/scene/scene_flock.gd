class_name SceneFlock
extends RefCounted

## A flock of small songbirds (Skypatch issue 104).
## The birds fly as boids in metres (across, up, away), so the flock has depth: it comes in far off
## as specks, wheels toward and away (growing and shrinking), then lands in waves along the oak's
## long branch and the cattail tips (each perch dips under its bird and springs back). Settled, each
## bird has its own small life: looking about, gleaning, hopping along the branch, flitting to
## another perch, dropping to the grass under the oak to peck. One bird going up takes the rest in
## a ripple that spreads by distance, and they leave together, away into the distance or rushing
## past close by.
##
## Projection: a bird `away` metres off is drawn at the scale the bands give that distance, over
## the pond's surface row at that distance (`SceneBehaviour.ground_y`); a perch is turned back
## into metres the same way, so landing is exact.

var beh: SceneBehaviour
var sp: SceneSpecies
var cfg: Dictionary = {}
var birds: Array = []
## arriving, wheeling, landing, settled, leaving
var state := "arriving"
var t := 0.0
var stay := 60.0
var transient := false
var goal := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var palette: Dictionary = {}
var _wheel := {}
var _exit := Vector3.ZERO
var _perches: Array = []
## Every stretch of grass it may drop to (`SceneBehaviour.flock_grounds`); a bird on one keeps its
## index in its perch (`area_i`).
var _grounds: Array = []
var _wheel_left := 0.0
var _land := true
## Leaving away into the distance (not past the side).
var _distant := false
## Leaving into the far treeline (fading among the trees).
var _into_trees := false
var _landing_at := Vector2.INF
## For clips: perches whose piece starts with `prefer` first; `leave` "trees" leaves into the trees.
var prefer := ""
var leave := ""
## Which of the bench's songbirds the party is (`cast` in the species data, Skypatch issue 134),
## or {} for the species' own sheet. Its `habit` says where it settles: perches (and the grass), the
## grass (a dove walking), the oak trunk (a woodpecker clinging and hitching up), the flowers (a
## hummingbird hovering and sipping).
var member: Dictionary = {}
var habit := "perch"
## Set before `setup`: the party comes back out of the far trees and down (after the hawk pass, issue 311).
var come_from_trees := false

## A bird is down (not flying) in any of these.
const DOWN := ["perched", "ground", "cling", "hover"]


## `count` < 0 takes the species' group size; a `passing` flock only goes over.
func setup(owner: SceneBehaviour, species: SceneSpecies, seed: int, count: int = -1, passing: bool = false) -> bool:
	beh = owner
	sp = species
	cfg = beh.tuning["flock"]
	rng.seed = seed
	transient = passing
	var palettes: Array = sp.data.get("palettes", [sp.data.get("colors", {})])
	palette = palettes[rng.randi() % palettes.size()]
	member = SceneSongbirdCast.pick(sp.data.get("cast", []), beh.cast_ctx(), rng, beh.next_cast)
	beh.next_cast = ""
	habit = String(member.get("habit", "perch"))
	var g := sp.range_of("group", [5, 12])
	if member.has("group"):
		g = Vector2(float(member["group"][0]), float(member["group"][1]))
	var n := count if count > 0 else rng.randi_range(int(g.x), int(g.y))
	var s := sp.range_of("stay_min", [1, 5])
	stay = rng.randf_range(s.x, s.y) * 60.0
	_perches = beh.flock_perches()
	_grounds = beh.flock_grounds()
	_land = not passing and not _perches.is_empty() and rng.randf() < float(cfg["land_chance"]) and beh.env_allows_birds()
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var z := rng.randf_range(float(cfg["enter_z"][0]), float(cfg["enter_z"][1]))
	var entry := Vector3(side * (half_width(z) + 4.0), rng.randf_range(float(cfg["enter_y"][0]), float(cfg["enter_y"][1])), z)
	var from_trees := not passing and (come_from_trees or rng.randf() < float(cfg.get("from_trees_chance", 0.0)))
	if from_trees:
		# Out of the far treeline: a speck that grows as it comes (Skypatch issue 147).
		entry = treeline_point()
		side = -signf(entry.x) if absf(entry.x) > 1.0 else side
	for i in n:
		var b := _new_bird(entry, side, from_trees, i)
		birds.append(b)
		_relayer(b)
	if come_from_trees:
		# Back after a scare (the hawk pass, issue 311): straight down where it can, no wheel.
		_land = not _perches.is_empty() and beh.env_allows_birds()
	# Wheel over the water in front of the oak, once or twice, before deciding.
	var c := Vector3(rng.randf_range(-0.3, 0.3) * half_width(30.0), rng.randf_range(float(cfg["wheel_y"][0]), float(cfg["wheel_y"][1])),
			rng.randf_range(float(cfg["wheel_z"][0]), float(cfg["wheel_z"][1])))
	_wheel = {"c": c, "r": rng.randf_range(float(cfg["wheel_r"][0]), float(cfg["wheel_r"][1])), "phi": atan2(entry.z - c.z, entry.x - c.x),
			"dir": -1.0 if rng.randf() < 0.5 else 1.0}
	_wheel_left = rng.randf_range(float(cfg["wheel_sec"][0]), float(cfg["wheel_sec"][1])) * (0.5 if passing else 1.0)
	if habit in ["trunk", "flowers"]:
		# A woodpecker or a hummingbird comes straight in; only a party wheels.
		_wheel_left = minf(_wheel_left, 1.2)
	if come_from_trees:
		_wheel_left = minf(_wheel_left, 1.0)
	state = "wheeling"
	if passing:
		# Straight over: across to the other side, near or far.
		_start_leaving(false, -side)
	beh.note("flock of %d arrives (%s)%s%s" % [n, member.get("id", palette.get("name", "birds")), " passing" if passing else "",
			" out of the trees" if from_trees else ""], sp.id)
	return true


## One bird of the party at `entry` (metres), flying in from `side`, or out of the trees.
func _new_bird(entry: Vector3, side: float, from_trees: bool, i: int) -> Dictionary:
	var speed := sp.speed("fly")
	var look := SceneCreatureLook.new()
	var drawn := sp.pick_sheet(false, rng)
	if not member.is_empty():
		drawn = member.get("tweaks", {}).merged({"id": member["id"]})
	look.setup(sp, palette, rng.randf_range(0.9, 1.1), rng.randi(), String(drawn.get("id", "")), drawn)
	look.density = beh.scene.density
	look.play("fly")
	look.wings = 1.0
	look.flap = rng.randf() * TAU
	var jitter := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * float(cfg["spread_m"])
	var b := {"look": look, "p": entry + jitter * Vector3(1.6, 0.6, 1.6), "v": Vector3(-side * speed, 0, 0), "mode": "boid", "layer": "",
			"wait": 0.0, "act": 0.0, "bound": rng.randf() * 0.5, "flapping": true, "perch": {}, "path": {}, "facing": -side, "id": i}
	if from_trees:
		b["p"] = entry + jitter * Vector3(1.0, 0.3, 0.5)
		b["v"] = Vector3(0, 0.5, -speed)
		b["alpha"] = 0.0
	return b


## The trickle back after the hawk pass (issue 311): `n` more birds come out of the far trees one
## after another and down near where the party is (a free perch near its landing, or the grass for
## a ground bird); with the party in the air they join it, and with it leaving they go with it.
func join_from_trees(n: int) -> int:
	var came := 0
	for i in n:
		var entry := treeline_point()
		var b := _new_bird(entry, -signf(entry.x) if absf(entry.x) > 1.0 else 1.0, true, birds.size())
		if state in ["settled", "landing"]:
			if habit == "ground" and not _grounds.is_empty():
				b["perch"] = _ground_perch(_landing_at)
				b["then"] = "ground"
			else:
				var free := _free_perches()
				if free.is_empty():
					(b["look"] as Node).queue_free()
					continue
				var near := _landing_at if _landing_at != Vector2.INF else (free[0]["at"] as Vector2)
				free.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return (a["at"] as Vector2).distance_to(near) < (c["at"] as Vector2).distance_to(near))
				b["perch"] = free[mini(rng.randi_range(0, 2), free.size() - 1)]
				b["then"] = "perched"
			b["wait"] = rng.randf_range(0.0, 0.8) * float(i)
		birds.append(b)
		_relayer(b)
		if not b["perch"].is_empty() and float(b["wait"]) <= 0.0:
			_go(b)
		came += 1
	return came


## The bird's body length in metres as drawn (the cast member's, else the species').
func length_m() -> float:
	return float(member.get("length", sp.size().x))


func half_width(z: float) -> float:
	return beh.scene.size_pt.x * 0.5 / beh.ppm_at_depth(z)


## A place in the far treeline (metres), where a bird goes into the trees or comes out of them:
## `flock_spread.trees` in the places file (fractions of the frame), else the far bank's scale.
func treeline_point() -> Vector3:
	var spec: Dictionary = beh.places.get("flock_spread", {}).get("trees", {})
	var rows: Array = spec.get("v", [0.25, 0.33])
	var cols: Array = spec.get("u", [0.15, 0.75])
	var at := beh.uv([rng.randf_range(float(cols[0]), float(cols[1])), rng.randf_range(float(rows[0]), float(rows[1]))])
	return metres_of(at, beh.ppm(String(spec.get("band", "far")), at.y))


## The avatar's seat (points), which a bird on the birch looks at now and then.
func _seat() -> Vector2:
	var seat: Dictionary = beh.scene.kit.seat
	if not seat.has("at"):
		return Vector2.INF
	return Vector2(float(seat["at"][0]), float(seat["at"][1])) / beh.scene.density


func screen_of(p: Vector3) -> Vector2:
	var s := beh.ppm_at_depth(p.z)
	return Vector2(beh.scene.size_pt.x * 0.5 + p.x * s, beh.ground_y(p.z) - p.y * s)


func metres_of(at: Vector2, at_ppm: float) -> Vector3:
	var z := beh.depth_of(at_ppm)
	var s := beh.ppm_at_depth(z)
	return Vector3((at.x - beh.scene.size_pt.x * 0.5) / s, (beh.ground_y(z) - at.y) / s, z)


func done() -> bool:
	return birds.is_empty()


func free_birds() -> void:
	for b in birds:
		_release(b)
		(b["look"] as Node).queue_free()
	birds.clear()


func world() -> Vector2:
	if birds.is_empty():
		return Vector2(1e6, 1e6)
	var sum := Vector3.ZERO
	for b in birds:
		sum += b["p"]
	sum /= float(birds.size())
	return Vector2(sum.x, sum.z)


func centre_on_screen() -> Variant:
	var n := 0
	var sum := Vector2.ZERO
	for b in birds:
		if String(b["mode"]) in ["boid", "to_perch"]:
			sum += screen_of(b["p"])
			n += 1
	return sum / float(n) if n > 0 else null


# --- Each frame ---------------------------------------------------------------------------------

func step(dt: float, tint: Color) -> void:
	t += dt
	match state:
		"wheeling":
			_wheel["phi"] = float(_wheel["phi"]) + dt * float(_wheel["dir"]) * sp.speed("fly") * 0.8 / float(_wheel["r"])
			var c: Vector3 = _wheel["c"]
			var r := float(_wheel["r"])
			goal = c + Vector3(cos(float(_wheel["phi"])) * r, sin(t * 0.7) * 1.5, sin(float(_wheel["phi"])) * r * 0.8)
			_wheel_left -= dt
			if _wheel_left <= 0.0:
				if _land:
					_start_landing()
				else:
					_start_leaving(false)
		"landing":
			goal = _perch_centre() + Vector3(0, 2.5, 2.0)
			if _all_down():
				state = "settled"
		"settled":
			if t > stay or (beh.scene.env.rain > float(cfg["rain_leaves"]) and rng.randf() < dt * 0.2):
				_start_leaving(false)
	var neighbours := birds.filter(func(b: Dictionary) -> bool: return String(b["mode"]) == "boid")
	for b in birds.duplicate():
		if float(b["wait"]) > 0.0:
			b["wait"] = float(b["wait"]) - dt
			if float(b["wait"]) <= 0.0:
				_go(b)
		match String(b["mode"]):
			"boid":
				_boid(b, neighbours, dt)
			"to_perch":
				_follow_path(b, dt)
			"perched", "ground", "cling", "hover":
				_settled(b, dt)
		_hold_perch(b)
		_draw_bird(b, dt, tint)
		if String(b["mode"]) == "boid" and _gone(b):
			_release(b)
			(b["look"] as Node).queue_free()
			birds.erase(b)


func _gone(b: Dictionary) -> bool:
	if state != "leaving":
		return false
	var p: Vector3 = b["p"]
	var s := screen_of(p)
	var m := 40.0
	var out := s.x < -m or s.x > beh.scene.size_pt.x + m or s.y < -m
	if not out:
		b["seen"] = true
	# Away into the distance the goal is short of `gone_z` and the boids would circle it for ever:
	# a bird that has nearly reached a distant exit is gone.
	var far := minf(float(cfg["gone_z"]), _exit.z * 0.92) if _distant else float(cfg["gone_z"])
	if _into_trees:
		# Into the far trees: it fades as it reaches them and is gone among them.
		var left := p.distance_to(_exit)
		b["alpha"] = minf(float(b.get("alpha", 1.0)), clampf((left - 1.0) / float(cfg.get("trees_fade_m", 8.0)), 0.0, 1.0))
		return left < 1.5 or float(b["alpha"]) <= 0.02
	return p.z > far or p.z < 2.5 or (out and bool(b.get("seen", false)))


func _boid(b: Dictionary, others: Array, dt: float) -> void:
	var p: Vector3 = b["p"]
	var v: Vector3 = b["v"]
	var sep := Vector3.ZERO
	var align := Vector3.ZERO
	var coh := Vector3.ZERO
	var na := 0
	var nc := 0
	for o in others:
		if o == b:
			continue
		var d: Vector3 = p - (o["p"] as Vector3)
		var dist := d.length()
		if dist < float(cfg["sep_m"]) and dist > 0.001:
			sep += d / (dist * dist)
		if dist < float(cfg["align_m"]):
			align += o["v"]
			na += 1
		if dist < float(cfg["cohere_m"]):
			coh += o["p"]
			nc += 1
	var acc := sep * float(cfg["sep_w"])
	if na > 0:
		acc += (align / float(na) - v) * float(cfg["align_w"])
	if nc > 0:
		acc += (coh / float(nc) - p) * float(cfg["cohere_w"])
	var max_speed := sp.speed("fly") * (1.35 if state == "leaving" else 1.0)
	var to_goal := goal - p
	acc += (to_goal.normalized() * max_speed - v) * float(cfg["goal_w"])
	acc += Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.5, 0.5), rng.randf_range(-1, 1)) * float(cfg["wander"])
	# Undulating flight: a burst of wingbeats, then wings folded and a shallow dip.
	b["bound"] = float(b["bound"]) - dt
	if float(b["bound"]) <= 0.0:
		b["flapping"] = not bool(b["flapping"])
		b["bound"] = rng.randf_range(0.25, 0.5) if bool(b["flapping"]) else rng.randf_range(0.12, 0.28)
	# The dip is drawn, not flown: it must not walk the flock up or down.
	b["dip"] = move_toward(float(b.get("dip", 0.0)), 0.0 if bool(b["flapping"]) else 0.18, dt * 0.9)
	var was := v
	v += acc * dt
	var speed := v.length()
	var lo := max_speed * 0.55
	if speed > max_speed:
		v = v / speed * max_speed
	elif speed < lo and speed > 0.001:
		v = v / speed * lo
	# Never turning or changing speed harder than it can (issue 318).
	if sp.accel_limit() < INF:
		v = was + (v - was).limit_length(sp.accel_limit() * dt)
	b["v"] = v
	b["p"] = p + v * dt
	(b["look"] as SceneCreatureLook).play("fly" if bool(b["flapping"]) else "glide")
	(b["look"] as SceneCreatureLook).wings = 1.0 if bool(b["flapping"]) else 0.35


## Back from a desktop flight onto a perch, pure (issue 318): the ease-out path off the flight's own
## tangent, its speed in the party's metres held under `top` (the flight was fitted on the screen's
## plane at the bird's real distance; here it is in the party's band, so the same speed may be more)
## and taken slowly enough to brake within `accel`, measured as the scene measures it. The scene suite
## on issue 356's branch found a return at 26 m/s and 61 m/s² from the old 0.6 s floor.
static func rejoin_path(from: Vector3, to: Vector3, vel: Vector3, dur: float, top: float, accel: float) -> Dictionary:
	if top < INF:
		vel = vel.limit_length(top * 0.85)
	var path := {}
	for k in 16:
		path = {"from": from, "to": to, "ctrl": from + vel * dur * 0.25, "dur": dur, "u": 0.0}
		var peak := path_peaks(path)
		if (top == INF or peak.x <= top * 0.95) and (accel == INF or peak.y <= accel * 0.9):
			break
		dur *= 1.15
	return path


## The fastest speed and hardest acceleration along an ease-out flit path, over a fifth of a second.
static func path_peaks(path: Dictionary) -> Vector2:
	var h := 1.0 / 30.0
	var dur := float(path["dur"])
	var ps: Array = []
	var a: Vector3 = path["from"]
	var c: Vector3 = path["ctrl"]
	var d: Vector3 = path["to"]
	var t := -0.2
	while t <= dur + 0.4:
		var u := clampf(t / dur, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 2.0)
		# Before it, the bird comes in at its flight speed; after, it sits.
		ps.append(a.lerp(c, e).lerp(c.lerp(d, e), e) + (((c - a) * 4.0 / dur) * t if t < 0.0 else Vector3.ZERO))
		t += h
	var top := 0.0
	var acc := 0.0
	var w := 6
	for i in range(w, ps.size()):
		var v: Vector3 = ((ps[i] as Vector3) - (ps[i - w] as Vector3)) / (w * h)
		top = maxf(top, v.length())
		if i >= 2 * w:
			var was: Vector3 = ((ps[i - w] as Vector3) - (ps[i - 2 * w] as Vector3)) / (w * h)
			acc = maxf(acc, (v - was).length() / (w * h))
	return Vector2(top, acc)


func _follow_path(b: Dictionary, dt: float) -> void:
	var path: Dictionary = b["path"]
	var u := minf(1.0, float(path["u"]) + dt / float(path["dur"]))
	path["u"] = u
	# Down onto a perch from flight it brakes all the way (ease-out); up from rest it speeds up
	# and brakes again (smoothstep), so a flit never starts at full speed (issue 318).
	var e := u * u * (3.0 - 2.0 * u) if String(path.get("ease", "")) == "inout" else 1.0 - pow(1.0 - u, 2.0)
	var a: Vector3 = path["from"]
	var c: Vector3 = path["ctrl"]
	var d: Vector3 = path["to"]
	var prev: Vector3 = b["p"]
	b["p"] = a.lerp(c, e).lerp(c.lerp(d, e), e)
	b["v"] = ((b["p"] as Vector3) - prev) / maxf(dt, 0.001)
	var look: SceneCreatureLook = b["look"]
	var then := String(path.get("then", "perched"))
	look.play("hover" if then == "hover" and u > 0.6 else ("land" if u > 0.78 else "fly"))
	look.wings = 1.0
	if u >= 1.0:
		var perch: Dictionary = b["perch"]
		b["mode"] = then
		b["v"] = Vector3.ZERO
		b["act"] = rng.randf_range(0.5, 2.0)
		look.play({"perched": "perch", "cling": "cling", "hover": "hover"}.get(then, "idle"))
		if then == "perched":
			look.play(_rest_action(b))
		look.wings = 1.0 if then == "hover" else 0.0
		_note_landing(b)
		if then == "cling":
			b["facing"] = 1.0
		elif then == "hover":
			b["facing"] = float(perch.get("facing", 1.0))
		if perch.has("piece"):
			beh.scene.perch_impulse(String(perch["piece"]), perch["at"], Vector2(0, float(cfg["landing_push"])))
		_relayer(b)


## A bird down on a perch or the grass: looks about, gleans, hops, flits, drops down or goes up.
func _settled(b: Dictionary, dt: float) -> void:
	b["act"] = float(b["act"]) - dt
	var look: SceneCreatureLook = b["look"]
	_step_moves(b, dt)
	if float(b["act"]) > 0.0 or state == "leaving":
		return
	var roll := rng.randf()
	var calm := beh.scene.env.rain > 0.2
	if String(b["mode"]) == "cling":
		_cling_beat(b, roll)
		return
	if habit == "trunk" and roll < 0.3 and not beh.trunk_spot(0.0).is_empty():
		# A woodpecker off the trunk goes back to it soon.
		var u := rng.randf_range(0.0, 0.4)
		_fly_to(b, _cling_perch(b, beh.trunk_spot(u), u), "cling", rng.randf_range(0.7, 1.2))
		return
	if String(b["mode"]) == "hover":
		_hover_beat(b, roll)
		return
	if String(b["mode"]) == "ground":
		if roll < 0.45:
			look.play(ground_action(String(b["mode"])))
			b["act"] = rng.randf_range(0.4, 1.6)
		elif roll < 0.8:
			_hop_ground(b)
		elif roll < 0.9:
			look.play("look")
			b["act"] = rng.randf_range(0.6, 2.0)
			if rng.randf() < 0.5:
				b["facing"] = -float(b["facing"])
		else:
			_to_free_perch(b)
		return
	# On a branch, a stalk or a pad: never the ground's pecking (Skypatch issue 147).
	var perch: Dictionary = b["perch"]
	var watch := float(perch.get("watch", 0.0))
	if roll < 0.45 or calm:
		look.play(_rest_action(b) if rng.randf() < 0.5 else "look")
		b["act"] = rng.randf_range(1.2, 4.5)
		var seat := _seat()
		if watch > 0.0 and seat != Vector2.INF and rng.randf() < watch:
			# Birds on the birch keep an eye on the one sitting below.
			b["facing"] = signf(seat.x - (perch["at"] as Vector2).x)
		elif rng.randf() < 0.45:
			b["facing"] = -float(b["facing"])
	elif roll < 0.66:
		# Gleaning: a quick reach forward to a leaf or a seed head and back.
		look.play(_rest_action(b))
		b["glean"] = 0.0
		b["act"] = rng.randf_range(0.6, 1.4)
	elif roll < 0.8 and not perch.get("grip", false):
		_hop_branch(b)
	elif roll < 0.93:
		_to_free_perch(b)
	elif not _grounds.is_empty():
		_to_ground(b)
	else:
		look.play("look")
		b["act"] = 1.0


func _hop_branch(b: Dictionary) -> void:
	var perch: Dictionary = b["perch"]
	var at: Vector2 = perch["at"]
	var p := _ppm(perch)
	var row := _perches.filter(func(q: Dictionary) -> bool: return q["piece"] == perch["piece"])
	var dx := rng.randf_range(0.06, 0.18) * p * (-1.0 if rng.randf() < 0.5 else 1.0)
	var nx := at.x + dx
	var best: Dictionary = {}
	var best_d := 1e9
	for q in row:
		var d := absf((q["at"] as Vector2).x - nx)
		if d < best_d:
			best_d = d
			best = q
	if best.is_empty() or best_d > 0.6 * p:
		(b["look"] as SceneCreatureLook).play("look")
		b["act"] = 0.8
		return
	var y := lerpf(at.y, (best["at"] as Vector2).y, clampf(absf(dx) / maxf(1.0, absf((best["at"] as Vector2).x - at.x)), 0.0, 1.0))
	var moved := perch.duplicate()
	moved["at"] = Vector2(nx, y)
	# Where it lands in metres at the new spot's own scale: on lily pads (the water band) a row's change
	# is a change of depth, and the old scale kept it at the wrong distance until the next hop jumped it
	# there in one step (issue 384: 1.2 m in depth, 29 m/s² against 25). A hop is short, or none.
	var dest := metres_of(moved["at"], _ppm(moved))
	if dest.distance_to(b["p"]) > float(cfg.get("hop_max_m", 0.35)):
		(b["look"] as SceneCreatureLook).play("look")
		b["act"] = 0.8
		return
	b["perch"] = moved
	b["p"] = dest
	b["facing"] = signf(dx)
	(b["look"] as SceneCreatureLook).play("hop")
	b["act"] = 0.35


## What a bird down in `mode` plays for a beat of feeding: pecking only on the ground; perched it
## gleans (its resting pose with a reach, drawn in `_draw_bird`).
static func ground_action(mode: String) -> String:
	return "peck" if mode == "ground" else "perch"


func _hop_ground(b: Dictionary) -> void:
	var at: Vector2 = b["perch"]["at"]
	var area: Dictionary = _grounds[clampi(int(b["perch"].get("area_i", 0)), 0, _grounds.size() - 1)]
	var p := beh.ppm(String(area["band"]), at.y)
	var from: Vector2 = area["from"]
	var to: Vector2 = area["to"]
	var walk := float(member.get("walk_m_per_sec", 0.0))
	var reach := 0.6 if walk > 0.0 else 0.25
	var nx := clampf(at.x + rng.randf_range(-reach, reach) * p, from.x, to.x)
	var ny := clampf(at.y + rng.randf_range(-0.05, 0.05) * p, minf(from.y, to.y), maxf(from.y, to.y))
	b["facing"] = signf(nx - at.x) if absf(nx - at.x) > 0.1 else float(b["facing"])
	if walk > 0.0:
		# A dove walks (head bobbing), it does not hop: the step is covered at its pace.
		var dur := maxf(0.4, Vector2(nx, ny).distance_to(at) / p / walk)
		b["move"] = {"kind": "walk", "from": at, "to": Vector2(nx, ny), "t": 0.0, "dur": dur}
		(b["look"] as SceneCreatureLook).play("walk")
		b["act"] = dur + rng.randf_range(0.1, 0.6)
		return
	var moved := {"at": Vector2(nx, ny), "band": area["band"], "area_i": b["perch"].get("area_i", 0), "area": area["area"]}
	# At the new spot's own scale, and short (issue 384, as on a branch).
	var dest := metres_of(moved["at"], _ppm(moved))
	if dest.distance_to(b["p"]) > float(cfg.get("hop_max_m", 0.35)):
		(b["look"] as SceneCreatureLook).play("look")
		b["act"] = rng.randf_range(0.4, 1.0)
		return
	b["perch"] = moved
	b["p"] = dest
	(b["look"] as SceneCreatureLook).play("hop")
	b["act"] = rng.randf_range(0.25, 0.5)


## Moves that take time while a bird is down: a dove's walk, a woodpecker's hitch up the trunk.
func _step_moves(b: Dictionary, dt: float) -> void:
	var move: Dictionary = b.get("move", {})
	if move.is_empty():
		b["v"] = Vector3.ZERO
		return
	move["t"] = float(move["t"]) + dt
	var u := clampf(float(move["t"]) / float(move["dur"]), 0.0, 1.0)
	var from: Vector2 = move["from"]
	var to: Vector2 = move["to"]
	var perch: Dictionary = b["perch"]
	var p := _ppm(perch)
	var at := from.lerp(to, u)
	if String(move["kind"]) == "hitch":
		# A hop up the bark: tail and feet push off, the body swings out a touch and back in.
		var e := u * u * (3.0 - 2.0 * u)
		at = from.lerp(to, e) + Vector2(-sin(PI * u) * 0.012 * p, 0.0)
	var prev: Vector2 = perch["at"]
	perch = perch.duplicate()
	perch["at"] = at
	b["perch"] = perch
	b["p"] = metres_of(at, p)
	b["v"] = Vector3((at.x - prev.x) / p, (prev.y - at.y) / p, 0.0) / maxf(dt, 0.001)
	if u >= 1.0:
		b.erase("move")
		if String(move["kind"]) == "walk":
			(b["look"] as SceneCreatureLook).play("idle")


## A woodpecker on the trunk: drums and probes at the bark, looks round the trunk, hitches up it in
## a few quick hops (tail braced), and from high up drops back down to work up again; now and then
## it goes to the oak's branch.
func _cling_beat(b: Dictionary, roll: float) -> void:
	var look: SceneCreatureLook = b["look"]
	var perch: Dictionary = b["perch"]
	var u := float(perch.get("u", 0.0))
	if roll < 0.38:
		var d := rng.randf_range(0.8, 2.4)
		look.play("cling_peck", d)
		b["act"] = d
	elif roll < 0.55:
		look.play("cling")
		b["act"] = rng.randf_range(0.6, 1.8)
	elif roll < 0.92 and u < 0.92:
		# Up the bark in a short run of hitches.
		var hops := rng.randi_range(1, 3)
		var nu := minf(1.0, u + rng.randf_range(0.04, 0.08))
		var spot := beh.trunk_spot(nu)
		if spot.is_empty():
			b["act"] = 0.5
			return
		var to := _cling_anchor(b, spot)
		b["move"] = {"kind": "hitch", "from": perch["at"], "to": to, "t": 0.0, "dur": rng.randf_range(0.11, 0.16)}
		perch = perch.duplicate()
		perch["u"] = nu
		perch["face"] = spot["at"]
		b["perch"] = perch
		look.play("cling")
		b["act"] = float(b["move"]["dur"]) + (rng.randf_range(0.05, 0.12) if hops > 1 else rng.randf_range(0.3, 0.9))
	elif u >= 0.92 or roll < 0.985:
		var spot := beh.trunk_spot(rng.randf_range(0.0, 0.3))
		if not spot.is_empty():
			_fly_to(b, _cling_perch(b, spot, rng.randf_range(0.0, 0.3)), "cling", rng.randf_range(0.7, 1.1))
	else:
		_to_free_perch(b)


## Where the bird's anchor goes so its claws hold the trunk face at `face` (points): the sheet's
## cling frames draw the trunk face at `trunk_face_px` from the anchor.
func _cling_anchor(b: Dictionary, spot: Dictionary) -> Vector2:
	var off: Array = member.get("trunk_face_px", [17, -18])
	var k := _pt_per_sheet_px(b, spot)
	return (spot["at"] as Vector2) - Vector2(float(off[0]), float(off[1])) * k


func _cling_perch(b: Dictionary, spot: Dictionary, u: float) -> Dictionary:
	return {"at": _cling_anchor(b, spot), "face": spot["at"], "band": spot["band"], "u": u, "cling": true}


## A hummingbird at the flowers: hovers, sips at a flower head, darts to the next.
func _hover_beat(b: Dictionary, roll: float) -> void:
	var look: SceneCreatureLook = b["look"]
	if roll < 0.45:
		var d := rng.randf_range(1.0, 2.2)
		look.play("sip", d)
		b["act"] = d
	elif roll < 0.62:
		look.play("hover")
		b["act"] = rng.randf_range(0.4, 1.2)
		if rng.randf() < 0.4:
			b["facing"] = -float(b["facing"])
	else:
		var flowers := beh.flower_spots()
		if flowers.is_empty():
			return
		_fly_to(b, _hover_perch(b, flowers[rng.randi() % flowers.size()]), "hover", rng.randf_range(0.3, 0.55))


## Where a hummingbird hovers to sip at `flower`: its bill tip at the flower head, from either side.
func _hover_perch(b: Dictionary, flower: Dictionary) -> Dictionary:
	var bill: Array = member.get("bill_px", [19, -19])
	var k := _pt_per_sheet_px(b, flower)
	var facing := 1.0 if rng.randf() < 0.6 else -1.0
	var at: Vector2 = flower["at"]
	return {"at": at - Vector2(float(bill[0]) * facing, float(bill[1])) * k, "flower": at, "band": flower["band"], "facing": facing}


## Points per px of the sheet's master drawing for the bird drawn at `place` ({at, band}): the
## whole-px scale `SceneSheet.pick_scale` will choose there.
func _pt_per_sheet_px(b: Dictionary, place: Dictionary) -> float:
	var look: SceneCreatureLook = b["look"]
	var s := _ppm(place)
	s *= sp.show_scale(String(place.get("band", "mid")), s * beh.scene.density)
	if look.sheet == null:
		return s / SceneCreatureLook.MASTER_PX_PER_M
	var entry: Dictionary = look.sheet.sets["side"]
	var pick := SceneSheet.pick_scale(entry, s * beh.scene.density)
	if String(pick[0]) == "master":
		return float(pick[1]) / beh.scene.density
	return s / look.sheet.master_ppm


func _to_free_perch(b: Dictionary) -> void:
	var free := _free_perches()
	if free.is_empty():
		return
	# A flit goes to one of the perches nearest (the scene is wide: never the birch to the reeds).
	# Nearest in metres, depth included (issue 318): a perch just above on screen may be on the far
	# bank, eighty metres back; a flit never goes further than `flit_max_m`.
	var here: Vector3 = b["p"]
	for q in free:
		q["dist_m"] = here.distance_to(metres_of(q["at"], _ppm(q)))
	free.sort_custom(func(q: Dictionary, r: Dictionary) -> bool: return float(q["dist_m"]) < float(r["dist_m"]))
	var options := free.slice(0, 5).filter(func(q: Dictionary) -> bool: return float(q["dist_m"]) <= float(cfg.get("flit_max_m", 10.0)))
	if options.is_empty():
		(b["look"] as SceneCreatureLook).play("look")
		b["act"] = rng.randf_range(0.6, 2.0)
		return
	var total := 0.0
	for q in options:
		total += _perch_liking(q)
	var roll := rng.randf() * total
	var perch: Dictionary = options[-1]
	for q in options:
		roll -= _perch_liking(q)
		if roll <= 0.0:
			perch = q
			break
	_fly_to(b, perch, "perched", rng.randf_range(0.6, 1.4))
	if (b["perch"] as Dictionary).has("piece"):
		beh.scene.perch_impulse(String(b["perch"]["piece"]), b["perch"]["at"], Vector2(0, float(cfg["takeoff_push"])))


func _to_ground(b: Dictionary) -> void:
	# Down to grass near it in metres (issue 318): a few picks, the nearest kept, none past `flit_max_m`.
	var best: Dictionary = {}
	var best_m := INF
	for i in 6:
		var g := _ground_perch((b["perch"] as Dictionary).get("at", Vector2.INF))
		var m := (b["p"] as Vector3).distance_to(metres_of(g["at"], _ppm(g)))
		if m < best_m:
			best = g
			best_m = m
	if best_m > float(cfg.get("flit_max_m", 10.0)):
		(b["look"] as SceneCreatureLook).play("look")
		b["act"] = rng.randf_range(0.6, 2.0)
		return
	_fly_to(b, best, "ground", rng.randf_range(0.7, 1.3))


## A place on one of the grounds, by their weights (from a perch at `near`, the nearer grass far
## likelier): {at, band, area_i, area}.
func _ground_perch(near: Vector2 = Vector2.INF) -> Dictionary:
	var weights: Array = []
	var total := 0.0
	for g in _grounds:
		var w := float(g.get("weight", 1.0))
		if near != Vector2.INF:
			var mid := ((g["from"] as Vector2) + (g["to"] as Vector2)) * 0.5
			w /= 1.0 + pow(mid.distance_to(near) / 120.0, 2.0)
		weights.append(w)
		total += w
	var roll := rng.randf() * total
	var i := 0
	for j in _grounds.size():
		roll -= float(weights[j])
		i = j
		if roll <= 0.0:
			break
	var g: Dictionary = _grounds[i]
	return {"at": (g["from"] as Vector2).lerp(g["to"], rng.randf()), "band": g["band"], "area_i": i, "area": g["area"]}


func _fly_to(b: Dictionary, perch: Dictionary, then: String, dur: float) -> void:
	var at: Vector2 = perch["at"]
	var to := metres_of(at, _ppm(perch))
	var from: Vector3 = b["p"]
	var ctrl := (from + to) * 0.5 + Vector3(0, float(cfg["arc_m"]), 0)
	b["perch"] = perch
	b["mode"] = "to_perch"
	b["path"] = {"from": from, "to": to, "ctrl": ctrl, "dur": dur, "u": 0.0, "then": then, "ease": "inout"}
	_fit_flight(b["path"])
	b["facing"] = signf(to.x - from.x) if absf(to.x - from.x) > 0.01 else float(b["facing"])
	_relayer(b)


## The eased point of a flight path at `u` (0..1).
static func path_point(path: Dictionary, u: float) -> Vector3:
	var e := u * u * (3.0 - 2.0 * u) if String(path.get("ease", "")) == "inout" else 1.0 - pow(1.0 - u, 2.0)
	var a: Vector3 = path["from"]
	var c: Vector3 = path["ctrl"]
	var d: Vector3 = path["to"]
	return a.lerp(c, e).lerp(c.lerp(d, e), e)


## A flight path takes as long as it must to stay inside the species' top speed and acceleration
## (issue 318): measured along the path, with the speed it starts at; slowed, never squeezed.
func _fit_flight(path: Dictionary) -> void:
	var top := sp.gait_limit("fly").y
	var acc := sp.accel_limit()
	if top == INF:
		return
	var n := 40
	for k in 6:
		var dur := float(path["dur"])
		var h := dur / float(n)
		var peak := 0.0
		var peak_a := 0.0
		var last_v: Variant = path.get("v0", Vector3.ZERO if String(path.get("ease", "")) == "inout" else null)
		var last := path_point(path, 0.0)
		for i in range(1, n + 1):
			var q := path_point(path, float(i) / float(n))
			var v := (q - last) / h
			peak = maxf(peak, v.length())
			if last_v != null:
				peak_a = maxf(peak_a, (v - (last_v as Vector3)).length() / h)
			last_v = v
			last = q
		var f := maxf(peak / top, sqrt(peak_a / acc) if acc < INF else 0.0)
		if f <= 1.0:
			return
		path["dur"] = dur * f * 1.02
		if path.has("v0"):
			path["ctrl"] = (path["from"] as Vector3) + (path["v0"] as Vector3) * float(path["dur"]) * 0.25


func _free_perches() -> Array:
	var taken := {}
	for b in birds:
		var perch: Dictionary = b["perch"]
		if perch.has("piece"):
			taken[str(perch["at"])] = true
	var out := _perches.filter(func(q: Dictionary) -> bool: return not taken.has(str(q["at"])))
	_shuffle(out)
	return out


## Shuffles `a` in place with the party's own dice. `Array.shuffle` draws from Godot's global generator,
## seeded anew every run, so a party's landings were never the same twice on one seed and the speed
## sweep could not replay an over it found (issue 427).
func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = a[i]
		a[i] = a[j]
		a[j] = tmp


## How much the party's species likes `perch` (`perch_weights` by piece-id prefix: a wren the
## reeds, waxwings the top of the oak).
func _perch_liking(perch: Dictionary) -> float:
	var likes: Dictionary = member.get("perch_weights", {})
	var piece := String(perch.get("piece", ""))
	for prefix in likes:
		if piece.begins_with(String(prefix)):
			return float(likes[prefix])
	return 1.0


func _perch_centre() -> Vector3:
	var sum := Vector3.ZERO
	var n := 0
	for b in birds:
		if (b["perch"] as Dictionary).has("at"):
			sum += metres_of(b["perch"]["at"], _ppm(b["perch"]))
			n += 1
	return sum / float(n) if n > 0 else goal


func _all_down() -> bool:
	for b in birds:
		if not String(b["mode"]) in DOWN:
			return false
	return true


## Lands in waves: the birds are split into two or three groups that come down a second or two
## apart, each bird a little after the one before; most take a perch, a few drop to the grass.
func _start_landing() -> void:
	state = "landing"
	var free := _free_perches()
	# Weighted shuffle: each perch draws its key once (a comparator must not roll dice).
	# A party seldom comes down where one of the last few did (issue 272).
	var recent: Array = beh.recent_places("songbird_land")
	var apart := float(cfg.get("land_apart_pt", 30.0))
	for q in free:
		q["key"] = float(q.get("weight", 1.0)) * _perch_liking(q) * rng.randf() * (1000.0 if prefer != "" and String(q.get("piece", "")).begins_with(prefer) else 1.0)
		if SceneVariety.nearest(q["at"], recent) < apart:
			q["key"] = float(q["key"]) * 0.05
	free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["key"]) > float(b["key"]))
	# The party comes down together: the first pick decides where, the rest take perches near it.
	if not free.is_empty():
		var anchor: Vector2 = free[0]["at"]
		var reach := float(cfg.get("party_reach_pt", 120.0))
		for q in free:
			q["key"] = float(q["key"]) / (1.0 + pow((q["at"] as Vector2).distance_to(anchor) / reach, 2.0)) + (1e6 if q["at"] == anchor else 0.0)
		free.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["key"]) > float(b["key"]))
		_landing_at = anchor
		beh.remember_place("songbird_land", anchor)
	var order := birds.duplicate()
	_shuffle(order)
	var waves := rng.randi_range(2, 3)
	var per := ceili(float(order.size()) / float(waves))
	var wave_t := 0.0
	for i in order.size():
		var b: Dictionary = order[i]
		if i % per == 0 and i > 0:
			wave_t += rng.randf_range(float(cfg["wave_gap_sec"][0]), float(cfg["wave_gap_sec"][1]))
		var ground := not _grounds.is_empty() and (free.is_empty() or rng.randf() < float(member.get("ground_share", cfg["ground_share"])))
		if habit == "trunk" and not beh.trunk_spot(0.0).is_empty():
			var u := rng.randf_range(0.0, 0.45)
			b["perch"] = _cling_perch(b, beh.trunk_spot(u), u)
			b["then"] = "cling"
		elif habit == "flowers" and not beh.flower_spots().is_empty():
			var flowers := beh.flower_spots()
			b["perch"] = _hover_perch(b, flowers[rng.randi() % flowers.size()])
			b["then"] = "hover"
		elif ground:
			b["perch"] = _ground_perch(_landing_at)
			b["then"] = "ground"
		else:
			b["perch"] = free.pop_front()
			b["then"] = "perched"
		b["wait"] = wave_t + rng.randf_range(0.0, float(cfg["wave_jitter_sec"]))
		b["mode"] = "boid"
	beh.note("flock lands in %d waves" % waves, sp.id)
	_sound("flock_land")


## Called when a bird's wait runs out: landing birds start down, leaving birds go up.
func _go(b: Dictionary) -> void:
	if state == "leaving":
		if String(b["mode"]) in DOWN:
			var perch: Dictionary = b["perch"]
			if perch.has("piece"):
				beh.scene.perch_impulse(String(perch["piece"]), perch["at"], Vector2(0, float(cfg["takeoff_push"])))
			# Up off the perch from rest: the flock's steering speeds it up within its limits (issue 318).
			b["v"] = Vector3(rng.randf_range(-1, 1) * 0.3, 1.0, rng.randf_range(-1, 1) * 0.3)
		b["mode"] = "boid"
		b["perch"] = {}
		_relayer(b)
		return
	var perch: Dictionary = b["perch"]
	if perch.is_empty():
		return
	var at: Vector2 = perch["at"]
	var to := metres_of(at, _ppm(perch))
	var from: Vector3 = b["p"]
	var dist := from.distance_to(to)
	b["mode"] = "to_perch"
	# Coming in from flight it leaves the flock on its own heading and speed (the path eases out, so
	# its control point is a quarter of the way at that speed) and brakes onto the perch (issue 318).
	var path := {"from": from, "to": to, "ctrl": from.lerp(to, 0.55) + Vector3(0, float(cfg["arc_m"]) * 1.5, 0),
			"dur": clampf(dist / (sp.speed("fly") * 0.75), 1.0, 4.5), "u": 0.0, "then": String(b.get("then", "perched"))}
	if (b["v"] as Vector3).length() > 0.1:
		path["v0"] = b["v"]
		path["ctrl"] = from + (b["v"] as Vector3) * float(path["dur"]) * 0.25
	b["path"] = path
	_fit_flight(path)


## The party's typed scene event (issue 413), from the first of its birds drawn on screen: the flock's
## standard kinds, `flock_takeoff` and `flock_land` (proposal 2026-10-21-sound-in-packages §6).
func _sound(kind: String) -> void:
	for b in birds:
		var at := screen_of(b["p"])
		if (b["look"] as CanvasItem).is_visible_in_tree():
			beh.sound_event(kind, b["look"], {"pos": at, "species": String(member.get("id", sp.id)), "band": "mid",
					"depth_m": float((b["p"] as Vector3).z)})
			return


## Up and away: one bird first, the rest after it in a ripple that spreads with distance.
func _start_leaving(hurry: bool, toward_side: float = 0.0) -> void:
	if state == "leaving":
		return
	if birds.any(func(b: Dictionary) -> bool: return String(b["mode"]) in DOWN):
		_sound("flock_takeoff")
	state = "leaving"
	var side := toward_side if toward_side != 0.0 else (-1.0 if rng.randf() < 0.5 else 1.0)
	if toward_side != 0.0:
		var z := rng.randf_range(float(cfg["pass_z"][0]), float(cfg["pass_z"][1]))
		_exit = Vector3(side * (half_width(z) + 10.0), rng.randf_range(float(cfg["enter_y"][0]), float(cfg["enter_y"][1])), z)
	elif leave == "" and rng.randf() < float(cfg["toward_chance"]):
		var z := rng.randf_range(4.0, 6.0)
		_exit = Vector3(side * (half_width(z) + 6.0), rng.randf_range(3.0, 6.0), z)
		beh.note("flock leaves toward us", sp.id)
	elif leave == "trees" or (leave == "" and rng.randf() < float(cfg.get("into_trees_chance", 0.0)) / maxf(0.01, 1.0 - float(cfg["toward_chance"]))):
		_into_trees = true
		_exit = treeline_point()
		beh.note("flock leaves into the trees", sp.id)
	else:
		var z := rng.randf_range(100.0, 140.0)
		_distant = true
		_exit = Vector3(side * half_width(z) * rng.randf_range(0.2, 1.3), rng.randf_range(14.0, 24.0), z)
		beh.note("flock leaves into the distance", sp.id)
	goal = _exit
	if birds.is_empty():
		return
	var first: Dictionary = birds[rng.randi() % birds.size()]
	var origin: Vector3 = first["p"]
	for b in birds:
		var d := (b["p"] as Vector3).distance_to(origin)
		var base := 0.0 if b == first else float(cfg["cascade_sec"]) * (0.4 if hurry else 1.0)
		b["wait"] = base + d * float(cfg["cascade_per_m"]) * (0.5 if hurry else 1.0) + rng.randf_range(0.0, 0.15 if hurry else 0.5)
		if String(b["mode"]) == "boid":
			b["wait"] = 0.0


## A bird back from a desktop flight at `at_pt` (scene points) going `v_pt` (points a second),
## drawn at `s` points per metre: it joins the party again and comes down where its kind settles
## (a free perch, `meant` first; the trunk; the flowers; the grass), or, with the party on its way
## out, goes with it.
func rejoin(b: Dictionary, at_pt: Vector2, v_pt: Vector2, s: float, meant: Dictionary) -> void:
	var target: Dictionary = {}
	var then := "perched"
	if state in ["settled", "landing", "wheeling"]:
		if habit == "trunk" and not beh.trunk_spot(0.0).is_empty():
			var u := rng.randf_range(0.0, 0.4)
			target = _cling_perch(b, beh.trunk_spot(u), u)
			then = "cling"
		elif habit == "flowers" and not beh.flower_spots().is_empty():
			var flowers := beh.flower_spots()
			target = _hover_perch(b, flowers[rng.randi() % flowers.size()])
			then = "hover"
		elif habit == "ground" and not _grounds.is_empty():
			target = _ground_perch()
			then = "ground"
		else:
			var free := _free_perches()
			for q in free:
				if q["at"] == meant.get("at") and q.get("piece") == meant.get("piece"):
					free.erase(q)
					free.push_front(q)
					break
			if not free.is_empty():
				target = free[0]
	b["layer"] = ""
	b["wait"] = 0.0
	if target.is_empty():
		var z := beh.depth_of(s / maxf(sp.show_scale("mid"), 0.01))
		var ppm := beh.ppm_at_depth(z)
		b["p"] = metres_of(at_pt, ppm)
		b["v"] = Vector3(v_pt.x / ppm, -v_pt.y / ppm, 0.0)
		b["mode"] = "boid"
		b["perch"] = {}
		if state != "leaving":
			_start_leaving(false)
	else:
		var ppm := _ppm(target)
		var from := metres_of(at_pt, ppm)
		var to := metres_of(target["at"], ppm)
		var vel := Vector3(v_pt.x / ppm, -v_pt.y / ppm, 0.0)
		var dur := clampf(from.distance_to(to) / maxf(vel.length() * 0.7, 0.5), 0.6, 2.2)
		b["p"] = from
		b["perch"] = target
		b["mode"] = "to_perch"
		# Leaving the flight's line on its own tangent (the path eases out, so it starts at
		# twice the mean speed): no kink where the flock takes over.
		b["path"] = rejoin_path(from, to, vel, dur, sp.top_speed(), sp.accel_limit())
		b["path"]["then"] = then
	birds.append(b)
	_relayer(b)
	if not beh.flocks.has(self):
		beh.flocks.append(self)


## Turn end: the flock settles, landing now if it meant to land; perched birds sit still a while.
func settle() -> void:
	if state == "wheeling" and _land:
		_start_landing()
	for b in birds:
		if String(b["mode"]) in DOWN:
			(b["look"] as SceneCreatureLook).play(_rest_action(b))
			b["act"] = rng.randf_range(2.5, 5.0)


## A flock that is a hand-off's big moment comes down after its wheel (where it can), so its tail
## plays where the eye landed rather than over an empty sky.
func land_for_moment() -> void:
	_land = not _perches.is_empty() and beh.env_allows_birds()


## A beat of the big moment's tail (issue 239): once the flock is down, a few birds flit to other
## perches near where it landed. False while it is still in the air or leaving.
func tail(_beat: int) -> bool:
	if state != "settled":
		return false
	gesture()
	return true


## Turn start with the flock as the moment: a few birds shift perches, or the flock wheels round once more.
func gesture() -> void:
	if state == "settled":
		var n := rng.randi_range(2, 4)
		for b in birds:
			if n <= 0:
				break
			if String(b["mode"]) == "perched":
				b["act"] = 0.0
				_to_free_perch(b)
				n -= 1
	elif state == "wheeling":
		_wheel_left += 3.0


func perceive(creatures: Array) -> void:
	if birds.is_empty() or state == "leaving":
		return
	var disturbed: Dictionary = sp.data.get("disturbed_by", {})
	for c in creatures:
		var other: SceneCreature = c
		if other.alpha < 0.3:
			continue
		var ow := other.world()
		var fear := sp.fear_of(other.sp.id)
		var near := 1e9
		var nearest: Dictionary = {}
		for b in birds:
			var p: Vector3 = b["p"]
			var d := Vector2(p.x, p.z).distance_to(ow)
			if d < near:
				near = d
				nearest = b
		if fear > 0.0 and near < fear:
			flush("%s at %.0f m" % [other.sp.id, near])
			return
		var dist := float(disturbed.get(other.sp.id, 0.0))
		if dist > 0.0 and other.is_moving():
			for b in birds:
				var p: Vector3 = b["p"]
				if String(b["mode"]) == "ground" and Vector2(p.x, p.z).distance_to(ow) < dist:
					_to_free_perch(b)
					beh.note("ground birds go up from the %s" % other.sp.id, sp.id)


## Up all at once. Put up by a predator, the burst of wings is an alarm others run from; put up by
## someone else's alarm, it is only heard and watched.
func flush(why: String, predator: bool = true) -> void:
	if state == "leaving":
		return
	beh.note("flock flushes (%s)" % why, sp.id)
	_start_leaving(true)
	var c: Variant = _any_screen()
	if c != null:
		beh.alarm(self, c, beh.ppm("mid", (c as Vector2).y), float(sp.data.get("alarm", {}).get("radius_m", 0.0)), "wings going up",
				"flee" if predator else "call")


func _any_screen() -> Variant:
	for b in birds:
		return screen_of(b["p"])
	return null


func hear_alarm(closeness: float, level: String = "flee") -> void:
	if state == "leaving":
		return
	if level == "flee" and rng.randf() < float(sp.data.get("heeds", 0.8)) * (1.0 - closeness * 0.6):
		flush("an alarm", false)
	else:
		for b in birds:
			if String(b["mode"]) in DOWN:
				(b["look"] as SceneCreatureLook).play("look" if String(b["mode"]) in ["perched", "ground"] else _rest_action(b))
				b["act"] = rng.randf_range(1.0, 3.0)


# --- Drawing ------------------------------------------------------------------------------------

## Points per metre for a perch: from the foot of the piece it is on (a cattail's tip is far up
## the water band's rows, but the bird is as near as the cattail's root).
func _ppm(perch: Dictionary) -> float:
	var at: Vector2 = perch["at"]
	return beh.ppm(String(perch["band"]), float(perch.get("scale_y", at.y)))


## The resting action for a bird that is down: perched, on the grass, clinging, hovering.
func _rest_action(b: Dictionary) -> String:
	if String(b["mode"]) == "perched" and bool((b["perch"] as Dictionary).get("grip", false)) and _has_cling(b):
		return "cling"
	return {"perched": "perch", "cling": "cling", "hover": "hover"}.get(String(b["mode"]), "idle")


## Whether the bird's sheet draws a clinging pose (only the woodpecker's does so far).
func _has_cling(b: Dictionary) -> bool:
	var look: SceneCreatureLook = b["look"]
	return look.sheet != null and look.sheet.resolve("cling") == "cling"


## A bird's weight on its perch: a stalk leans and dips under it while it sits and springs back when
## it goes (`scene.perch_hold`; `perch_load` in the flock tuning, points, by the piece's kind).
func _hold_perch(b: Dictionary) -> void:
	var perch: Dictionary = b["perch"]
	var want := ""
	if String(b["mode"]) == "perched" and perch.has("piece"):
		want = String(perch["piece"])
	var had := String(b.get("held", ""))
	if want == had and (want == "" or b.get("held_at") == perch["at"]):
		return
	_release(b)
	if want == "":
		return
	var kind := String(beh.scene.kit.piece(want).get("kind", ""))
	var loads: Dictionary = cfg.get("perch_load", {})
	var load: Array = loads.get(kind, loads.get("default", [0.0, 0.0]))
	var push := Vector2(float(load[0]) * float(b["facing"]), float(load[1])) * length_m() / 0.2
	if beh.scene.perch_hold(want, _key(b), perch["at"], push):
		b["held"] = want
		b["held_at"] = perch["at"]


func _release(b: Dictionary) -> void:
	if String(b.get("held", "")) != "":
		beh.scene.perch_release(String(b["held"]), _key(b))
	b["held"] = ""


func _key(b: Dictionary) -> String:
	return "%d:%s" % [get_instance_id(), str(b.get("id", 0))]


## Every landing, for the heatmap (`tools/landing_map.gd`): off unless `landing_log` is an array.
static var landing_log = null


func _note_landing(b: Dictionary) -> void:
	if landing_log is Array:
		(landing_log as Array).append({"at": b["perch"]["at"], "area": String(b["perch"].get("area", b["perch"].get("piece", b["mode"]))),
				"mode": String(b["mode"]), "species": String(member.get("id", sp.id))})


## The actor layer it draws in: its perch's band, or among the oak's leaves (`layer`, behind the crowns).
func _layer_of(b: Dictionary) -> String:
	var perch: Dictionary = b["perch"]
	if String(b["mode"]) in DOWN and perch.has("band"):
		return String(perch.get("layer", perch["band"])) if String(b["mode"]) == "perched" else String(perch["band"])
	return _band_of(b)


## The depth band it is in (for its size), whatever layer it draws in.
func _band_of(b: Dictionary) -> String:
	var perch: Dictionary = b["perch"]
	if String(b["mode"]) in DOWN and perch.has("band"):
		return String(perch["band"])
	var z := (b["p"] as Vector3).z
	if z >= float(cfg["far_z"]):
		return "far"
	if z >= float(cfg["near_z"]):
		return "mid"
	return "near"


func _relayer(b: Dictionary) -> void:
	var layer := _layer_of(b)
	if layer == String(b["layer"]):
		return
	b["layer"] = layer
	var node: Node = b["look"]
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	beh.scene.actor_layer(layer).add_child(node)


func _draw_bird(b: Dictionary, dt: float, tint: Color) -> void:
	var look: SceneCreatureLook = b["look"]
	var p: Vector3 = b["p"]
	var s := beh.ppm_at_depth(p.z)
	var at := screen_of(p) + Vector2(0, float(b.get("dip", 0.0)) * s if String(b["mode"]) == "boid" else 0.0)
	var perch: Dictionary = b["perch"]
	if String(b["mode"]) == "perched" and perch.has("piece"):
		at = (perch["at"] as Vector2) + beh.scene.perch_offset(String(perch["piece"]), perch["at"])
		s = _ppm(perch)
	elif String(b["mode"]) in ["ground", "cling"]:
		at = perch["at"]
		s = _ppm(perch)
	if b.has("glean") and String(b["mode"]) == "perched":
		# A glean: leaning forward and down to a leaf and back, a whole art px or two.
		var g := float(b["glean"]) + dt
		var dur := float(cfg.get("glean_sec", 0.45))
		b["glean"] = g
		if g >= dur:
			b.erase("glean")
		else:
			var reach := sin(PI * g / dur) * float(cfg.get("glean_pt", 1.5))
			at += Vector2(float(b["facing"]) * reach, reach * 0.6)
	elif String(b["mode"]) == "hover":
		# Held in the air on a blur of wings: a small bob, never quite still.
		at = (perch["at"] as Vector2) + Vector2(0.0, sin(t * 7.0 + float(b["bound"]) * 9.0) * 0.6)
		s = _ppm(perch)
	var v: Vector3 = b["v"]
	if String(b["mode"]) in ["boid", "to_perch"] and absf(v.x) > 0.3:
		b["facing"] = signf(v.x)
	if String(b["mode"]) == "boid":
		_relayer(b)
	look.position = at
	s *= sp.show_scale(_band_of(b), s * beh.scene.density)
	look.scale = Vector2(s * float(b["facing"]), s)
	look.px = 1.0 / maxf(s, 0.01)
	# Seen flying at us or away from us when the flight is mostly in depth.
	look.view_hint = "side"
	if String(b["mode"]) in ["boid", "to_perch"] and absf(v.z) > absf(v.x) * 1.2:
		look.view_hint = "toward" if v.z < 0.0 else "away"
	look.advance(dt, v.length() * dt)
	# Far birds fade a little into the haze rather than shrinking to a hard dot.
	var haze := clampf((p.z - 60.0) / 80.0, 0.0, 0.6) if String(b["mode"]) == "boid" else 0.0
	if b.has("alpha") and state != "leaving":
		# Out of the trees: it comes clear as it leaves them.
		b["alpha"] = minf(1.0, float(b["alpha"]) + dt / float(cfg.get("trees_fade_sec", 1.5)))
	look.modulate = Color(tint.r, tint.g, tint.b, (1.0 - haze) * float(b.get("alpha", 1.0)))
