class_name SceneSway
extends RefCounted

## How every piece of the kit answers the wind: each piece is a row of damped springs, one per
## few columns, each pushed by the wind where it stands. Stiff short things (grass, reeds) answer
## the leading edge of a gust at once and quiver; heavy crowns lean late, slowly, and rock back
## after it passes. A landing or a brush adds an impulse at a point that spreads to its neighbours
## and settles. The shader bends the piece by these values (more toward its top).
##
## Hook for the behaviour engine: `impulse(piece_id, at, push)` (a bird lands: push down; a deer
## brushes past: push sideways). Pure; `textures()` hands the renderer one row per piece.

var tuning: Dictionary = {}
## piece id -> {x0, width, cols, col_px, dx, vx, dy, vy, weight, omega, zeta, phase, gain, kind}
var entries: Dictionary = {}


func _init(sway_tuning: Dictionary) -> void:
	tuning = sway_tuning


func add(spec: Dictionary) -> void:
	if not SceneKit.bends(spec):
		return
	var size: Vector2 = spec["size"]
	var col_px := float(tuning["column_px"])
	var cols := maxi(2, ceili(size.x / col_px) + 1)
	var sway: Dictionary = spec.get("sway", {})
	# The kit's stiffness: how fast a piece returns (1 rigid). It raises the natural frequency a
	# little; the kind and the size set it (a tall heavy crown is slow, grass quick).
	var stiffness := clampf(float(sway.get("stiffness", 0.5)), 0.0, 1.0)
	var kind := String(spec.get("kind", ""))
	var pivot_y := float(spec.get("pivot", [0, size.y])[1])
	var height := maxf(pivot_y, size.y - pivot_y)
	var hz := float(tuning["hz"].get(kind, tuning["hz"]["default"])) * lerpf(0.8, 1.3, stiffness) \
			* pow(float(tuning["reference_height_px"]) / maxf(height, 8.0), 0.25)
	var e := {
		"x0": float(spec["at"][0]), "width": size.x, "cols": cols, "col_px": size.x / float(cols - 1),
		"dx": PackedFloat32Array(), "vx": PackedFloat32Array(), "dy": PackedFloat32Array(), "vy": PackedFloat32Array(),
		"weight": float(sway.get("weight", 0.0)),
		"omega": TAU * hz,
		"zeta": float(tuning["damping"].get(kind, tuning["damping"]["default"])),
		"phase": float(sway.get("phase", 0.0)),
		"gain": float(tuning["px_per_wind"]) * float(tuning["kind_gain"].get(kind, 1.0))
				* sqrt(maxf(height, 8.0) / float(tuning["reference_height_px"])),
		"kind": kind,
		# How much each column listens to its own patch of wind: grass and reeds are many stalks,
		# a fern or a flower head is one body and must not shear like a rubber sheet.
		"variation": float(tuning["variation"].get(kind, tuning["variation"]["default"])),
	}
	if kind == "far_tree":
		_far_tree(e, spec)
	# Packed arrays are values: size each one, then store it.
	for k in ["dx", "vx", "dy", "vy"]:
		var values := PackedFloat32Array()
		values.resize(cols)
		e[k] = values
	entries[String(spec["id"])] = e


## A far-band tree (Skypatch issue 165) takes its spring from
## its type (`far_tree.<tree>`: a conifer stiff and slow from the tip, a broadleaf looser and quicker),
## its reach in points rather than from its height (the far band is small, the movement must still
## read), a dead band so calm air moves nothing, and its own response (a hashed spread of frequency
## and damping) so a gust rolls across the treeline tree by tree instead of in step.
func _far_tree(e: Dictionary, spec: Dictionary) -> void:
	var types: Dictionary = tuning["far_tree"]
	var tree := String(spec.get("tree", "broadleaf"))
	var t: Dictionary = types.get(tree, types["broadleaf"])
	var h := hash(String(spec["id"]))
	var u := float(h % 1000) / 999.0
	var v := float((h / 1000) % 1000) / 999.0
	var spread := float(types["response_spread"])
	e["omega"] = TAU * float(t["hz"]) * (1.0 + spread * (u * 2.0 - 1.0))
	e["zeta"] = float(t["damping"]) * (1.0 + spread * (v * 2.0 - 1.0))
	e["gain"] = float(t["reach_pt"])
	e["variation"] = float(t["variation"])
	e["far"] = {"calm": float(types["calm_wind"]), "curve": float(types["curve"]), "limit": float(t["max_pt"])}
	e["tree"] = tree


