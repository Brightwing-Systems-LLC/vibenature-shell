class_name ShelfRenderer
extends RefCounted

## Draws a placeholder shelf island from its ShelfGeometry, pixel by pixel on palette
## colours (contracts/palette.hex): a shaded grass top with tufts and flowers, a lip with
## grass hanging over it wherever the top meets a wall, a soil cross-section with stones and
## roots, a soil facet under each cut front corner, and a floating underside with hanging
## roots and loose rocks. A pond is a box of cells: water on its surface cells and, through
## the front face, its cross-section, darker row by row. Seeded: the same island always
## draws the same.

const EMPTY := 0
const TOP := 1
const FACE := 2
const UNDER := 3
const WATER := 4
## A cut front corner's soil wall.
const FACET := 5
## The pond seen through the front face.
const WATER_VOL := 6

const GRASS_DARKEST := Color("165a4c")
const GRASS_DARK := Color("239063")
const GRASS := Color("1ebc73")
const GRASS_LIGHT := Color("91db69")
const LIP := Color("cddf6c")
const SOIL_EXPOSED := Color("9e4539")
const SOIL_SHADOW := Color("6e2727")
const SOIL_0 := Color("9e4539")
const SOIL_1 := Color("7a3045")
const SOIL_2 := Color("45293f")
const ROCK_0 := Color("45293f")
const ROCK_1 := Color("3e3546")
const ROCK_2 := Color("2e222f")
const ROCK_SPECK := Color("625565")
const STONE := Color("7f708a")
const STONE_LIGHT := Color("9babb2")
const ROOT := Color("966c6c")
const ROOT_DARK := Color("694f62")
const WATER_TOP := Color("4d9be6")
const WATER_EDGE := Color("4d65b4")
const WATER_LIGHT := Color("8fd3ff")
const WATER_DEEP := Color("484a77")
const WATER_DEEPEST := Color("323353")
const WHITE := Color("ffffff")
const FLOWERS := [Color("ffffff"), Color("ed8099"), Color("a884f3"), Color("fbff86")]
const FLOWER_EYE := Color("f9c22b")
const BAND_TINTS := [Color("cddf6c"), Color("0eaf9b")]
const BAND_LINE := Color("fbff86")
const GRID_LINE := Color("fbff86")
const REGION_COLORS := {1: Color("1ebc73"), 2: Color("9e4539"), 3: Color("625565"), 4: Color("4d9be6"), 5: Color("cd683d"), 6: Color("4d65b4")}

var geo: ShelfGeometry
var shelf: Dictionary
var treatment := "A"
var rng := RandomNumberGenerator.new()
var image: Image
var rim_path: Array = []
var _kind := PackedByteArray()
## Per column, how far the lip rises above the front edge into a round or sliced front corner.
var _lift := PackedInt32Array()
## Per column, the bottom of the face or facet above the underside.
var _bottom := PackedFloat32Array()
var _facets: Array = []
var _w := 0
var _h := 0


## `options`: treatment ("A"–"D"), front_corners ([left, right], see ShelfOutlines.rim),
## pond, band_tint, band_lines, grid (bools). The pond box itself is on the geometry.
static func render(island: ShelfGeometry, shelf_config: Dictionary, options: Dictionary = {}) -> Image:
	return drawn(island, shelf_config, options).image


## The renderer after drawing, for its image and its maps.
static func drawn(island: ShelfGeometry, shelf_config: Dictionary, options: Dictionary = {}) -> ShelfRenderer:
	var r := ShelfRenderer.new()
	r.geo = island
	r.shelf = shelf_config
	r.treatment = String(options.get("treatment", "A"))
	r.rng.seed = hash([island.noise_seed, island.width, island.bands, island.rows])
	r._draw(options)
	return r


## Which part of the island each pixel is, one flat colour per region (REGION_COLORS: top,
## face, underside, water surface, facet, water seen through the front): the target an art
## generator is measured against.
func region_image() -> Image:
	var out := Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	for y in _h:
		for x in _w:
			var k := _kind[y * _w + x]
			if k != EMPTY:
				out.set_pixel(x, y, REGION_COLORS[k])
	return out


