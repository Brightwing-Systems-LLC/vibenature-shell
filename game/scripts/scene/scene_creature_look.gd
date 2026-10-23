class_name SceneCreatureLook
extends Node2D

## How a creature looks while it does one of the §7 actions. Until the bench's cast lands
## (Skypatch issue 100) this draws a placeholder for each
## body plan (quadruped, songbird, heron, turtle, fish, snake) in metres, so motion and pacing can be
## judged now: legs move with the gait and the ground covered, heads go down to graze and come up to
## scan, a heron's neck folds and stabs, wings beat. The pose eases toward each action rather than
## jumping, as a body does.
##
## When the scene package's `creatures/<species>/meta.json` is delivered, the sheet plays instead (the
## action's frames, its view, scaled from the master's 140 px/m to the creature's place), with no
## change to the behaviour that drives it.
##
## Units: the node's scale is points per metre (negative x to face left), so everything below is in
## metres, +x forward, feet at the origin, up is -y.

const MASTER_PX_PER_M := 140.0

var body := "quadruped"
## Length and height (shoulder, or standing) in metres.
var dims := Vector2(1.0, 1.0)
var shape: Dictionary = {}
var colors: Dictionary = {}
var spots := false
## One point in metres: the thinnest a line may be drawn.
var px := 0.05
var action := "idle"
var action_t := 0.0
## The gait's phase (radians), advanced by the ground covered.
var gait := 0.0
var gait_kind := "walk"
var moving := 0.0
## Eased pose values, 0..1 unless noted.
var head_down := 0.0
var alert := 0.0
var flag := 0.0
var sit := 0.0
var lie := 0.0
var groom := 0.0
var neck := 0.0
var air := 0.0
var under := 0.0
var ear := 0.0
var tail_flick := 0.0
## Wing phase (radians) and how open the wings are (0 folded).
var flap := 0.0
var wings := 0.0
## Metres of leg under water (a wading heron).
var wade := 0.0
## On the surface seen from above the cut (not in the cut-away): a swimmer shows only its top.
var at_surface := false
## A waterline in this node's own units (down positive), INF none: set by the creature for a leap
## out on the pond (issue 340).
var waterline_local := INF
## How much of a part under the surface still shows through (balance `behaviour.below_surface_alpha`).
var below_alpha := 0.0
var _targets := {}
## The bench's drawing of this animal, when delivered (`SceneSheet`); the placeholder otherwise.
var sheet: SceneSheet
## Art px per point (the kit's density), to size the sheet in art px.
var density := 2.0
## Which way it is seen: side, toward or away (birds flying at or from the viewer).
var view_hint := "side"
var _dur := -1.0
var _from := 0
var _backwards := false
var _rng := RandomNumberGenerator.new()


## `sheet_id` names the bench's creature (the scene package's `creatures/<id>/`); `tweaks` are the
## species' {swap: {action: action}, scale: {action: factor}, tint: {action: value}} for that sheet.
func setup(sp: SceneSpecies, palette: Dictionary, size_mult: float, seed: int, sheet_id: String = "", tweaks: Dictionary = {}) -> void:
	body = sp.body
	dims = sp.size() * size_mult
	shape = sp.data.get("shape", {})
	_rng.seed = seed
	for key in palette:
		if String(key) != "name":
			colors[key] = Color(String(palette[key]))
	spots = palette.has("spots")
	sheet = SceneSheet.load_for(sheet_id)
	if sheet != null:
		sheet.swap = tweaks.get("swap", {})
		sheet.action_scale = tweaks.get("scale", {})
		sheet.action_tint = tweaks.get("tint", {})
		sheet.hold = tweaks.get("hold", {})
		sheet.hold_rows = tweaks.get("hold_rows", {})
		sheet.max_reduced_scale = float(tweaks.get("max_reduced_scale", 3.0))
		add_child(sheet)


func has_sheet() -> bool:
	return sheet != null