## How hard the wind `w` pushes a far tree: nothing below the calm band, then rising less than in
## proportion (a breeze shows, a gale does not throw the treeline about).
static func far_push(w: float, far: Dictionary) -> float:
	var over := absf(w) - float(far["calm"])
	if over <= 0.0:
		return 0.0
	return signf(w) * pow(over, float(far["curve"]))


## Advances every spring `dt` seconds under `env`'s wind.
func step(dt: float, env: SceneEnvironment) -> void:
	var sub := maxi(1, ceili(dt / float(tuning["max_substep_sec"])))
	var h := dt / float(sub)
	var spread := float(tuning["neighbour_coupling"])
	for id in entries:
		var e: Dictionary = entries[id]
		var cols := int(e["cols"])
		var dx: PackedFloat32Array = e["dx"]
		var vx: PackedFloat32Array = e["vx"]
		var dy: PackedFloat32Array = e["dy"]
		var vy: PackedFloat32Array = e["vy"]
		var w := float(e["omega"])
		var z := float(e["zeta"])
		var far: Dictionary = e.get("far", {})
		# A far tree's reach is its type's (the kit's weight only says that it moves).
		var gain := float(e["gain"]) * (1.0 if not far.is_empty() else float(e["weight"]))
		var targets := PackedFloat32Array()
		targets.resize(cols)
		for i in cols:
			var x := float(e["x0"]) + float(i) * float(e["col_px"])
			if not far.is_empty():
				# A far tree listens where it stands, so a gust reaches the trees in its path in turn.
				targets[i] = gain * far_push(env.wind_at(x), far)
				continue
			# The phase shifts where along the field this piece listens, so neighbours differ.
			targets[i] = gain * env.wind_at(x + float(e["phase"]) * 40.0)
		var mean := 0.0
		for i in cols:
			mean += targets[i]
		mean /= float(cols)
		var variation := float(e["variation"])
		for i in cols:
			targets[i] = lerpf(mean, targets[i], variation)
		var held := _held(e)
		for i in cols:
			targets[i] += held[i].x
		for s in sub:
			for i in cols:
				# Columns pull gently on their neighbours, so a piece bends as one body.
				var left := dx[maxi(0, i - 1)]
				var right := dx[mini(cols - 1, i + 1)]
				var couple := spread * (left + right - 2.0 * dx[i])
				var ax := w * w * (targets[i] - dx[i]) - 2.0 * z * w * vx[i] + w * w * couple
				vx[i] += ax * h
				dx[i] += vx[i] * h
				var ly := dy[maxi(0, i - 1)]
				var ry := dy[mini(cols - 1, i + 1)]
				var ay := w * w * (held[i].y - dy[i]) - 2.0 * z * w * vy[i] + w * w * spread * (ly + ry - 2.0 * dy[i])
				vy[i] += ay * h
				dy[i] += vy[i] * h
			# Never further than a believable bend.
			var limit := float(far.get("limit", tuning["max_px"]))
			for i in cols:
				dx[i] = clampf(dx[i], -limit, limit)
				dy[i] = clampf(dy[i], -limit, limit)
		e["dx"] = dx
		e["vx"] = vx
		e["dy"] = dy
		e["vy"] = vy