## Each top and water-surface pixel's cell: red = column + 1, green = rank, blue 0.
func cell_image() -> Image:
	var out := Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	for y in _h:
		var rank := clampi(floori(geo.z_at(y + 0.5)) + 1, 1, geo.bands)
		for x in _w:
			var k := _kind[y * _w + x]
			var c := geo.column_at(x + 0.5)
			if (k == TOP or k == WATER) and c >= 0:
				out.set_pixel(x, y, Color8(c + 1, rank, 0))
	return out


## The pond's pixels by voxel: on the surface red = column + 1, green = rank, blue 0; through
## the front red = column + 1, green 0, blue = row.
func voxel_image() -> Image:
	var out := Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	var front := geo.front_y()
	for y in _h:
		var rank := clampi(floori(geo.z_at(y + 0.5)) + 1, 1, geo.bands)
		for x in _w:
			var k := _kind[y * _w + x]
			var c := geo.column_at(x + 0.5)
			if k == WATER:
				out.set_pixel(x, y, Color8(c + 1, rank, 0))
			elif k == WATER_VOL:
				out.set_pixel(x, y, Color8(c + 1, 0, floori((y + 0.5 - front) / geo.cube) + 1))
	return out


func _draw(options: Dictionary) -> void:
	var size := geo.image_size()
	_w = size.x
	_h = size.y
	image = Image.create_empty(_w, _h, false, Image.FORMAT_RGBA8)
	_kind.resize(_w * _h)
	_kind.fill(EMPTY)
	_bottom.resize(_w)
	for x in _w:
		_bottom[x] = geo.bottom_y(x + 0.5)
	_facets = geo.facets()
	var corners: Array = options.get("front_corners", ["square", "square"])
	rim_path = ShelfOutlines.rim(geo, treatment, shelf, corners)
	_lift = ShelfOutlines.lip_lift(geo, shelf, corners, _w)
	_fill(ShelfOutlines.silhouette(geo, rim_path))
	ShelfOutlines.cut(treatment, self)
	_paint_regions()
	_darken_edges()
	_top_detail()
	if not geo.pond.is_empty():
		_pond()
	_lip()
	_face_detail()
	_underside_detail()
	ShelfOutlines.decorate(treatment, self)
	if bool(options.get("band_tint", false)):
		_band_tint()
	if bool(options.get("band_lines", false)):
		_band_lines()
	if bool(options.get("grid", false)):
		_grid()


func kind_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return EMPTY
	return _kind[y * _w + x]


static func is_wall(k: int) -> bool:
	return k == FACE or k == FACET


## Sets a pixel. Anything painted outside the slab counts as `kind` there: underside for a
## root or a rock, top for a grass tuft hanging over the rim.
func paint(at: Vector2, color: Color, kind: int = UNDER) -> void:
	var x := floori(at.x)
	var y := floori(at.y)
	if x < 0 or y < 0 or x >= _w or y >= _h:
		return
	image.set_pixel(x, y, color)
	if _kind[y * _w + x] == EMPTY:
		_kind[y * _w + x] = kind


func cut_disc(center: Vector2, radius: float) -> void:
	for y in range(floori(center.y - radius), ceili(center.y + radius) + 1):
		for x in range(floori(center.x - radius), ceili(center.x + radius) + 1):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius and kind_at(x, y) != EMPTY:
				_kind[y * _w + x] = EMPTY


## The lowest opaque row in column `x`, or -1.
func column_bottom(x: int) -> int:
	for y in range(_h - 1, -1, -1):
		if kind_at(x, y) != EMPTY:
			return y
	return -1


func _in_facet(p: Vector2) -> bool:
	for f in _facets:
		if Geometry2D.is_point_in_polygon(p, f):
			return true
	return false


## Scanline fill of the silhouette into the region map.
func _fill(polygon: PackedVector2Array) -> void:
	var front := geo.front_y()
	var facet_top := front
	for f in _facets:
		for p in f:
			facet_top = minf(facet_top, p.y)
	var top := geo.top_polygon()
	for y in _h:
		var yc := y + 0.5
		var xs: Array[float] = []
		for i in polygon.size():
			var a := polygon[i]
			var b := polygon[(i + 1) % polygon.size()]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y))
		xs.sort()
		for j in range(0, xs.size() - 1, 2):
			for x in range(maxi(0, ceili(xs[j] - 0.5)), mini(_w, ceili(xs[j + 1] - 0.5))):
				_kind[y * _w + x] = _classify(Vector2(x + 0.5, yc), front - _lift[x], facet_top, top)