## Starts `a`; the pose eases toward it. A drawn one-shot may start on frame `from` or play backwards.
func play(a: String, seconds: float = -1.0, from: int = 0, backwards: bool = false) -> void:
	if a != action:
		action = a
		action_t = 0.0
	_dur = seconds
	_from = from
	_backwards = backwards


## Advances `dt` seconds having moved `moved_m` metres along the ground (or through the air).
func advance(dt: float, moved_m: float) -> void:
	action_t += dt
	var stride := _stride()
	if stride > 0.0:
		gait += moved_m / stride * TAU * 0.5
	moving = lerpf(moving, 1.0 if moved_m > 0.0005 else 0.0, clampf(dt * 8.0, 0.0, 1.0))
	var t := _pose_targets()
	var fast := action in ["startle", "strike", "run"]
	var rate := 9.0 if fast else 3.2
	head_down = move_toward(head_down, float(t.get("head_down", 0.0)), dt * rate * 0.6)
	alert = move_toward(alert, float(t.get("alert", 0.0)), dt * rate)
	flag = move_toward(flag, float(t.get("flag", 0.0)), dt * 6.0)
	sit = move_toward(sit, float(t.get("sit", 0.0)), dt * 1.6)
	lie = move_toward(lie, float(t.get("lie", 0.0)), dt * 0.9)
	groom = move_toward(groom, float(t.get("groom", 0.0)), dt * 2.5)
	under = move_toward(under, float(t.get("under", 0.0)), dt * 1.5)
	wings = move_toward(wings, float(t.get("wings", 0.0)), dt * 5.0)
	var neck_target := float(t.get("neck", 0.0))
	neck = move_toward(neck, neck_target, dt * (14.0 if neck_target > 1.5 else 2.2))
	ear = sin(action_t * 30.0) * 0.6 if action == "ear_flick" and action_t < 0.45 else ear * maxf(0.0, 1.0 - dt * 10.0)
	tail_flick = absf(sin(action_t * 14.0)) if action == "tail_flick" and action_t < 0.9 else tail_flick * maxf(0.0, 1.0 - dt * 8.0)
	if action == "strike" and body == "quadruped":
		# A fox's pounce: up and over, nose first, in about 0.7 s.
		air = sin(PI * clampf(action_t / 0.7, 0.0, 1.0)) * dims.y * 1.6
	elif action == "hop":
		air = absf(sin(action_t * 9.0)) * dims.y * 0.9
	else:
		air = move_toward(air, 0.0, dt * 3.0)
	var beat := float(t.get("beat", 0.0))
	if beat > 0.0:
		flap += dt * TAU * beat
	if sheet != null:
		sheet.set_action(action, _dur, _from, _backwards)
		var sunk := under * dims.y * 0.55 if at_surface and body in ["turtle", "snake", "fish"] and action in ["swim", "surface", "dive"] else 0.0
		sheet.wade_m = maxf(wade if body == "heron" and action not in ["fly", "glide"] else 0.0, sunk)
		sheet.below_alpha = below_alpha
		sheet.waterline_local = waterline_local
		sheet.update(dt, moved_m, density / maxf(px, 0.0001), view_hint, air)
	else:
		queue_redraw()


func _stride() -> float:
	match body:
		"quadruped":
			return dims.x * (0.55 if gait_kind == "walk" else 0.85 if gait_kind == "trot" else 1.4)
		"heron":
			return 0.35
		"songbird":
			return 0.06
		"turtle":
			return 0.08
	return 0.0


