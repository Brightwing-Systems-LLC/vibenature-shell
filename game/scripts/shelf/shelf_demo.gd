class_name ShelfDemo
extends Node

## The shelf-island prototype (VIBENATURE_SHELF_DEMO=1), in place of today's islands. Shows
## one set of islands at a time, each in its own window, switched from the debug panel's
## "Shelf demo" section (Option-click home):
##   bands     a 1-rank ledge, a 3-rank and a 5-rank island
##   rows      a 3-rank island with a front face 1, 3 and 5 rows deep
##   widths    a 3-rank island 7, 11 and 15 columns wide
##   outlines  the same island once per outline treatment, A–D
##   corners   corner cuts: one corner, a larger one, all four, a mix
##   pond      voxel-box ponds with a fish stepping through the grid in all three directions
##   pieces    a long island built from a left cap, two middles and a right cap
##   tune      one island whose columns, ranks, rows, cuts and pond change live
## The band module (taper) is shared by every island, so changing it changes them all.

const SETS := ["bands", "rows", "widths", "outlines", "corners", "pond", "pieces", "tune"]
## Where each band's placeholder bird perches across (u), front band first.
const BIRD_U := [0.8, 0.28, 0.68, 0.36, 0.6]
const NO_CUTS := {"fl": 0, "fr": 0, "bl": 0, "br": 0}

var game: Game
var shelf: Dictionary
var state := {
	"set": "bands", "columns": 11, "bands": 3, "rows": 2, "cuts": NO_CUTS.duplicate(), "pond": -1,
	"treatment": "A", "seed": 1, "left_corner": "square", "right_corner": "square",
	"band_tint": true, "band_lines": true, "grid": true, "seams": true, "stroll": false, "art_scale": 1,
}
var last_click := ""
var windows: Array[ShelfIslandWindow] = []

static var _birds := {}
static var _fish := {}


func setup(owner_game: Game) -> void:
	game = owner_game
	shelf = game.balance.data["shelf"].duplicate(true)
	state["art_scale"] = int(shelf["art_scale"])
	state["columns"] = int(shelf["columns_default"])
	state["rows"] = int(shelf["rows_default"])
	state["taper"] = float(shelf["taper_per_band"])
	_build()


## The islands of a set, each a spec: columns, bands, rows, cuts, pond box, pieces, treatment,
## front corners, seed, label and the view toggles. Every island in a set shares one seed, so
## treatments differ only in outline.
static func islands_for(set_name: String, shelf_config: Dictionary, view: Dictionary) -> Array:
	var widths: Dictionary = shelf_config["widths"]
	var medium := int(widths["medium"])
	var rows := int(shelf_config["rows_default"])
	var treatment := String(view.get("treatment", "A"))
	var presets: Array = shelf_config["pond"]["presets"]
	var out: Array = []
	match set_name:
		"bands":
			for bands in [1, 3, 5]:
				out.append({"columns": medium, "bands": bands})
		"rows":
			for r in [1, 3, 5]:
				out.append({"columns": medium, "bands": 3, "rows": r})
		"widths":
			for w in ["narrow", "medium", "wide"]:
				out.append({"columns": int(widths[w]), "bands": 3})
		"outlines":
			for t in ShelfOutlines.NAMES:
				out.append({"columns": medium, "bands": 3, "treatment": t})
		"corners":
			for cuts in [{"fl": 1}, {"br": 2}, {"fl": 1, "fr": 1, "bl": 1, "br": 1}, {"fl": 2, "fr": 1, "bl": 1, "br": 2}]:
				out.append({"columns": medium, "bands": 3, "cuts": cuts})
		"pond":
			out.append({"columns": medium, "bands": 3, "rows": 3, "pond": presets[1]})
			out.append({"columns": medium, "bands": 5, "rows": 5, "pond": {"c0": 2, "c1": 9, "r1": 5, "w": 5}})
		"pieces":
			out.append({"columns": 20, "bands": 3, "pieces": [5, 5, 5, 5], "cuts": {"fl": 1, "br": 1}})
		"tune":
			var tune := {"columns": int(view.get("columns", medium)), "bands": int(view.get("bands", 3)),
					"rows": int(view.get("rows", rows)), "cuts": view.get("cuts", NO_CUTS),
					"front_corners": [String(view.get("left_corner", "square")), String(view.get("right_corner", "square"))]}
			var preset := int(view.get("pond", -1))
			if preset >= 0:
				tune["pond"] = presets[preset]
			out.append(tune)
	var specs: Array = []
	for o in out:
		var spec := {
			"columns": o["columns"], "bands": o["bands"], "rows": o.get("rows", rows),
			"cuts": NO_CUTS.merged(o.get("cuts", {}), true), "pond": o.get("pond", {}),
			"pieces": o.get("pieces", [o["columns"]]), "treatment": o.get("treatment", treatment),
			"front_corners": o.get("front_corners", ["square", "square"]),
			"seed": int(view.get("seed", 1)),
			"taper": float(view.get("taper", shelf_config["taper_per_band"])),
			"band_tint": bool(view.get("band_tint", true)), "band_lines": bool(view.get("band_lines", true)),
			"grid": bool(view.get("grid", true)), "seams": bool(view.get("seams", true)),
		}
		spec["label"] = label(spec)
		specs.append(spec)
	return specs


