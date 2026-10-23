class_name ShelfOutlines
extends RefCounted

## The outline treatments: how a shelf island's silhouette is softened so no edge reads as
## a ruler-straight line. Each is a function over the same ShelfGeometry, picked by name,
## and only ever draws over it: band positions, spots and the front edge stay put.
##
## A · gentle wobble: the rim and corners shift 1–2 px along a seeded curve, small round corners.
## B · grass lip: a straight-ish rim hidden behind grass tufts along the front and the sides.
## C · eroded edge: chips bitten out of the corners and the front lip, crumbs falling below.
## D · soft bevel: larger round corners and a shaded bevel between the top and the front face.

const NAMES := ["A", "B", "C", "D"]
const TITLES := {"A": "gentle wobble", "B": "grass lip", "C": "eroded edge", "D": "soft bevel"}
const FRONT_CORNERS := ["square", "round", "slice"]


## The rim from the bottom of the left wall (the front face's side, or a cut corner's facet), up
## and round the top (left side, any cuts, back edge, right side) and down the right wall: one
## point per art pixel, each {"at", "normal" (outward), "part" ("face" or "top")}, softened by
## `name`. Every corner of the geometry's rim is rounded by the treatment's radius.
##
## `front_corners` [left, right] adds round or slice decoration to an uncut front corner
## (see lip_lift); "square" leaves it to the treatment.
static func rim(geo: ShelfGeometry, name: String, shelf: Dictionary, front_corners: Array = ["square", "square"]) -> Array:
	var cfg: Dictionary = shelf["outline"][name]
	var corners := geo.rim_corners()
	var radius := float(cfg["corner_px"])
	var path: Array = []
	var start: Vector2 = corners[0]["at"]
	var last := corners.size() - 1
	for i in range(1, corners.size()):
		var corner: Vector2 = corners[i]["at"]
		var part := "face" if i == 1 or i == last else "top"
		if i == last:
			_line(path, start, corner, "face")
			break
		var next: Vector2 = corners[i + 1]["at"]
		var style := "square"
		if i == 1 and geo.cuts["fl"] == 0:
			style = String(front_corners[0])
		elif i == last - 1 and geo.cuts["fr"] == 0:
			style = String(front_corners[1])
		var wanted := radius
		if style == "round":
			wanted = float(shelf["front_corner"]["round_px"])
		elif style == "slice":
			wanted = float(shelf["front_corner"]["slice_px"])
		var r := minf(wanted, minf(start.distance_to(corner), corner.distance_to(next)) / 2.0)
		var a := corner + (start - corner).normalized() * r
		var b := corner + (next - corner).normalized() * r
		_line(path, start, a, part)
		if style == "slice":
			_line(path, a, b, "top")
		else:
			_curve(path, a, corner, b, "top")
		start = b
	path.append({"at": corners[-1]["at"], "part": "face"})
	_add_normals(path)
	var n := path.size()
	var s := geo.noise_seed * 31 + name.unicode_at(0)
	for i in n:
		var p: Dictionary = path[i]
		var fade := clampf(minf(i, n - 1 - i) / 4.0, 0.0, 1.0)
		var on_top: bool = p["part"] == "top"
		var amount := float(cfg["wobble_px"]) if on_top else float(shelf["face_wobble_px"])
		var period := float(cfg["wobble_period_px"]) if on_top else float(shelf["face_wobble_period_px"])
		p["at"] = p["at"] + p["normal"] * wobble(i, period, s) * amount * fade
	return path


## A seeded wander in [-1, 1]: smooth noise plus a slow swell, so it never rests on one
## offset for long (a stretch at one offset is what reads as a ruler).
static func wobble(i: float, period: float, s: int) -> float:
	return ShelfRenderer.noise1(i / period, s) * 0.6 + sin(TAU * i / (period * 0.8) + s % 7) * 0.4


