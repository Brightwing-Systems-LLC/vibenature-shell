class_name ShelfGeometry
extends RefCounted

## A shelf island on a cube grid (Skypatch issue 15):
## a slab whose back edge sits against the screen and whose front edge sticks out toward the
## viewer. The grid has **columns** across (`cube` px wide, the same width front to back),
## **ranks** going back (the bands, 1 to 5; rank 1 is the front; each is `taper` times as deep
## as the one in front) and **rows** going down the front face (1 to 5, `cube` px each at the
## front). At each end the top steps in by `slant` × that rank's depth: the same on every
## island, so pieces join and corner cuts keep one shape.
##
## Corner cuts: each top corner (fl, fr, bl, br) may be cut by a straight line at 45° in plan,
## k cells in size: k columns along the edge and k ranks along the side. A cut front corner
## turns the front face: a facet of soil runs under the cut.
##
## A pond is a box of cells: columns c0 to c1 (end excluded), ranks 1 to r1, rows 1 to w. Its
## surface is on the top; its front cross-section shows through the front face; a voxel
## (column, rank, row) maps to a screen point and a fish size.
##
## A long island is cut into pieces (left cap, middles, right cap) along column boundaries;
## each piece is at most `piece_max_columns` columns plus `piece_margin` px either side.
##
## Island art px throughout, top-left of the island image at (0, 0). The front edge is always
## the same distance above the face's bottom, so a one-rank ledge is the front slice of a
## five-rank island with the same rows. Pure and immutable once made; the outline treatments
## draw over it and never change it. This is the one implementation of the rules: the bench
## reads it through the guide export (game/tests/shelf_snapshot.gd).

const CORNERS := ["fl", "fr", "bl", "br"]

var columns: int
var bands: int
var rows: int
var cuts := {"fl": 0, "fr": 0, "bl": 0, "br": 0}
## {} or {"c0", "c1", "r1", "w"}.
var pond := {}
## Column counts per piece, left to right.
var pieces: Array = []
var cube: int
var width: int
var taper: float
var band_depth: float
var slant: float
var hang_px: int
## Left, top, right, bottom margins around the slab for wobble, tufts and hanging roots.
var pad: Array
var piece_margin: int
var noise_seed: int
var _sizes: Array
var _size_px: Dictionary
var _fish_px: Dictionary
var _spot_u: Array


## `options`: rows (int), cuts ({fl, fr, bl, br}), pond ({c0, c1, r1, w}), pieces ([int]),
## taper (float, 0 for the configured one). Invalid options fail an assert; check with `problem`.
func _init(column_count: int, band_count: int, shelf: Dictionary, island_seed: int = 0, options: Dictionary = {}) -> void:
	columns = column_count
	bands = band_count
	rows = int(options.get("rows", shelf["rows_default"]))
	for corner in CORNERS:
		cuts[corner] = int(options.get("cuts", {}).get(corner, 0))
	pond = options.get("pond", {})
	pieces = options.get("pieces", [columns])
	cube = int(shelf["cube_px"])
	width = columns * cube
	var t := float(options.get("taper", 0.0))
	taper = t if t > 0.0 else float(shelf["taper_per_band"])
	band_depth = float(shelf["band_depth_px"])
	slant = float(shelf["slant_per_depth"])
	hang_px = int(shelf["underside_hang_px"])
	pad = shelf["pad_px"]
	piece_margin = int(shelf["piece_margin_px"])
	noise_seed = island_seed
	_sizes = shelf["sizes_by_bands"][clampi(bands, 1, 5) - 1]
	_size_px = shelf["size_px"]
	_fish_px = shelf["fish_px"]
	_spot_u = shelf["spot_u"]
	var why := problem(columns, bands, rows, cuts, pond, pieces, shelf)
	assert(why == "", "shelf geometry: " + why)