## A push on `piece_id` at scene point `at`: `push.y` > 0 presses down (a bird landing), `push.x`
## sideways (a brush), in px/s of velocity at that point, spread over `radius` px.
func impulse(piece_id: String, at: Vector2, push: Vector2, radius: float = -1.0) -> bool:
	if not entries.has(piece_id):
		return false
	var e: Dictionary = entries[piece_id]
	var r := radius if radius > 0.0 else float(tuning["impulse_radius_px"])
	var vx: PackedFloat32Array = e["vx"]
	var vy: PackedFloat32Array = e["vy"]
	for i in int(e["cols"]):
		var x := float(e["x0"]) + float(i) * float(e["col_px"])
		var k := exp(-pow((x - at.x) / r, 2.0))
		vx[i] += push.x * k
		vy[i] += push.y * k
	e["vx"] = vx
	e["vy"] = vy
	return true


## A weight resting on `piece_id` at `at` (a bird sitting on a cattail): the piece leans by
## `push` (px: sideways, down) there for as long as it is held, and springs back when `key` lets go.
func hold(piece_id: String, key: String, at: Vector2, push: Vector2, radius: float = -1.0) -> bool:
	if not entries.has(piece_id):
		return false
	var e: Dictionary = entries[piece_id]
	var loads: Dictionary = e.get("loads", {})
	loads[key] = {"x": at.x, "push": push, "r": radius if radius > 0.0 else float(tuning["impulse_radius_px"])}
	e["loads"] = loads
	return true


func release(piece_id: String, key: String) -> void:
	if entries.has(piece_id):
		(entries[piece_id].get("loads", {}) as Dictionary).erase(key)


## What the held weights on a piece push each column to (px: sideways, down).
func _held(e: Dictionary) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(int(e["cols"]))
	var loads: Dictionary = e.get("loads", {})
	if loads.is_empty():
		return out
	for i in int(e["cols"]):
		var x := float(e["x0"]) + float(i) * float(e["col_px"])
		for key in loads:
			var l: Dictionary = loads[key]
			out[i] += (l["push"] as Vector2) * exp(-pow((x - float(l["x"])) / float(l["r"]), 2.0))
	return out


## Rain beating on the leaves: `count` small downward taps at random places on random pieces
## (wider pieces catch more), each settling on its own.
func patter(count: int, push: float, rng: RandomNumberGenerator) -> void:
	if entries.is_empty() or count <= 0:
		return
	var ids := entries.keys()
	var total := 0.0
	for id in ids:
		total += float(entries[id]["width"])
	for n in count:
		var roll := rng.randf() * total
		for id in ids:
			roll -= float(entries[id]["width"])
			if roll <= 0.0:
				var e: Dictionary = entries[id]
				var x := float(e["x0"]) + rng.randf() * float(e["width"])
				impulse(String(id), Vector2(x, 0), Vector2(0, push * rng.randf_range(0.5, 1.0)), float(tuning["patter_radius_px"]))
				break


## The current bend of `piece_id` at scene column `x`: Vector2(sideways, down) at the top.
func bend_at(piece_id: String, x: float) -> Vector2:
	if not entries.has(piece_id):
		return Vector2.ZERO
	var e: Dictionary = entries[piece_id]
	var u := clampf((x - float(e["x0"])) / float(e["col_px"]), 0.0, float(int(e["cols"]) - 1))
	var i := int(floor(u))
	var j := mini(i + 1, int(e["cols"]) - 1)
	var f := u - float(i)
	var dx: PackedFloat32Array = e["dx"]
	var dy: PackedFloat32Array = e["dy"]
	return Vector2(lerpf(dx[i], dx[j], f), lerpf(dy[i], dy[j], f))


## One row image per piece (RG float: sideways, down), for the shader.
func image_for(piece_id: String) -> Image:
	var e: Dictionary = entries[piece_id]
	var cols := int(e["cols"])
	var data := PackedFloat32Array()
	data.resize(cols * 2)
	var dx: PackedFloat32Array = e["dx"]
	var dy: PackedFloat32Array = e["dy"]
	for i in cols:
		data[i * 2] = dx[i]
		data[i * 2 + 1] = dy[i]
	return Image.create_from_data(cols, 1, false, Image.FORMAT_RGF, data.to_byte_array())