## Which part a silhouette pixel is: below the face's or a facet's bottom it is underside; in a
## facet, facet; above the front edge, top (or, outside the top and nearer a facet than the
## top, that facet's softened edge); otherwise face.
func _classify(p: Vector2, front: float, facet_top: float, top: PackedVector2Array) -> int:
	var x := clampi(floori(p.x), 0, _w - 1)
	if p.y >= _bottom[x]:
		return UNDER
	if _facets.is_empty() or p.y < facet_top:
		return TOP if p.y < front else FACE
	if _in_facet(p):
		return FACET
	if p.y >= front:
		return FACE
	if geo.in_top(p):
		return TOP
	var to_top := _distance(p, top)
	for f in _facets:
		if _distance(p, f) < to_top:
			return FACET
	return TOP


static func _distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])))
	return best


func _band_of(y: float) -> int:
	return clampi(floori(geo.z_at(y)) + 1, 1, geo.bands)


func _paint_regions() -> void:
	var s := geo.noise_seed
	var front := geo.front_y()
	var wall := float(geo.rows * geo.cube)
	for y in _h:
		var yc := y + 0.5
		var band_shift := (_band_of(yc) - 1) * 0.05
		for x in _w:
			match _kind[y * _w + x]:
				TOP:
					var v := noise2(x / 7.0, y / 3.0, s) * 0.75 + hash01(x, y, s) * 0.25 - band_shift
					image.set_pixel(x, y, GRASS_DARK if v < 0.32 else (GRASS if v < 0.78 else GRASS_LIGHT))
				FACE, FACET:
					var f := (yc - front) / wall + (hash01(x, y, s + 5) - 0.5) * 0.08
					if _kind[y * _w + x] == FACET:
						f += 0.34
					var b1 := 0.32 + noise1(x / 9.0, s + 1) * 0.08
					var b2 := 0.66 + noise1(x / 11.0, s + 2) * 0.08
					image.set_pixel(x, y, SOIL_0 if f < b1 else (SOIL_1 if f < b2 else SOIL_2))
				UNDER:
					var t := (yc - _bottom[x]) / maxf(1.0, geo.hang_px) + (hash01(x, y, s + 7) - 0.5) * 0.15
					var c := ROCK_0 if t < 0.25 else (ROCK_1 if t < 0.6 else ROCK_2)
					if hash01(x, y, s + 9) < 0.04:
						c = ROCK_SPECK
					image.set_pixel(x, y, c)


## One darker pixel round the outside of each region, so the silhouette reads.
func _darken_edges() -> void:
	var dark := {TOP: GRASS_DARKEST, FACE: SOIL_2, FACET: SOIL_2, UNDER: ROCK_2}
	for y in _h:
		for x in _w:
			var k := kind_at(x, y)
			if k == EMPTY:
				continue
			if kind_at(x - 1, y) == EMPTY or kind_at(x + 1, y) == EMPTY or kind_at(x, y - 1) == EMPTY or kind_at(x, y + 1) == EMPTY:
				image.set_pixel(x, y, dark[k])


func _random_top_point() -> Vector2i:
	for attempt in 50:
		var x := rng.randi_range(0, _w - 1)
		var y := rng.randi_range(0, floori(geo.front_y()) - 3)
		if kind_at(x, y) == TOP and kind_at(x, y - 2) == TOP and kind_at(x - 1, y) == TOP and kind_at(x + 1, y) == TOP:
			return Vector2i(x, y)
	return Vector2i(-1, -1)


func _top_detail() -> void:
	var top := geo.top_polygon()
	var area := 0.0
	for i in top.size():
		area += top[i].cross(top[(i + 1) % top.size()])
	area = absf(area) / 2.0
	for i in roundi(area / 100.0 * float(shelf["grass_tufts_per_100px2"])):
		var p := _random_top_point()
		if p.x < 0:
			continue
		var tall := _band_of(p.y + 0.5) <= 3
		_set_top(p, GRASS_DARK)
		_set_top(p + Vector2i(-1, -1), GRASS_LIGHT)
		_set_top(p + Vector2i(1, -1), GRASS)
		if tall:
			_set_top(p + Vector2i(0, -2), GRASS_LIGHT)
			_set_top(p + Vector2i(-1, 0), GRASS_DARK)
	for i in roundi(area / 100.0 * float(shelf["flowers_per_100px2"])):
		var p := _random_top_point()
		if p.x < 0:
			continue
		var petal: Color = FLOWERS[rng.randi_range(0, FLOWERS.size() - 1)]
		if _band_of(p.y + 0.5) <= 2:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				_set_top(p + d, petal)
			_set_top(p, FLOWER_EYE)
		else:
			_set_top(p, petal)