## Why these settings break the rules, or "" if they are legal.
static func problem(column_count: int, band_count: int, row_count: int, corner_cuts: Dictionary, pond_box: Dictionary,
		piece_columns: Array, shelf: Dictionary) -> String:
	if band_count < 1 or band_count > 5:
		return "ranks must be 1 to 5, not %d" % band_count
	if row_count < 1 or row_count > 5:
		return "rows must be 1 to 5, not %d" % row_count
	if column_count < int(shelf["columns_min"]):
		return "at least %d columns, not %d" % [shelf["columns_min"], column_count]
	var k := {}
	for corner in CORNERS:
		k[corner] = int(corner_cuts.get(corner, 0))
		if k[corner] < 0:
			return "cut %s is negative" % corner
	if k["fl"] + k["fr"] > column_count - 1:
		return "front cuts %d + %d leave no front column" % [k["fl"], k["fr"]]
	var back_cells := back_columns(column_count, band_count, shelf)
	if back_cells < 1.0:
		return "%d columns are too narrow for %d ranks: the back edge would be %.2f columns" % [column_count, band_count, back_cells]
	if k["bl"] + k["br"] > floori(back_cells) - 1:
		return "back cuts %d + %d leave no back column (the back edge is %.2f columns)" % [k["bl"], k["br"], back_cells]
	if k["fl"] + k["bl"] > band_count:
		return "left cuts %d + %d overlap (ranks %d)" % [k["fl"], k["bl"], band_count]
	if k["fr"] + k["br"] > band_count:
		return "right cuts %d + %d overlap (ranks %d)" % [k["fr"], k["br"], band_count]
	var total := 0
	for n in piece_columns:
		if int(n) < 1 or int(n) > int(shelf["piece_max_columns"]):
			return "a piece has %d columns (1 to %d)" % [n, shelf["piece_max_columns"]]
		total += int(n)
	if total != column_count:
		return "pieces add up to %d columns, the island has %d" % [total, column_count]
	if piece_columns.size() > 1:
		if int(piece_columns[0]) <= k["fl"] or int(piece_columns[0]) <= k["bl"] \
				or int(piece_columns[-1]) <= k["fr"] or int(piece_columns[-1]) <= k["br"]:
			return "corner cuts must fit inside the end caps"
	if not pond_box.is_empty():
		var c0 := int(pond_box["c0"])
		var c1 := int(pond_box["c1"])
		if c1 - c0 < 2 or c0 < k["fl"] or c1 > column_count - k["fr"]:
			return "pond columns %d to %d must be 2 or more, inside the uncut front" % [c0, c1]
		if int(pond_box["r1"]) < 1 or int(pond_box["r1"]) > band_count:
			return "pond ranks 1 to %d must be within 1 to %d" % [pond_box["r1"], band_count]
		if int(pond_box["w"]) < 1 or int(pond_box["w"]) > row_count:
			return "pond rows %d must be within 1 to %d" % [pond_box["w"], row_count]
		var cube := float(shelf["cube_px"])
		for z in range(int(pond_box["r1"])):
			var inset_cells := _depth_static(z + 0.5, shelf) * float(shelf["slant_per_depth"]) / cube
			for c in range(c0, c1):
				var from_left := c + 0.5 - inset_cells
				var from_right := column_count - c - 0.5 - inset_cells
				if from_left < 0.0 or from_right < 0.0 or _cut_at(from_left, from_right, z + 0.5, band_count, k):
					return "the pond runs into a corner cut or off the slanted side"
	return ""


## How many columns wide the back edge of an island this size is (fractional: the slant
## clips the end columns).
static func back_columns(column_count: int, band_count: int, shelf: Dictionary) -> float:
	var inset := _depth_static(band_count, shelf) * float(shelf["slant_per_depth"])
	return (column_count * float(shelf["cube_px"]) - 2.0 * inset) / float(shelf["cube_px"])


static func _depth_static(z: float, shelf: Dictionary) -> float:
	var depth := 0.0
	var d := float(shelf["band_depth_px"])
	var t := float(shelf["taper_per_band"])
	var whole := floori(z)
	for b in whole:
		depth += d * pow(t, b)
	return depth + (z - whole) * d * pow(t, whole)


func image_size() -> Vector2i:
	return Vector2i(int(pad[0]) + width + int(pad[2]), int(face_bottom()) + hang_px + int(pad[3]))


func left_x() -> float:
	return float(pad[0])


func center_x() -> float:
	return left_x() + width / 2.0


## The front edge of the top: where the top meets the front face.
func front_y() -> float:
	return float(pad[1]) + ceilf(depth_to(bands))


func face_bottom() -> float:
	return front_y() + rows * cube


## How far back from the front edge depth `z` (in ranks, may be fractional) lies, in px.
func depth_to(z: float) -> float:
	var depth := 0.0
	var whole := floori(z)
	for b in whole:
		depth += band_depth * pow(taper, b)
	return depth + (z - whole) * band_depth * pow(taper, whole)


## The rank depth (0 at the front edge, `bands` at the back) of art row `y`.
func z_at(y: float) -> float:
	var back := front_y() - y
	var z := 0.0
	for b in bands:
		var d := band_depth * pow(taper, b)
		if back <= d:
			return z + back / d
		back -= d
		z += 1.0
	return float(bands)