func _pose_targets() -> Dictionary:
	# The heron's drawn hunting and preening actions, for the drawn-in-code placeholder.
	var a := action
	if a.begins_with("preen") or a == "shake":
		a = "groom"
	elif a == "stalk":
		a = "walk"
	elif a == "strike_fast":
		a = "strike"
	elif a == "freeze" or a.begins_with("catch_") or a.begins_with("wiggle_") or a.begins_with("flip_") or a.begins_with("swallow_"):
		a = "look"
	match a:
		"graze", "peck":
			return {"head_down": 1.0}
		"drink":
			return {"head_down": 1.15}
		"look":
			return {"alert": 1.0, "neck": 1.0, "wings": 0.0}
		"startle":
			return {"alert": 1.0, "flag": 1.0, "neck": 0.4}
		"sit":
			return {"sit": 1.0, "alert": 0.3}
		"lie":
			return {"lie": 1.0}
		"groom":
			return {"groom": 1.0}
		"run":
			return {"flag": 1.0 if shape.get("tail_kind", "") == "flag" else 0.0, "alert": 0.3}
		"walk", "trot":
			return {"head_down": 0.15 if body == "quadruped" else 0.0, "neck": 0.6 if body == "heron" else 0.0}
		"strike":
			return {"neck": 2.0} if body == "heron" else {"head_down": 0.8}
		"fly":
			return {"wings": 1.0, "beat": 2.3 if body == "heron" else 13.0}
		"glide":
			return {"wings": 1.0, "beat": 0.0}
		"land", "takeoff":
			return {"wings": 1.0, "beat": 3.0 if body == "heron" else 16.0}
		"swim":
			return {"under": 0.75}
		"dive":
			return {"under": 1.0}
		"surface":
			return {"under": 0.7}
		"bask":
			return {"neck": 1.0, "under": 0.0}
		"climb":
			return {}
		"perch":
			return {"alert": 0.2}
	return {"neck": 0.0}


func _draw() -> void:
	if sheet != null:
		return
	match body:
		"quadruped":
			_quadruped()
		"songbird":
			_songbird()
		"heron":
			_heron()
		"turtle":
			_turtle()
		"snake":
			_snake()


func _c(key: String, fallback: String = "808080") -> Color:
	return colors.get(key, Color(fallback))


func _ellipse(center: Vector2, r: Vector2, angle: float, color: Color, n: int = 18) -> void:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(center + Vector2(cos(a) * r.x, sin(a) * r.y).rotated(angle))
	_fill(pts, color)


## A filled shape, skipped when it has folded flat (a wing edge-on), which cannot be triangulated.
func _fill(pts: PackedVector2Array, color: Color) -> void:
	var area := 0.0
	for i in pts.size():
		area += pts[i].cross(pts[(i + 1) % pts.size()])
	if absf(area) > 1e-7 and (pts.size() == 3 or not Geometry2D.triangulate_polygon(pts).is_empty()):
		draw_colored_polygon(pts, color)


func _line(a: Vector2, b: Vector2, w: float, color: Color) -> void:
	# Not antialiased: the feather is in local units (metres here) and would smear a whole leg.
	draw_line(a, b, color, maxf(w, px * 0.9), false)


func _poly(points: PackedVector2Array, w: float, color: Color) -> void:
	draw_polyline(points, color, maxf(w, px * 0.9), false)