static func label(spec: Dictionary) -> String:
	var text := "%d×%d×%d · %s %s" % [spec["columns"], spec["bands"], spec["rows"], spec["treatment"], ShelfOutlines.TITLES[spec["treatment"]]]
	var cut_names: Array = []
	for corner in ShelfGeometry.CORNERS:
		if int(spec["cuts"][corner]) > 0:
			cut_names.append("%s%d" % [corner, spec["cuts"][corner]])
	if not cut_names.is_empty():
		text += " · cut " + " ".join(cut_names)
	if not spec["pond"].is_empty():
		var p: Dictionary = spec["pond"]
		text += " · pond %d×%d×%d" % [int(p["c1"]) - int(p["c0"]), p["r1"], p["w"]]
	if spec["pieces"].size() > 1:
		text += " · pieces %s" % "+".join(spec["pieces"].map(func(n) -> String: return str(n)))
	return text


static func geometry(spec: Dictionary, shelf_config: Dictionary) -> ShelfGeometry:
	return ShelfGeometry.new(int(spec["columns"]), int(spec["bands"]), shelf_config, int(spec["seed"]), {
		"rows": spec["rows"], "cuts": spec["cuts"], "pond": spec["pond"], "pieces": spec["pieces"], "taper": spec["taper"]})


## The island with its birds and avatar (and a fish in any pond), as one image.
static func preview(spec: Dictionary, shelf_config: Dictionary) -> Image:
	var geo := geometry(spec, shelf_config)
	var island := ShelfRenderer.render(geo, shelf_config, spec)
	var sky := int(shelf_config["sky_px"])
	var out := Image.create_empty(island.get_width(), sky + island.get_height(), false, Image.FORMAT_RGBA8)
	out.blend_rect(island, Rect2i(Vector2i.ZERO, island.get_size()), Vector2i(0, sky))
	if not geo.pond.is_empty():
		var p := geo.pond
		var fish_at := Vector2i(geo.voxel_point(int(p["c0"]), 1, int(p["w"])).round()) + Vector2i(0, sky)
		var f := fish_image(geo.fish_px(1))
		out.blend_rect(f, Rect2i(Vector2i.ZERO, f.get_size()), fish_at - f.get_size() / 2)
	for band in range(geo.bands, 0, -1):
		var size := geo.size_px(band)
		var perch := geo.point_at(band, BIRD_U[band - 1])
		if band == 1:
			var figure := AssetLibrary.vec2i(shelf_config["avatar_figure"])
			var feet := Vector2i(geo.point_at(1, 0.5).round()) + Vector2i(0, sky)
			_figure(out, feet, figure)
		if geo.in_top(perch):
			var at := Vector2i(perch.round()) + Vector2i(0, sky)
			out.blend_rect(bird_image(size), Rect2i(0, 0, size, size), at - Vector2i(size / 2, size - 1))
	return out