## Edge `i` of the bands: 0 is the front edge, `bands` the back edge.
func edge_y(i: float) -> float:
	return front_y() - depth_to(i)


## How far each end of the top steps in at depth `z`.
func inset(z: float) -> float:
	return slant * depth_to(z)


func side_x(z: float, right: bool) -> float:
	return left_x() + width - inset(z) if right else left_x() + inset(z)


## Half the top's width at edge `i` (before corner cuts).
func edge_half_width(i: float) -> float:
	return width / 2.0 - inset(i)


## Plan position of an art point on the top: columns in from the left and right sides, and
## ranks back from the front edge.
func plan(point: Vector2) -> Dictionary:
	var z := z_at(point.y)
	return {"z": z, "left": (point.x - side_x(z, false)) / cube, "right": (side_x(z, true) - point.x) / cube}


## Whether a plan point is in a corner cut: `from_left` and `from_right` in columns from each
## side at that depth, `z` in ranks from the front edge.
static func _cut_at(from_left: float, from_right: float, z: float, band_count: int, k: Dictionary) -> bool:
	return from_left + z < k["fl"] or from_right + z < k["fr"] \
			or from_left + (band_count - z) < k["bl"] or from_right + (band_count - z) < k["br"]


func in_cut(point: Vector2) -> bool:
	var p := plan(point)
	return _cut_at(p["left"], p["right"], p["z"], bands, cuts) if _has_cuts() else false


func _has_cuts() -> bool:
	return cuts["fl"] + cuts["fr"] + cuts["bl"] + cuts["br"] > 0


## True on the top (between the front and back edges, inside the sides, outside every cut).
func in_top(point: Vector2) -> bool:
	if point.y > front_y() or point.y < edge_y(bands):
		return false
	var z := z_at(point.y)
	if point.x < side_x(z, false) or point.x > side_x(z, true):
		return false
	return not in_cut(point)


## The top's outline, clockwise from the front-left: front edge, front-right cut, right side,
## back-right cut, back edge, back-left cut, left side, front-left cut. Exact: the sides and
## cuts are straight within each rank, so a point at every rank edge is enough.
func top_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	var b := float(bands)
	out.append(Vector2(side_x(0, false) + cuts["fl"] * cube, front_y()))
	out.append(Vector2(side_x(0, true) - cuts["fr"] * cube, front_y()))
	_cut_line(out, 0.0, float(cuts["fr"]), true, func(z: float) -> float: return cuts["fr"] - z)
	_side(out, float(cuts["fr"]), b - cuts["br"], true)
	_cut_line(out, b - cuts["br"], b, true, func(z: float) -> float: return cuts["br"] - (b - z))
	out.append(Vector2(side_x(b, true) - cuts["br"] * cube, edge_y(b)))
	out.append(Vector2(side_x(b, false) + cuts["bl"] * cube, edge_y(b)))
	_cut_line(out, b, b - cuts["bl"], false, func(z: float) -> float: return cuts["bl"] - (b - z))
	_side(out, b - cuts["bl"], float(cuts["fl"]), false)
	_cut_line(out, float(cuts["fl"]), 0.0, false, func(z: float) -> float: return cuts["fl"] - z)
	return _dedupe(out)


## Points along a cut from depth `z0` to `z1`, `cells_in(z)` columns in from that side.
func _cut_line(out: PackedVector2Array, z0: float, z1: float, right: bool, cells_in: Callable) -> void:
	if z0 == z1:
		return
	for z in _depths(z0, z1):
		var dx: float = cells_in.call(z) * cube
		out.append(Vector2(side_x(z, right) - dx if right else side_x(z, right) + dx, edge_y(z)))


func _side(out: PackedVector2Array, z0: float, z1: float, right: bool) -> void:
	for z in _depths(z0, z1):
		out.append(Vector2(side_x(z, right), edge_y(z)))


## `z0`, every whole rank edge strictly between, and `z1`, in order.
static func _depths(z0: float, z1: float) -> Array:
	var out: Array = [z0]
	if z1 > z0:
		for z in range(floori(z0) + 1, ceili(z1)):
			out.append(float(z))
	else:
		for z in range(ceili(z0) - 1, floori(z1), -1):
			out.append(float(z))
	out.append(z1)
	return out


static func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or not out[-1].is_equal_approx(p):
			out.append(p)
	if out.size() > 1 and out[0].is_equal_approx(out[-1]):
		out.remove_at(out.size() - 1)
	return out