## Per image column, how many px the lip rises above the front edge: a round or sliced
## front corner turns the top's corner away, so the front face wraps up into it and the lip
## curves (round) or runs straight (slice) up to the side edge. Square corners stay flat.
static func lip_lift(geo: ShelfGeometry, shelf: Dictionary, front_corners: Array, columns: int) -> PackedInt32Array:
	var lift := PackedInt32Array()
	lift.resize(columns)
	lift.fill(0)
	var cfg: Dictionary = shelf["front_corner"]
	var zone := float(cfg["zone_px"])
	var height := float(cfg["lift_px"])
	var edges := [geo.left_x(), geo.left_x() + geo.width]
	for side in 2:
		var style := String(front_corners[side])
		if style == "square" or geo.cuts["fr" if side == 1 else "fl"] > 0:
			continue
		for x in columns:
			var d: float = absf(x + 0.5 - edges[side])
			if d >= zone:
				continue
			var t := 1.0 - d / zone
			var rise := t if style == "slice" else 1.0 - sqrt(maxf(0.0, 1.0 - t * t))
			lift[x] = maxi(lift[x], roundi(rise * height))
	return lift


## The whole silhouette polygon: the softened rim, then the underside back to the start.
static func silhouette(geo: ShelfGeometry, rim_path: Array) -> PackedVector2Array:
	var polygon := PackedVector2Array()
	for p in rim_path:
		polygon.append(p["at"])
	var under := geo.underside()
	for i in range(1, under.size() - 1):
		polygon.append(under[i])
	return polygon


## Before the island is painted: cuts in the silhouette (C's chipped corners).
static func cut(name: String, r: ShelfRenderer) -> void:
	if name != "C":
		return
	var cfg: Dictionary = r.shelf["outline"]["C"]
	var chip: Array = cfg["chip_px"]
	for corner in _corner_points(r):
		var radius := r.rng.randf_range(float(chip[0]), float(chip[1]))
		r.cut_disc(corner["at"] + corner["normal"] * radius * 0.35, radius)
	var top_points: Array = r.rim_path.filter(func(p: Dictionary) -> bool: return p["part"] == "top")
	for i in maxi(0, int(cfg["chips"]) / 2 - 2):
		var p: Dictionary = top_points[r.rng.randi_range(0, top_points.size() - 1)]
		var radius := r.rng.randf_range(float(chip[0]), float(chip[1])) * 0.7
		r.cut_disc(p["at"] + p["normal"] * radius * 0.5, radius)


## After the island is painted: B's overhanging tufts, C's chipped lip and crumbs.
static func decorate(name: String, r: ShelfRenderer) -> void:
	match name:
		"B":
			_rim_tufts(r)
		"C":
			_lip_chips(r)
			_crumbs(r)


## How long the grass blades hanging over the front lip are, as a multiple.
static func lip_blade_factor(name: String) -> float:
	return 1.6 if name == "B" else 1.0


static func bevel_rows(name: String, shelf: Dictionary) -> int:
	return int(shelf["outline"]["D"]["bevel_px"]) if name == "D" else 0


static func _rim_tufts(r: ShelfRenderer) -> void:
	var cfg: Dictionary = r.shelf["outline"]["B"]
	var every: Array = cfg["tuft_every_px"]
	var reach: Array = cfg["tuft_reach_px"]
	var i := r.rng.randi_range(0, int(every[1]))
	while i < r.rim_path.size():
		var p: Dictionary = r.rim_path[i]
		if p["part"] == "top":
			var normal: Vector2 = p["normal"]
			var along := Vector2(-normal.y, normal.x)
			for blade in [-1, 0, 1]:
				var length := r.rng.randi_range(int(reach[0]), int(reach[1]))
				var at: Vector2 = p["at"] - normal + along * blade
				for k in length + 1:
					var c := ShelfRenderer.GRASS_LIGHT if k == length else ShelfRenderer.GRASS
					r.paint(at + (normal + along * blade * 0.4) * k, c, ShelfRenderer.TOP)
		i += r.rng.randi_range(int(every[0]), int(every[1]))