func _set_top(p: Vector2i, color: Color) -> void:
	if kind_at(p.x, p.y) == TOP:
		image.set_pixel(p.x, p.y, color)


## Per column, the last top row above a wall (the lip), or -1.
func _lip_rows() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(_w)
	out.fill(-1)
	for x in _w:
		for y in range(_h - 1, 0, -1):
			if is_wall(kind_at(x, y)) and kind_at(x, y - 1) == TOP:
				out[x] = y - 1
				break
	return out


## The highlight wherever the top meets a wall, the front face or a cut corner's facet (D: a
## rounded, shaded bevel), and grass blades hanging over it at irregular intervals.
func _lip() -> void:
	var lips := _lip_rows()
	var bevel := ShelfOutlines.bevel_rows(treatment, shelf)
	var ramp: Array = [LIP, GRASS_DARK]
	if bevel > 0:
		ramp = [GRASS_LIGHT, LIP, GRASS, GRASS_DARK, GRASS_DARKEST]
		ramp = ramp.slice(maxi(0, 3 - bevel))
	var above := maxi(1, bevel) - 1
	for x in _w:
		if lips[x] < 0:
			continue
		for i in ramp.size():
			var y := lips[x] - above + i
			var k := kind_at(x, y)
			if (k == TOP or is_wall(k)) and kind_at(x - 1, y) != EMPTY and kind_at(x + 1, y) != EMPTY:
				image.set_pixel(x, y, ramp[i])
	var every: Array = shelf["lip_blades_every_px"]
	var length: Array = shelf["lip_blade_px"]
	var factor := ShelfOutlines.lip_blade_factor(treatment)
	var x := rng.randi_range(0, int(every[1]))
	while x < _w:
		if lips[x] >= 0 and is_wall(kind_at(x, lips[x] + 2)):
			var n := roundi(rng.randi_range(int(length[0]), int(length[1])) * factor)
			for k in n:
				var y := lips[x] + 2 + k
				if not is_wall(kind_at(x, y)):
					break
				image.set_pixel(x, y, GRASS_DARK if k == n - 1 else GRASS)
		x += rng.randi_range(int(every[0]), int(every[1]))


func _face_detail() -> void:
	var face := geo.front_face()
	var front := floori(geo.front_y())
	var wall := geo.rows * geo.cube
	var scale := face.size.x / 176.0 * geo.rows / 2.0
	for i in maxi(1, roundi(int(shelf["stones"]) * scale)):
		var w := rng.randi_range(3, 5)
		var h := rng.randi_range(2, 3)
		var at := Vector2i(rng.randi_range(int(face.position.x) + 2, maxi(int(face.position.x) + 2, int(face.end.x) - w - 2)),
				rng.randi_range(front + 3, maxi(front + 3, front + wall - h - 1)))
		for y in h:
			for x in w:
				if (x == 0 or x == w - 1) and (y == 0 or y == h - 1):
					continue
				var p := at + Vector2i(x, y)
				if kind_at(p.x, p.y) == FACE:
					image.set_pixel(p.x, p.y, STONE_LIGHT if y == 0 and x <= 1 else (ROCK_1 if y == h - 1 else STONE))
	for i in maxi(1, roundi(int(shelf["roots"]) * face.size.x / 176.0)):
		var x := rng.randi_range(int(face.position.x) + 4, maxi(int(face.position.x) + 4, int(face.end.x) - 4))
		var n := rng.randi_range(roundi(wall * 0.4), roundi(wall * 0.85))
		for k in n:
			var y := front + 2 + k
			if kind_at(x, y) != FACE:
				break
			image.set_pixel(x, y, ROOT)
			if kind_at(x + 1, y) == FACE:
				image.set_pixel(x + 1, y, ROOT_DARK)
			if rng.randf() < 0.3:
				x += rng.randi_range(-1, 1)