## A placeholder swimming fish `size` px across, side view: an orange body, a tail, an eye.
static func fish_image(size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var s := float(size)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var body := pow((p.x - s * 0.58) / (s * 0.36), 2) + pow((p.y - s * 0.5) / (s * 0.2), 2) <= 1.0
			var tail := p.x < s * 0.26 and absf(p.y - s * 0.5) < (s * 0.26 - p.x) * 0.9 + 1.0 and p.x > s * 0.04
			if body or tail:
				image.set_pixel(x, y, Color("fb6b1d") if body and p.y < s * 0.52 else Color("f79617"))
	image.set_pixel(roundi(s * 0.78), roundi(s * 0.44), Color("2e222f"))
	return image


static func fish_texture(size: int) -> Texture2D:
	if not _fish.has(size):
		_fish[size] = ImageTexture.create_from_image(fish_image(size))
	return _fish[size]


## A placeholder bird `size` px square, feet at the bottom centre: a round red songbird.
static func bird_image(size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	var s := float(size)
	var red := Color("e83b3b")
	var dark := Color("ae2334")
	var outline := Color("6e2727")
	var body := Vector2(s * 0.45, s * 0.62)
	var head := Vector2(s * 0.66, s * 0.36)
	for y in size:
		for x in size:
			var p := Vector2(x + 0.5, y + 0.5)
			var in_body := pow((p.x - body.x) / (s * 0.3), 2) + pow((p.y - body.y) / (s * 0.2), 2) <= 1.0
			var in_head := p.distance_to(head) <= s * 0.15
			var in_tail := p.x < s * 0.24 and p.x > s * 0.04 and absf(p.y - (s * 0.58 + (s * 0.24 - p.x) * 0.5)) < s * 0.05
			if in_body or in_head or in_tail:
				image.set_pixel(x, y, dark if in_tail or (in_body and p.y > body.y and p.x < body.x) else red)
	var crest := Vector2i(roundi(head.x - s * 0.04), roundi(head.y - s * 0.2))
	for y in range(crest.y, roundi(head.y - s * 0.1)):
		image.set_pixel(clampi(crest.x + (y - crest.y) / 2, 0, size - 1), clampi(y, 0, size - 1), red)
	var beak := Vector2i(roundi(head.x + s * 0.13), roundi(head.y))
	for i in maxi(2, size / 12):
		image.set_pixel(clampi(beak.x + i, 0, size - 1), beak.y, Color("f9c22b"))
		image.set_pixel(clampi(beak.x + i / 2, 0, size - 1), beak.y + 1, Color("f9c22b"))
	image.set_pixel(roundi(head.x + s * 0.04), roundi(head.y - s * 0.03), Color("2e222f"))
	var legs := Color("3e3546")
	for y in range(roundi(body.y + s * 0.18), size):
		image.set_pixel(roundi(body.x - s * 0.06), y, legs)
		image.set_pixel(roundi(body.x + s * 0.06), y, legs)
	var outlined := image.duplicate() as Image
	for y in size:
		for x in size:
			if image.get_pixel(x, y).a > 0.5:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var q: Vector2i = Vector2i(x, y) + d
				if q.x >= 0 and q.y >= 0 and q.x < size and q.y < size and image.get_pixel(q.x, q.y).a > 0.5 and image.get_pixel(q.x, q.y) != legs:
					outlined.set_pixel(x, y, outline)
					break
	return outlined


static func bird_texture(size: int) -> Texture2D:
	if not _birds.has(size):
		_birds[size] = ImageTexture.create_from_image(bird_image(size))
	return _birds[size]


## The avatar's placeholder figure, for previews only (the windows use Avatar's sheet).
static func _figure(out: Image, feet: Vector2i, figure: Vector2i) -> void:
	var left := feet.x - figure.x / 2
	var top := feet.y - figure.y + 1
	var head := figure.x / 2
	out.fill_rect(Rect2i(left + (figure.x - head) / 2, top, head, head), Color("f5a097"))
	out.fill_rect(Rect2i(left + (figure.x - head) / 2, top, head, head / 3), Color("6e4c30"))
	var body_h := int(figure.y * 0.38)
	out.fill_rect(Rect2i(left + figure.x / 6, top + head, figure.x - figure.x / 3, body_h), Color("4d9be6"))
	var leg_top := top + head + body_h
	out.fill_rect(Rect2i(left + figure.x / 4, leg_top, figure.x / 5, feet.y - leg_top + 1), Color("3e3546"))
	out.fill_rect(Rect2i(left + figure.x - figure.x / 4 - figure.x / 5, leg_top, figure.x / 5, feet.y - leg_top + 1), Color("3e3546"))


func _build() -> void:
	for window in windows:
		window.queue_free()
	windows.clear()
	shelf["taper_per_band"] = state["taper"]
	var k := maxi(1, roundi(DisplayServer.screen_get_max_scale()))
	var scale := int(state["art_scale"]) * k
	var input: Dictionary = game.balance.data["input"]
	var display: Dictionary = game.balance.data["display"]
	for spec in islands_for(String(state["set"]), shelf, state):
		var window := ShelfIslandWindow.new()
		window.setup(spec, shelf, scale, float(input["drag_threshold_px"]), float(display["click_shape_epsilon"]), game.idle_fps_max)
		window.spot_clicked.connect(_on_spot_clicked)
		window.pointer.alt_clicked.connect(func(_at: Vector2) -> void: game.call("_open_debug_panel"))
		add_child(window)
		windows.append(window)
	_lay_out(scale)
	for window in windows:
		WindowChrome.draw_on_demand(window)
		window.set_stroll(bool(state["stroll"]))
	print("VibeNature shelf demo: %s" % describe())


## Left to right along the bottom of the screen, bottoms level, wrapping upward.
func _lay_out(scale: int) -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var gap := int(shelf["window_gap_px"]) * scale
	var right := game.get_window().position.x - gap
	var x := usable.position.x + gap
	var bottom := usable.end.y - gap
	var row_height := 0
	for window in windows:
		if x + window.size.x > right and x > usable.position.x + gap:
			x = usable.position.x + gap
			bottom -= row_height + gap
			row_height = 0
		window.position = Vector2i(x, bottom - window.size.y)
		x += window.size.x + gap
		row_height = maxi(row_height, window.size.y)


func _on_spot_clicked(window: ShelfIslandWindow, where: Dictionary) -> void:
	last_click = "%s: column %d, rank %d, u %.2f, %s" % [window.spec["label"], int(where["column"]), int(where["band"]), float(where["u"]), where["size"]]
	print("VibeNature shelf demo: " + last_click)


func describe() -> String:
	var text := "shelf: %s set · taper %.2f · outline %s · ×%d" % [state["set"], state["taper"], state["treatment"], state["art_scale"]]
	if state["set"] == "tune":
		text += "\ntune: " + label(islands_for("tune", shelf, state)[0])
	if last_click != "":
		text += "\nclicked " + last_click
	return text


func show_set(set_name: String) -> void:
	state["set"] = set_name
	_build()


## Applies a tune change and keeps the island legal: cuts shrink and the pond drops out when a
## smaller island can no longer hold them.
func _tune(key: String, value) -> void:
	state[key] = value
	state["set"] = "tune"
	var cuts: Dictionary = state["cuts"]
	for i in 50:
		var why := _tune_problem()
		if why == "":
			break
		if why.contains("pond"):
			state["pond"] = -1
			continue
		for corner in ShelfGeometry.CORNERS:
			if int(cuts[corner]) > 0:
				cuts[corner] = int(cuts[corner]) - 1
				break
	_build()


func _tune_problem() -> String:
	var spec: Dictionary = islands_for("tune", shelf, state)[0]
	return ShelfGeometry.problem(int(spec["columns"]), int(spec["bands"]), int(spec["rows"]), spec["cuts"], spec["pond"], spec["pieces"], shelf)


func step(key: String, by: int, low: int, high: int) -> void:
	_tune(key, clampi(int(state[key]) + by, low, high))


## The next legal cut size at `corner`, wrapping back to no cut.
func cycle_cut(corner: String) -> void:
	var cuts: Dictionary = state["cuts"]
	var start := int(cuts[corner])
	for i in range(1, 7):
		cuts[corner] = (start + i) % 7
		if _tune_problem() == "" or cuts[corner] == 0:
			break
	_tune("cuts", cuts)


func cycle_pond() -> void:
	var presets: Array = shelf["pond"]["presets"]
	var next := int(state["pond"])
	for i in presets.size() + 1:
		next = next + 1 if next + 1 < presets.size() else -1
		state["pond"] = next
		if next == -1 or _tune_problem() == "":
			break
	_tune("pond", next)


## The next front-corner decoration (square, round, slice) on `side`: "left_corner" or "right_corner".
func cycle_corner(side: String) -> void:
	var shapes := ShelfOutlines.FRONT_CORNERS
	_tune(side, shapes[(shapes.find(String(state[side])) + 1) % shapes.size()])


func step_taper(by: float) -> void:
	state["taper"] = clampf(snappedf(float(state["taper"]) + by, 0.01), 0.75, 1.0)
	_build()


func set_treatment(name: String) -> void:
	state["treatment"] = name
	_build()


func toggle(key: String) -> void:
	state[key] = not bool(state[key])
	if key == "stroll":
		for window in windows:
			window.set_stroll(bool(state["stroll"]))
		return
	_build()


func set_art_scale(scale: int) -> void:
	state["art_scale"] = scale
	_build()


func regenerate() -> void:
	state["seed"] = int(state["seed"]) + 1
	_build()


## The debug panel's "Shelf demo" sections: [heading, [[label, callable], ...]].
func debug_sections() -> Array:
	var sets: Array = []
	for set_name in SETS:
		sets.append([String(set_name).capitalize(), show_set.bind(set_name)])
	var outlines: Array = []
	for name in ShelfOutlines.NAMES:
		outlines.append(["%s · %s" % [name, ShelfOutlines.TITLES[name]], set_treatment.bind(name)])
	var max_columns := int(shelf["piece_max_columns"])
	return [
		["Shelf demo · sets", sets],
		["Shelf demo · tune (one island)", [
			["Columns −", step.bind("columns", -1, int(shelf["columns_min"]), max_columns)],
			["Columns +", step.bind("columns", 1, int(shelf["columns_min"]), max_columns)],
			["Ranks −", step.bind("bands", -1, 1, 5)], ["Ranks +", step.bind("bands", 1, 1, 5)],
			["Rows −", step.bind("rows", -1, 1, 5)], ["Rows +", step.bind("rows", 1, 1, 5)],
			["Cut FL", cycle_cut.bind("fl")], ["Cut FR", cycle_cut.bind("fr")],
			["Cut BL", cycle_cut.bind("bl")], ["Cut BR", cycle_cut.bind("br")],
			["Pond", cycle_pond],
			["Round/slice left", cycle_corner.bind("left_corner")], ["Round/slice right", cycle_corner.bind("right_corner")],
		]],
		["Shelf demo · every island", [
			["Taper −", step_taper.bind(-0.01)], ["Taper +", step_taper.bind(0.01)],
			["Regenerate", regenerate],
		]],
		["Shelf demo · outline", outlines],
		["Shelf demo · view", [
			["Band tint", toggle.bind("band_tint")], ["Band lines", toggle.bind("band_lines")],
			["Grid", toggle.bind("grid")], ["Seams", toggle.bind("seams")],
			["Avatar strolls", toggle.bind("stroll")], ["×1", set_art_scale.bind(1)], ["×2", set_art_scale.bind(2)],
		]],
	]