static func _lip_chips(r: ShelfRenderer) -> void:
	var cfg: Dictionary = r.shelf["outline"]["C"]
	var chip: Array = cfg["chip_px"]
	var face := r.geo.front_face()
	var front := floori(r.geo.front_y())
	for i in maxi(1, int(cfg["chips"]) - int(cfg["chips"]) / 2):
		var cx := r.rng.randf_range(face.position.x + 6, face.end.x - 6)
		var radius := r.rng.randf_range(float(chip[0]), float(chip[1]))
		for y in range(front - ceili(radius), front + 2):
			for x in range(floori(cx - radius), ceili(cx + radius) + 1):
				var dx := (x + 0.5 - cx) / radius
				var dy := (y + 0.5 - front) / radius
				if dx * dx + dy * dy > 1.0 or r.kind_at(x, y) == ShelfRenderer.WATER:
					continue
				if y < front and r.kind_at(x, y) == ShelfRenderer.TOP:
					r.paint(Vector2(x, y), ShelfRenderer.SOIL_EXPOSED)
				elif y >= front and r.kind_at(x, y) == ShelfRenderer.FACE:
					r.paint(Vector2(x, y), ShelfRenderer.SOIL_SHADOW)


static func _crumbs(r: ShelfRenderer) -> void:
	var face := r.geo.front_face()
	for i in int(r.shelf["outline"]["C"]["crumbs"]):
		var x := r.rng.randi_range(int(face.position.x) + 4, int(face.end.x) - 4)
		var bottom := r.column_bottom(x)
		if bottom < 0:
			continue
		var y := bottom + r.rng.randi_range(2, 9)
		var c := ShelfRenderer.SOIL_1 if r.rng.randf() < 0.5 else ShelfRenderer.SOIL_2
		r.paint(Vector2(x, y), c)
		if r.rng.randf() < 0.4:
			r.paint(Vector2(x + 1, y), c)


static func _corner_points(r: ShelfRenderer) -> Array:
	# The rim's real corners (where it turns by more than 25°), as their nearest rim points.
	var corners := r.geo.rim_corners()
	var targets: Array = []
	for i in range(1, corners.size() - 1):
		var a: Vector2 = corners[i]["at"] - corners[i - 1]["at"]
		var b: Vector2 = corners[i + 1]["at"] - corners[i]["at"]
		if absf(a.angle_to(b)) > deg_to_rad(25.0):
			targets.append(corners[i]["at"])
	var out: Array = []
	for target in targets:
		var best: Dictionary = r.rim_path[0]
		for p in r.rim_path:
			if (p["at"] as Vector2).distance_to(target) < (best["at"] as Vector2).distance_to(target):
				best = p
		out.append(best)
	return out


static func _line(path: Array, a: Vector2, b: Vector2, part: String) -> void:
	var steps := maxi(1, ceili(a.distance_to(b)))
	for i in steps:
		path.append({"at": a.lerp(b, float(i) / steps), "part": part})


static func _curve(path: Array, a: Vector2, control: Vector2, b: Vector2, part: String) -> void:
	var steps := maxi(1, ceili(a.distance_to(control) + control.distance_to(b)))
	for i in steps:
		var t := float(i) / steps
		path.append({"at": a.lerp(control, t).lerp(control.lerp(b, t), t), "part": part})


static func _add_normals(path: Array) -> void:
	for i in path.size():
		var before: Vector2 = path[maxi(0, i - 2)]["at"]
		var after: Vector2 = path[mini(path.size() - 1, i + 2)]["at"]
		var d := (after - before).normalized()
		# The rim runs clockwise on screen, so outward is the direction turned left.
		path[i]["normal"] = Vector2(d.y, -d.x)