func _underside_detail() -> void:
	var line := geo.bottom_outline()
	var x0 := int(line[0].x)
	var x1 := int(line[-1].x)
	for i in int(shelf["hanging_roots"]):
		var x := rng.randi_range(x0 + 6, maxi(x0 + 6, x1 - 6))
		var y := column_bottom(x) - 1
		for k in rng.randi_range(5, 14):
			y += 1
			paint(Vector2(x, y), ROOT if k % 4 != 3 else ROOT_DARK)
			if rng.randf() < 0.25:
				x += rng.randi_range(-1, 1)
	var under := geo.underside()
	var tip := under[0]
	for p in under:
		if p.y > tip.y:
			tip = p
	for i in int(shelf["loose_rocks"]):
		var x := roundi(tip.x + rng.randf_range(-0.22, 0.22) * (x1 - x0))
		var bottom := column_bottom(x)
		if bottom < 0:
			continue
		var w := rng.randi_range(2, 4)
		var h := rng.randi_range(2, 3)
		var y := bottom + rng.randi_range(3, 9)
		for dy in h:
			for dx in w:
				paint(Vector2(x + dx, y + dy), STONE if dy == 0 and dx == 0 else (ROCK_1 if dy == h - 1 else ROCK_SPECK))


## The pond box: water on its surface cells; through the front face its cross-section, one
## shade darker per row, with the box's back-bottom edge showing faintly through the water
## in perspective and a thin line of soil beneath.
func _pond() -> void:
	var cfg: Dictionary = shelf["pond"]
	var surface := geo.pond_surface()
	var box := Rect2(surface[0].x, surface[2].y, surface[1].x - surface[0].x, surface[0].y - surface[2].y)
	for y in range(floori(box.position.y), ceili(box.end.y)):
		for x in range(floori(box.position.x), ceili(box.end.x)):
			if kind_at(x, y) == TOP and box.has_point(Vector2(x + 0.5, y + 0.5)):
				_kind[y * _w + x] = WATER
				image.set_pixel(x, y, WATER_TOP)
	for y in range(floori(box.position.y), ceili(box.end.y)):
		for x in range(floori(box.position.x), ceili(box.end.x)):
			if kind_at(x, y) == WATER:
				for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
					if kind_at(x + d.x, y + d.y) == TOP:
						image.set_pixel(x + d.x, y + d.y, GRASS_DARKEST)
						image.set_pixel(x, y, WATER_EDGE)
	var water: Array[Vector2i] = []
	for y in range(floori(box.position.y), ceili(box.end.y)):
		for x in range(floori(box.position.x), ceili(box.end.x)):
			if kind_at(x, y) == WATER and kind_at(x, y - 1) == WATER and kind_at(x - 3, y) == WATER and kind_at(x + 6, y) == WATER:
				water.append(Vector2i(x, y))
	if not water.is_empty():
		for i in 3:
			var p: Vector2i = water[rng.randi_range(0, water.size() - 1)]
			for dx in rng.randi_range(3, 6):
				if kind_at(p.x + dx, p.y) == WATER:
					image.set_pixel(p.x + dx, p.y, WATER_LIGHT)
		var glint: Vector2i = water[rng.randi_range(0, water.size() - 1)]
		image.set_pixel(glint.x, glint.y, WHITE)
		if kind_at(glint.x + 1, glint.y) == WATER:
			image.set_pixel(glint.x + 1, glint.y, WHITE)
		for i in int(cfg["lily_pads"]):
			var p: Vector2i = water[rng.randi_range(0, water.size() - 1)]
			for dy in range(-2, 2):
				for dx in range(-5, 6):
					if pow(dx / 5.5, 2) + pow((dy + 0.5) / 2.0, 2) > 1.0 or kind_at(p.x + dx, p.y + dy) != WATER:
						continue
					if dx >= 1 and dx <= 2 and dy == -2:
						continue
					image.set_pixel(p.x + dx, p.y + dy, GRASS_LIGHT if dy == -2 else (GRASS if dy < 1 else GRASS_DARK))
			if i == 0 and kind_at(p.x - 2, p.y - 2) == WATER:
				image.set_pixel(p.x - 2, p.y - 1, FLOWERS[1])
				image.set_pixel(p.x - 2, p.y - 2, FLOWERS[0])
	var window := geo.pond_window()
	var shades := [WATER_TOP, WATER_EDGE, WATER_DEEP, WATER_DEEPEST, WATER_DEEPEST]
	for y in range(floori(window.position.y), ceili(window.end.y)):
		var row := floori((y + 0.5 - window.position.y) / geo.cube)
		for x in range(floori(window.position.x), ceili(window.end.x)):
			if not is_wall(kind_at(x, y)):
				continue
			_kind[y * _w + x] = WATER_VOL
			image.set_pixel(x, y, WATER_LIGHT if y == floori(window.position.y) else shades[mini(row, shades.size() - 1)])
	# The back-bottom edge of the box, seen through the water, and its two receding sides.
	var r1 := float(geo.pond["r1"])
	var back_y: float = geo.edge_y(r1) + geo.pond["w"] * geo.cube * pow(geo.taper, r1)
	for x in range(floori(window.position.x), ceili(window.end.x)):
		if kind_at(x, floori(back_y)) == WATER_VOL and x % 2 == 0:
			image.set_pixel(x, floori(back_y), WATER_DEEP)
	for y in range(floori(window.position.y), ceili(window.end.y)):
		for x in range(floori(window.position.x) - 1, ceili(window.end.x) + 1):
			if is_wall(kind_at(x, y)) and (kind_at(x - 1, y) == WATER_VOL or kind_at(x + 1, y) == WATER_VOL):
				image.set_pixel(x, y, SOIL_2)
	var below := ceili(window.end.y)
	for x in range(floori(window.position.x), ceili(window.end.x)):
		if is_wall(kind_at(x, below)):
			image.set_pixel(x, below, SOIL_2)