## Band `band` (1 is the front) before corner cuts: front-left, front-right, back-right, back-left.
func band_polygon(band: int) -> PackedVector2Array:
	var z0 := float(band - 1)
	var z1 := float(band)
	return PackedVector2Array([
		Vector2(side_x(z0, false), edge_y(z0)), Vector2(side_x(z0, true), edge_y(z0)),
		Vector2(side_x(z1, true), edge_y(z1)), Vector2(side_x(z1, false), edge_y(z1))])


## The cell (column, rank) on the top, clipped by the sides and any cut: [] if none of it is left.
func cell_polygon(column: int, rank: int) -> Array:
	var x0 := left_x() + column * cube
	var strip := PackedVector2Array([
		Vector2(x0, edge_y(rank - 1)), Vector2(x0 + cube, edge_y(rank - 1)),
		Vector2(x0 + cube, edge_y(rank)), Vector2(x0, edge_y(rank))])
	return Geometry2D.intersect_polygons(strip, top_polygon())


## The column under art x (on the grid, whatever the depth), or -1 outside.
func column_at(x: float) -> int:
	var c := floori((x - left_x()) / cube)
	return c if c >= 0 and c < columns else -1


## The straight part of the front face (between any front cuts).
func front_face() -> Rect2:
	var x0: float = side_x(0, false) + cuts["fl"] * cube
	var x1: float = side_x(0, true) - cuts["fr"] * cube
	return Rect2(x0, front_y(), x1 - x0, rows * cube)


## Height of the front face (its rows) at depth `z`, foreshortened like everything else.
func wall_height(z: float) -> float:
	return rows * cube * pow(taper, z)


## A cut front corner's facet: the soil wall under the cut, as one polygon (top edge from the
## front edge back to the side, bottom edge back again), or [] if that corner is not cut.
func facet(right: bool) -> PackedVector2Array:
	var k := float(cuts["fr" if right else "fl"])
	if k == 0:
		return PackedVector2Array()
	var top := PackedVector2Array()
	_cut_line(top, 0.0, k, right, func(z: float) -> float: return k - z)
	var out := PackedVector2Array(top)
	for i in range(top.size() - 1, -1, -1):
		out.append(top[i] + Vector2(0, wall_height(z_at(top[i].y))))
	return out


func facets() -> Array:
	var out: Array = []
	for right in [false, true]:
		var f := facet(right)
		if not f.is_empty():
			out.append(f)
	return out


## The bottom of the face and facets, left to right: where the underside hangs from.
func bottom_outline() -> PackedVector2Array:
	var points: Array = []
	for f in facets():
		# A facet is its top edge then its bottom edge back again: keep the bottom half.
		for i in range(f.size() / 2, f.size()):
			points.append(f[i])
	var face := front_face()
	points.append(Vector2(face.position.x, face.end.y))
	points.append(Vector2(face.end.x, face.end.y))
	points.sort()
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or not out[-1].is_equal_approx(p):
			out.append(p)
	return out


## The bottom outline's y at art x (its ends hold outside).
func bottom_y(x: float) -> float:
	var line := bottom_outline()
	if x <= line[0].x:
		return line[0].y
	for i in range(1, line.size()):
		if x <= line[i].x:
			var a := line[i - 1]
			var b := line[i]
			return a.y if is_equal_approx(a.x, b.x) else lerpf(a.y, b.y, (x - a.x) / (b.x - a.x))
	return line[-1].y


## The floating underside, from the bottom outline's right end round to its left end: a
## tapering point, seeded so the island always looks the same.
func underside() -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([noise_seed, "underside"])
	var line := bottom_outline()
	var left := line[0].x
	var right := line[-1].x
	var span := right - left
	var tip := 0.5 + rng.randf_range(-0.1, 0.1)
	var steps := maxi(8, int(span) / 9)
	var points := PackedVector2Array()
	for i in steps + 1:
		var s := float(i) / steps
		var k := s / tip * 0.5 if s < tip else 0.5 + (s - tip) / (1.0 - tip) * 0.5
		var depth := 1.0 - pow(absf(2.0 * k - 1.0), 1.5)
		var jitter := 0.0 if i == 0 or i == steps else rng.randf_range(-0.09, 0.09) * hang_px
		var x := right - s * span
		x = lerpf(x, right - tip * span, depth * depth * 0.4)
		points.append(Vector2(x, bottom_y(x) + maxf(0.0, depth * hang_px + jitter * depth)))
	points[0] = line[-1]
	points[-1] = line[0]
	return points