static func _bez(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	return a.lerp(b, t).lerp(b.lerp(c, t), t)


# --- Quadrupeds: deer, fox, raccoon, squirrel, bear ---------------------------------------------

func _quadruped() -> void:
	var L := dims.x
	var H := dims.y
	var leg := H * float(shape.get("leg", 0.55))
	var bt := H - leg
	var bulk := float(shape.get("bulk", 1.0))
	var down := lie * (leg - bt * 0.15)
	var body_y := -(leg + bt * 0.5) + down - air
	var hip := Vector2(-L * 0.33, body_y + bt * 0.05 - float(shape.get("hunch", 0.0)) * H)
	var sho := Vector2(L * 0.3, body_y)
	if sit > 0.0:
		hip = hip.lerp(Vector2(-L * 0.16, -bt * 0.5), sit)
		sho = sho.lerp(Vector2(L * 0.22, body_y - H * 0.18), sit)
	var gk := gait_kind
	var stride := L * (0.2 if gk == "walk" else 0.28 if gk == "trot" else 0.42) * moving
	var lift := H * (0.08 if gk == "walk" else 0.14 if gk == "trot" else 0.2) * moving
	# Phase offsets: walk is a four-beat lateral sequence, trot diagonal pairs, run a bound.
	var offs := {"walk": [0.0, PI, PI * 0.5, PI * 1.5], "trot": [0.0, PI, PI, 0.0], "run": [0.0, 0.35, PI, PI + 0.35]}
	var o: Array = offs.get(gk, offs["walk"])
	var dark := _c("dark")
	var far_tint := _c("back").darkened(0.25)
	var w := L * 0.045 * clampf(bulk, 0.8, 1.6)
	if lie < 0.6:
		# Far legs first (darker), near legs after the body.
		_leg(hip + Vector2(L * 0.02, 0), float(o[1]), stride, lift, leg, w, far_tint, true, false)
		_leg(sho + Vector2(-L * 0.02, 0), float(o[3]), stride, lift, leg, w, far_tint, false, false)
	_tail(hip, L, H, bt)
	var mid := (hip + sho) * 0.5
	var ang := (sho - hip).angle()
	var r := Vector2((sho - hip).length() * 0.5 + bt * 0.42, bt * 0.5 * bulk)
	_ellipse(mid, r, ang, _c("body"))
	_ellipse(mid + Vector2(0, bt * 0.18).rotated(ang), Vector2(r.x * 0.82, r.y * 0.55), ang, _c("belly"))
	_ellipse(mid + Vector2(0, -bt * 0.2).rotated(ang), Vector2(r.x * 0.9, r.y * 0.5), ang, _c("back"))
	if float(shape.get("hump", 0.0)) > 0.0:
		_ellipse(sho + Vector2(-L * 0.05, -bt * 0.35), Vector2(L * 0.16, float(shape["hump"]) * H + bt * 0.2), 0.0, _c("back"))
	if spots:
		var s := _c("spots")
		for i in 7:
			var u := float(i) / 6.0
			_ellipse(mid + Vector2(lerpf(-r.x * 0.7, r.x * 0.6, u), -bt * (0.12 + 0.12 * float(i % 2))).rotated(ang), Vector2(bt * 0.06, bt * 0.045), 0.0, s, 8)
	if lie < 0.6:
		_leg(hip, float(o[0]), stride, lift, leg, w, _c("body"), true, true)
		_leg(sho, float(o[2]), stride, lift, leg, w, _c("body"), false, true)
	else:
		_ellipse(sho + Vector2(L * 0.08, bt * 0.35), Vector2(L * 0.12, bt * 0.15), 0.0, _c("body"))
	_head(sho, L, H, bt, body_y)


func _leg(top: Vector2, phase: float, stride: float, lift: float, leg: float, w: float, color: Color, hind: bool, near: bool) -> void:
	var foot := Vector2(top.x + stride * sin(gait + phase), -lift * maxf(0.0, cos(gait + phase)))
	if hind and sit > 0.0:
		# Haunches: the hind leg folds under the body.
		foot = foot.lerp(top + Vector2(dims.x * 0.18, leg * 0.1), sit)
		foot.y = minf(foot.y, 0.0)
	foot.y -= air * 0.6
	var knee := top.lerp(foot, 0.5) + Vector2(dims.x * (0.06 if hind else -0.025), 0.0)
	var dark := _c("dark")
	_line(top, knee, w * 1.3, color)
	_line(knee, foot, w * 0.75, color)
	if near:
		_line(foot + Vector2(0, -leg * 0.12), foot, w * 0.8, dark)


func _head(sho: Vector2, L: float, H: float, bt: float, body_y: float) -> void:
	var n := float(shape.get("neck", 0.4))
	var hl := H * float(shape.get("head", 0.3))
	var normal := sho + Vector2(L * 0.24, -H * n * 0.85)
	var up := sho + Vector2(L * 0.18, -H * n * 1.3)
	var graze := Vector2(sho.x + L * 0.32, -hl * 0.35)
	var drink := Vector2(sho.x + L * 0.38, -hl * 0.12)
	var preen := Vector2(-L * 0.1, body_y - bt * 0.45)
	var h := normal.lerp(up, alert)
	h = h.lerp(graze, clampf(head_down, 0.0, 1.0))
	if head_down > 1.0:
		h = graze.lerp(drink, (head_down - 1.0) / 0.15)
	h = h.lerp(preen, groom)
	h.y -= sin(gait * 2.0) * H * 0.012 * moving
	# The snout points forward and down, steeper as the head goes down; back when grooming.
	var snout := lerpf(0.55, 1.35, clampf(head_down, 0.0, 1.0)) - alert * 0.35
	snout = lerp_angle(snout, PI - 0.6, groom)
	var neck_base := sho + Vector2(L * 0.04, -bt * 0.3)
	var neck_w := bt * 0.42 * clampf(float(shape.get("bulk", 1.0)), 0.8, 1.5)
	_poly(PackedVector2Array([neck_base, neck_base.lerp(h, 0.5) + Vector2(0, -bt * 0.08), h]), neck_w, _c("body"))
	var dir := Vector2.RIGHT.rotated(snout)
	_ellipse(h + dir * hl * 0.3, Vector2(hl * 0.5, hl * 0.24), snout, _c("body"))
	_ellipse(h + dir * hl * 0.72, Vector2(hl * 0.13, hl * 0.12), snout, _c("dark"), 10)
	if shape.get("tail_kind", "") == "ringed":
		_ellipse(h + dir * hl * 0.32, Vector2(hl * 0.22, hl * 0.12), snout, _c("dark"), 12)
	_ellipse(h + dir * hl * 0.22 + Vector2(0, -hl * 0.06).rotated(snout), Vector2(hl * 0.045, hl * 0.045), 0.0, Color(0.06, 0.05, 0.05), 8)
	var ear_len := H * float(shape.get("ear", 0.12))
	var back := h - dir * hl * 0.05
	for i in 2:
		var a := snout - PI * 0.5 - 0.5 - 0.35 * float(i) + (ear if i == 0 else 0.0) - alert * 0.2
		var base := back + Vector2(0, -hl * 0.1)
		var tip := base + Vector2.RIGHT.rotated(a) * ear_len
		var side := Vector2.RIGHT.rotated(a + PI * 0.5) * ear_len * 0.28
		_fill(PackedVector2Array([base - side, tip, base + side]), _c("back") if i == 1 else _c("body"))


func _tail(hip: Vector2, L: float, H: float, bt: float) -> void:
	var kind := String(shape.get("tail_kind", "flag"))
	var tl := L * float(shape.get("tail", 0.2))
	var root := hip + Vector2(-bt * 0.4, -bt * 0.25)
	match kind:
		"flag":
			# A deer's tail: brown and down at rest, up and white when alarmed.
			var up := clampf(flag + tail_flick * 0.5, 0.0, 1.0)
			var a := lerpf(PI * 0.62, PI * 1.35, up)
			var tip := root + Vector2.RIGHT.rotated(a) * tl * (0.8 + up * 0.2)
			_line(root, tip, tl * (0.35 + up * 0.25), _c("accent") if up > 0.4 else _c("back"))
		"bushy", "ringed":
			var droop := 0.35 - tail_flick * 0.3 - (0.5 if action == "run" else 0.0)
			var p0 := root
			var p1 := root + Vector2(-tl * 0.55, tl * (0.15 + droop * 0.4))
			var p2 := root + Vector2(-tl, tl * droop)
			var pts := PackedVector2Array()
			for i in 7:
				pts.append(_bez(p0, p1, p2, float(i) / 6.0))
			_poly(pts, tl * 0.32, _c("body"))
			if kind == "bushy":
				_ellipse(p2, Vector2(tl * 0.16, tl * 0.14), 0.0, _c("accent"), 10)
			else:
				for i in range(2, 7, 2):
					_ellipse(pts[i], Vector2(tl * 0.07, tl * 0.17), (p2 - p0).angle(), _c("dark"), 10)
		"squirrel":
			# Up over the back in an S, flicking.
			var f := tail_flick * 0.25
			var p0 := root
			var p1 := root + Vector2(-tl * 0.7, -tl * (0.2 + f))
			var p2 := root + Vector2(-tl * 0.1, -tl * (1.1 + f))
			var pts := PackedVector2Array()
			for i in 9:
				pts.append(_bez(p0, p1, p2, float(i) / 8.0))
			_poly(pts, tl * 0.42, _c("back"))
			_poly(pts, tl * 0.22, _c("accent"))
		"stub":
			_ellipse(root, Vector2(tl, tl * 0.8), 0.0, _c("back"), 8)


# --- Songbirds ---------------------------------------------------------------------------------

func _songbird() -> void:
	var b := dims.x
	var flying := wings > 0.3
	var pitch := 0.0
	if not flying:
		pitch = -0.5 + head_down * 0.9 + alert * -0.15
	var c := Vector2(0, -b * 0.28 - air)
	if flying:
		c = Vector2.ZERO
	var dir := Vector2.RIGHT.rotated(pitch)
	if not flying:
		_line(Vector2(-b * 0.03, 0), c + Vector2(-b * 0.03, b * 0.1), px, _c("dark"))
		_line(Vector2(b * 0.04, 0), c + Vector2(b * 0.03, b * 0.1), px, _c("dark"))
	_line(c - dir * b * 0.22, c - dir * b * 0.48 + Vector2(0, b * (0.1 if not flying else 0.0)), b * 0.07, _c("wing"))
	_ellipse(c, Vector2(b * 0.3, b * 0.17), pitch, _c("body"))
	_ellipse(c + Vector2(0, b * 0.07).rotated(pitch), Vector2(b * 0.22, b * 0.09), pitch, _c("belly"))
	var head := c + dir * b * 0.27 + Vector2(0, -b * 0.1).rotated(pitch)
	_ellipse(head, Vector2(b * 0.12, b * 0.11), 0.0, _c("body"), 12)
	_ellipse(head + Vector2(0, -b * 0.04), Vector2(b * 0.1, b * 0.06), 0.0, _c("dark"), 10)
	_fill(PackedVector2Array([head + Vector2(b * 0.08, -b * 0.02), head + Vector2(b * 0.2, b * 0.01), head + Vector2(b * 0.08, b * 0.04)]), _c("dark"))
	if flying:
		var s := sin(flap) * wings
		var root := c + Vector2(b * 0.04, -b * 0.03)
		var tip := c + Vector2(-b * 0.12, -b * 0.75 * s)
		_fill(PackedVector2Array([root + Vector2(b * 0.1, 0), tip, root + Vector2(-b * 0.15, 0)]), _c("wing"))
	else:
		_ellipse(c + Vector2(-b * 0.04, -b * 0.03).rotated(pitch), Vector2(b * 0.2, b * 0.09), pitch, _c("wing"))


# --- Great blue heron --------------------------------------------------------------------------

func _heron() -> void:
	var legs := _c("legs")
	if wings > 0.3 and action in ["fly", "glide", "land", "takeoff"]:
		_heron_flying()
		return
	var leg_top := Vector2(-0.02, -0.56)
	var step := sin(gait) * 0.08 * moving
	for i in 2:
		var foot := Vector2(step * (1.0 if i == 0 else -1.0), 0.0)
		var knee := leg_top.lerp(foot, 0.5) + Vector2(-0.03, 0)
		var from_y := -wade
		var col := legs.darkened(0.2) if i == 1 else legs
		_line(leg_top, knee, 0.022, col)
		if knee.y < from_y:
			var end := knee.lerp(foot, clampf((from_y - knee.y) / maxf(0.001, foot.y - knee.y), 0.0, 1.0))
			_line(knee, end, 0.018, col)
	var lean := 0.25 + neck * 0.15 - alert * 0.1
	var bc := Vector2(-0.06, -0.72)
	_ellipse(bc + Vector2(-0.18, 0.05), Vector2(0.14, 0.05), lean + 0.3, _c("back"))
	_ellipse(bc, Vector2(0.25, 0.11), -lean * 0.4, _c("body"))
	_ellipse(bc + Vector2(-0.04, -0.03), Vector2(0.2, 0.07), -lean * 0.4, _c("back"))
	var base := Vector2(0.13, -0.8)
	var head: Vector2
	var mid: Vector2
	var bill_angle := 0.15
	var n := neck
	if n > 1.2:
		var u := clampf(n - 1.0, 0.0, 1.0)
		head = Vector2(0.42, -1.0).lerp(Vector2(0.62, -0.12 - wade * 0.3), u)
		mid = Vector2(0.28, -0.95).lerp(Vector2(0.45, -0.55), u)
		bill_angle = lerpf(0.2, 1.1, u)
	else:
		head = Vector2(0.12, -1.02).lerp(Vector2(0.42, -1.0), clampf(n, 0.0, 1.0))
		mid = Vector2(0.0, -0.93).lerp(Vector2(0.26, -0.98), clampf(n, 0.0, 1.0))
		head = head.lerp(Vector2(0.18, -1.3), alert * (1.0 - clampf(n, 0.0, 1.0)))
		mid = mid.lerp(Vector2(0.1, -1.12), alert * (1.0 - clampf(n, 0.0, 1.0)))
		bill_angle = lerpf(0.15, 0.35, clampf(n, 0.0, 1.0)) - alert * 0.25
	if groom > 0.0:
		head = head.lerp(Vector2(0.05, -0.74), groom)
		mid = mid.lerp(Vector2(0.12, -0.95), groom)
		bill_angle = lerpf(bill_angle, 2.2, groom)
	if action == "look" and action_t > 0.6 and _swallowing:
		bill_angle = -1.1
	var pts := PackedVector2Array()
	for i in 9:
		pts.append(_bez(base, mid, head, float(i) / 8.0))
	_poly(pts, 0.05, _c("belly"))
	_ellipse(head, Vector2(0.06, 0.035), bill_angle, _c("accent"), 12)
	_line(head + Vector2(-0.02, -0.025), head + Vector2(-0.14, -0.01), 0.012, _c("dark"))
	var dir := Vector2.RIGHT.rotated(bill_angle)
	_fill(PackedVector2Array([head + dir * 0.03 + dir.orthogonal() * 0.014, head + dir * 0.19, head + dir * 0.03 - dir.orthogonal() * 0.014]), _c("bill"))
	_ellipse(head + dir * 0.015 + Vector2(0, -0.01), Vector2(0.008, 0.008), 0.0, Color(0.1, 0.08, 0.05), 6)


## Set by the creature after a catch: the head tips back to swallow.
var _swallowing := false


func set_swallowing(on: bool) -> void:
	_swallowing = on


func _heron_flying() -> void:
	var s := sin(flap)
	var landing := action == "land"
	var legs := _c("legs")
	var trail := Vector2(-0.62, 0.04) if not landing else Vector2(0.15, 0.45)
	_line(Vector2(-0.18, 0.02), trail, 0.02, legs)
	_ellipse(Vector2(-0.02, 0), Vector2(0.34, 0.1), 0.0, _c("body"))
	_ellipse(Vector2(0.24, -0.05), Vector2(0.09, 0.06), 0.0, _c("belly"))
	var head := Vector2(0.33, -0.07)
	_ellipse(head, Vector2(0.055, 0.035), 0.1, _c("accent"), 10)
	_fill(PackedVector2Array([head + Vector2(0.03, -0.012), head + Vector2(0.2, 0.01), head + Vector2(0.03, 0.014)]), _c("bill"))
	# Seen side-on, the far wing shows above the body on the upstroke and below on the down:
	# broad (a heron's wings are wide and bowed), the hand swept back, dark primaries.
	var wing := s * wings
	if landing:
		wing = 0.85 + 0.15 * s
	var root_f := Vector2(0.16, -0.03)
	var root_b := Vector2(-0.2, -0.03)
	var elbow := Vector2(0.0, -0.42 * wing)
	var tip := Vector2(-0.32, -0.88 * wing)
	_fill(PackedVector2Array([root_f, elbow + Vector2(0.14, 0), tip + Vector2(0.06, 0), tip, elbow + Vector2(-0.22, 0), root_b]), _c("back"))
	_fill(PackedVector2Array([elbow.lerp(tip, 0.45) + Vector2(0.1, 0), tip + Vector2(0.06, 0), tip, elbow.lerp(tip, 0.45) + Vector2(-0.18, 0)]), _c("dark"))


# --- Turtles -----------------------------------------------------------------------------------

func _turtle() -> void:
	var L := dims.x
	var h := dims.y
	var sink := under * h * 0.95
	if under < 0.6:
		var y := sink
		for i in 4:
			var lx := L * (0.3 if i < 2 else -0.28) + sin(gait + float(i) * PI) * L * 0.05 * moving
			_ellipse(Vector2(lx, -h * 0.1 + y), Vector2(L * 0.08, h * 0.12), 0.3, _c("dark"), 8)
		var dome := PackedVector2Array()
		for i in 13:
			var a := PI + PI * float(i) / 12.0
			dome.append(Vector2(cos(a) * L * 0.5, -h * 0.15 + sin(a) * h + y))
		draw_colored_polygon(dome, _c("body"))
		_line(Vector2(-L * 0.48, -h * 0.13 + y), Vector2(L * 0.48, -h * 0.13 + y), h * 0.16, _c("belly"))
		for i in 3:
			_line(Vector2(-L * 0.3 + L * 0.3 * float(i), -h * 0.9 + y), Vector2(-L * 0.36 + L * 0.3 * float(i), -h * 0.3 + y), px * 0.6, _c("back"))
		var out := 0.12 + neck * 0.1
		var head := Vector2(L * (0.48 + out), -h * (0.35 + neck * 0.4) + y)
		_line(Vector2(L * 0.42, -h * 0.25 + y), head, h * 0.32, _c("dark"))
		_ellipse(head, Vector2(L * 0.08, h * 0.2), -0.2 - neck * 0.3, _c("dark"), 10)
		_line(head + Vector2(-L * 0.06, h * 0.02), head + Vector2(-L * 0.12, h * 0.1), px * 0.6, _c("accent"))
	else:
		# Swimming: the head and a sliver of shell at the surface.
		var vis := clampf((1.0 - under) / 0.4, 0.0, 1.0)
		if vis <= 0.02:
			return
		var a := Color(_c("dark"), vis)
		_ellipse(Vector2(0, -h * 0.05), Vector2(L * 0.38, h * 0.1), 0.0, Color(_c("back"), vis * 0.7))
		_ellipse(Vector2(L * 0.55, -h * 0.25), Vector2(L * 0.08, h * 0.2), -0.15, a, 10)


# --- Water snake -------------------------------------------------------------------------------

func _snake() -> void:
	var L := dims.x
	var pts := PackedVector2Array()
	var n := 16
	for i in n:
		var s := float(i) / float(n - 1) * L
		var wave := sin(s * 7.0 - action_t * 4.2) * 0.07 * (s / L + 0.2)
		pts.append(Vector2(-s * 0.92, wave * 0.3 - 0.004))
	var head := Vector2(0.04, -0.035 - alert * 0.04)
	pts.insert(0, head)
	_poly(pts, 0.034, _c("body"))
	for i in range(2, n, 3):
		_line(pts[i], pts[mini(i + 1, n)], 0.036, _c("back"))
	_ellipse(head + Vector2(0.02, 0), Vector2(0.03, 0.017), 0.05, _c("back"), 10)