## Debug: a faint tint per band, so the bands stay readable.
func _band_tint() -> void:
	var amount := float(shelf["band_tint"])
	for y in _h:
		var tint: Color = BAND_TINTS[(_band_of(y + 0.5) - 1) % 2]
		for x in _w:
			if kind_at(x, y) == TOP:
				image.set_pixel(x, y, image.get_pixel(x, y).lerp(tint, amount))


## Debug: dotted lines along the band edges.
func _band_lines() -> void:
	for i in range(1, geo.bands):
		var y := floori(geo.edge_y(i))
		for x in range(ceili(geo.side_x(i, false)), floori(geo.side_x(i, true))):
			if x % 2 == 0 and (kind_at(x, y) == TOP or kind_at(x, y) == WATER):
				image.set_pixel(x, y, BAND_LINE)


## Debug: the grid. Column lines on the top, and in a pond the middle of every voxel seen
## through the front and every surface cell.
func _grid() -> void:
	for c in range(1, geo.columns):
		var x := floori(geo.left_x() + c * geo.cube)
		for y in _h:
			if y % 2 == 0 and (kind_at(x, y) == TOP or kind_at(x, y) == WATER):
				image.set_pixel(x, y, GRID_LINE)
	if geo.pond.is_empty():
		return
	for rank in range(1, int(geo.pond["r1"]) + 1):
		for row in range(1, int(geo.pond["w"]) + 1):
			for c in range(int(geo.pond["c0"]), int(geo.pond["c1"])):
				var p := geo.voxel_point(c, rank, row)
				var k := kind_at(floori(p.x), floori(p.y))
				if k == WATER or k == WATER_VOL:
					image.set_pixel(floori(p.x), floori(p.y), WHITE if rank == 1 else GRID_LINE)


## A seeded, repeatable value in [0, 1) for an integer point.
static func hash01(x: int, y: int, s: int) -> float:
	var n := (x * 73856093) ^ (y * 19349663) ^ (s * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0xffff) / 65536.0


## Smooth seeded noise along a line, in [-1, 1].
static func noise1(t: float, s: int) -> float:
	var i := floori(t)
	var f := t - i
	f = f * f * (3.0 - 2.0 * f)
	return lerpf(hash01(i, 0, s), hash01(i + 1, 0, s), f) * 2.0 - 1.0


## Smooth seeded noise over a plane, in [0, 1).
static func noise2(x: float, y: float, s: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	fx = fx * fx * (3.0 - 2.0 * fx)
	fy = fy * fy * (3.0 - 2.0 * fy)
	var top := lerpf(hash01(ix, iy, s), hash01(ix + 1, iy, s), fx)
	var bottom := lerpf(hash01(ix, iy + 1, s), hash01(ix + 1, iy + 1, s), fx)
	return lerpf(top, bottom, fy)