## The silhouette's outer edge before softening, from the bottom-left up and round to the
## bottom-right: [{"at", "part"}], part "face" for a vertical face or facet edge, "top" for
## the rest. The outline treatments soften this; the underside closes it.
func rim_corners() -> Array:
	var top := top_polygon()
	var bottom := bottom_outline()
	# The top polygon runs from the front-left along the front edge, up the right side and back
	# down the left; the visible rim runs the other way: from where the left wall meets the top,
	# up the left side, along the back and down the right side.
	var i := _index_of(top, Vector2(side_x(float(cuts["fl"]), false), edge_y(float(cuts["fl"]))))
	var last := _index_of(top, Vector2(side_x(float(cuts["fr"]), true), edge_y(float(cuts["fr"]))))
	var out: Array = [{"at": bottom[0], "part": "face"}]
	while true:
		out.append({"at": top[i], "part": "top"})
		if i == last:
			break
		i = (i - 1 + top.size()) % top.size()
	out.append({"at": bottom[-1], "part": "face"})
	return out


static func _index_of(points: PackedVector2Array, target: Vector2) -> int:
	var best := 0
	for i in points.size():
		if points[i].distance_to(target) < points[best].distance_to(target):
			best = i
	return best


## The art point of `u` (0 left, 1 right) across the middle of band `band`'s depth, side to side.
func point_at(band: int, u: float) -> Vector2:
	var z := band - 0.5
	return Vector2(lerpf(side_x(z, false), side_x(z, true), u), edge_y(z))


## {"band", "u", "column"} for an art point on the top, or {} off it (for clicks).
func locate(point: Vector2) -> Dictionary:
	if not in_top(point):
		return {}
	var z := z_at(point.y)
	var band := clampi(floori(z) + 1, 1, bands)
	var u := (point.x - side_x(z, false)) / (side_x(z, true) - side_x(z, false))
	return {"band": band, "u": u, "column": column_at(point.x)}


func size_class(band: int) -> String:
	return String(_sizes[band - 1])


func size_px(band: int) -> int:
	return int(_size_px[size_class(band)])


## Every perch left on the top after cuts: a few points across each band, with the creature size.
func spots() -> Array:
	var out: Array = []
	for band in range(1, bands + 1):
		for u in _spot_u:
			var at := point_at(band, float(u))
			if in_top(at):
				out.append({"band": band, "u": float(u), "at": at, "size": size_class(band)})
	return out


## The pond's surface rectangle in plan, as an art polygon on the top ([] without a pond).
func pond_surface() -> PackedVector2Array:
	if pond.is_empty():
		return PackedVector2Array()
	var x0: float = left_x() + int(pond["c0"]) * cube
	var x1: float = left_x() + int(pond["c1"]) * cube
	var y1 := edge_y(float(pond["r1"]))
	return PackedVector2Array([Vector2(x0, front_y()), Vector2(x1, front_y()), Vector2(x1, y1), Vector2(x0, y1)])


## The pond's cross-section seen through the front face.
func pond_window() -> Rect2:
	if pond.is_empty():
		return Rect2()
	var x0: float = left_x() + int(pond["c0"]) * cube
	return Rect2(x0, front_y(), (int(pond["c1"]) - int(pond["c0"])) * cube, int(pond["w"]) * cube)


## The art point at the middle of voxel (column, rank, row) in the pond: x on its column, y
## its row's depth below the surface at its rank, foreshortened by rank like everything else.
func voxel_point(column: int, rank: int, row: int) -> Vector2:
	var z := rank - 0.5
	return Vector2(left_x() + (column + 0.5) * cube, edge_y(z) + (row - 0.5) * cube * pow(taper, z))


## Swimming-fish size at rank `rank`, by the island's rank mapping.
func fish_px(rank: int) -> int:
	return int(_fish_px[size_class(rank)])


## Each piece's rect in island art px: its columns plus `piece_margin` either side (the end
## caps take the island's own side margins), and the seam x between neighbours.
func piece_rects() -> Array:
	var out: Array = []
	var start := 0
	var h := image_size().y
	for i in pieces.size():
		var n := int(pieces[i])
		var x0 := 0.0 if i == 0 else left_x() + start * cube - piece_margin
		var x1 := float(image_size().x) if i == pieces.size() - 1 else left_x() + (start + n) * cube + piece_margin
		out.append({"rect": Rect2i(int(x0), 0, int(x1 - x0), h), "columns": [start, start + n]})
		start += n
	return out


func seams() -> Array:
	var out: Array = []
	var start := 0
	for i in pieces.size() - 1:
		start += int(pieces[i])
		out.append(left_x() + start * cube)
	return out
