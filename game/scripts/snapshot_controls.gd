class_name SnapshotControls
extends RefCounted

## Stills of the scene's controls (Skypatch issue 169),
## off screen: the scene at each of its sizes (issue 222: 50…100%), with the tab closed and with
## the strip open (a hover on the book), each laid over a plain desktop, a 1:1 crop of the corner,
## crops of the avatar's face and a tree edge, and each Config tab. `game/tools/snap.sh <godot> <out> controls`.

const PRESET := "calm"
const DESKTOP := "4a5a6a"
const DESKTOP_LIGHT := "eef2f6"
## Where the size stills crop (points): the avatar's face from the seat, and a tree crown's edge
## against the sky.
const FACE_FROM_SEAT_PT := Vector2(0, -52)
const TREE_EDGE_PT := Vector2(200, 60)

var s: Snapshot
var game: Game
var _scene_shots: SnapshotScene


func _init(owner: Snapshot) -> void:
	s = owner
	game = owner.game
	_scene_shots = SnapshotScene.new(owner)


func run() -> void:
	Pace.start_moving()
	s._expect(game.scene.controls != null, "scene mode has the control strip")
	var steps: Array = game.balance.data["display"]["scene_sizes"]
	for step in steps:
		await _size_step(int(step), steps)
	for step in steps:
		game.set_scene_size(int(step))
		await _ready_scene()
		await _mouse_clear("mouse_clear_%d" % int(step))
	game.set_scene_size(100)
	await _ready_scene()
	await _mouse_clear_sizes()
	for tab in SceneConfigWindow.TAB_NAMES.size():
		game.scene_config.open(tab)
		await game.get_tree().process_frame
		await game.get_tree().process_frame
		_save(game.scene_config, "config_%d_%s" % [tab + 1, SceneConfigWindow.TAB_NAMES[tab].to_lower()])
	game.scene_config.close_config()
	await _pickers()
	Pace.stop_moving()


## One scene size (issue 222): the scene with the tab closed and with the strip open (a hover on the
## book), and 1:1 crops of the avatar's face and a tree edge against the sky, to judge the softness
## of the in-between sizes.
func _size_step(percent: int, steps: Array) -> void:
	game.set_scene_size(percent)
	await _ready_scene()
	var scene := game.scene
	var tag := "size_%d" % percent
	s._expect(game.scene_percent() == percent, "%s: the scene is at %d%%" % [tag, percent])
	var full := Game.scene_point_scale(true, 2.0)
	s._expect(is_equal_approx(scene.scale_px, full * percent / 100.0), "%s: %.2f units per point" % [tag, scene.scale_px])
	var exact: Array = game.balance.data["display"]["scene_sizes_exact"]
	var sharp := not (exact.has(float(percent)) or exact.has(percent))
	s._expect((scene.shrink != null) == sharp, "%s: %s" % [tag, "drawn at full and shrunk smoothly" if sharp else "drawn nearest at its own scale"])
	var controls := scene.controls
	s._expect(controls.is_disabled("zoom_out") == (percent == int(steps[0])) and controls.is_disabled("zoom_in") == (percent == int(steps[-1])),
			"%s: a magnifier is greyed out only at its end" % tag)
	controls.close_now()
	s._expect(not controls.is_open and not scene.mouse_passthrough, "%s: closed, only the tab takes the mouse" % tag)
	await _shot("%s_tab_closed" % tag)
	controls.open_now(true)
	controls.hovered = "book"
	controls.queue_redraw()
	await _shot("%s_strip_open" % tag)
	await _crops(tag)


## 1:1 crops round the avatar's face and round a tree edge (`TREE_EDGE_PT`, in points), at the
## window's own pixels, over the plain desktop.
func _crops(tag: String) -> void:
	await game.get_tree().process_frame
	var image := _grab(game.scene)
	if image == null:
		return
	var scene := game.scene
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	var desktop := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	desktop.fill(Color(DESKTOP))
	desktop.blend_rect(image, bounds, Vector2i.ZERO)
	var face := Vector2i(((scene.sitter.seat + FACE_FROM_SEAT_PT) * scene.scale_px).round())
	desktop.get_region(Rect2i(face - Vector2i(80, 80), Vector2i(160, 160)).intersection(bounds)).save_png(s.out_dir.path_join("%s__face_1x.png" % tag))
	var edge := Vector2i((TREE_EDGE_PT * scene.scale_px).round())
	desktop.get_region(Rect2i(edge - Vector2i(160, 100), Vector2i(320, 200)).intersection(bounds)).save_png(s.out_dir.path_join("%s__tree_edge_1x.png" % tag))
	s.steps.append({"step": "%s_crops" % tag, "windows": ["scene"], "files": ["%s__face_1x.png" % tag, "%s__tree_edge_1x.png" % tag], "checks": []})


## Mouse clear (issue 428), with a faked cursor: on top with the cursor in the middle of the art, the
## hole's centre is see-through and its rim ramps smoothly back to the scene; over the strip the strip
## draws unchanged; behind, no hole. Saves the hole over a dark and a light desktop and a 1:1 crop of
## its feathered edge.
func _mouse_clear(tag: String) -> void:
	var scene := game.scene
	var clear := scene.mouse_clear
	s._expect(clear != null, "%s: scene mode has mouse clear" % tag)
	if clear == null:
		return
	var card := scene.letter_card
	if card != null and card.catches():
		var r := card.card_rect()
		var drawn := Rect2(r.position * card.ui_scale, r.size * card.ui_scale)
		var region: Variant = scene.hit.regions.get(SceneLetterCard.REGION)
		s._expect(region is Rect2 and (region as Rect2).is_equal_approx(drawn),
				"%s: the letter card's region is the drawn card (%s, drawn %s, issue 465)" % [tag, region, drawn])
	var plain := _grab(scene)
	var cursor: Array = [null]
	clear.cursor_source = func() -> Variant: return cursor[0]
	var middle := _hole_spot(scene)
	cursor[0] = Vector2(scene.position) + middle
	game.set_all_on_top(true)
	clear.poll()
	await game.get_tree().process_frame
	s._expect(clear.inside and clear.draws > 0, "%s: on top, the cursor in the middle: the hole is shown (%d draws)" % [tag, clear.draws])
	var holed := _grab(scene)
	if plain != null and holed != null:
		var c := Vector2i(middle)
		var r := clear.radius()
		s._expect(holed.get_pixelv(c).a < 0.004 and plain.get_pixelv(c).a > 0.99,
				"%s: the hole's centre is see-through (alpha %.3f over %.3f)" % [tag, holed.get_pixelv(c).a, plain.get_pixelv(c).a])
		var ramp: Array = []
		var smooth := true
		var last := -1.0
		for i in int(ceil(r)) + 3:
			var at := c + Vector2i(i, 0)
			var base := plain.get_pixelv(at).a
			var keep := holed.get_pixelv(at).a / base if base > 0.01 else 1.0
			ramp.append(snappedf(keep, 0.01))
			if keep < last - 0.02 or (last >= 0.0 and keep - last > 0.25):
				smooth = false
			last = keep
		s._expect(smooth and ramp[0] < 0.01 and ramp[-1] > 0.98, "%s: the rim ramps smoothly from see-through to the scene (%s)" % [tag, ramp])
		var fringe := 0.0
		for i in int(ceil(r)):
			var p := holed.get_pixelv(c + Vector2i(i, 0))
			fringe = maxf(fringe, maxf(p.r, maxf(p.g, p.b)) - p.a)
		s._expect(fringe < 0.02, "%s: colour is cut with alpha, no fringe (%.3f)" % [tag, fringe])
		_mouse_clear_stills(tag, holed, c, r)
	var strip := scene.controls.hit_rect()
	var kept := _kept_px(strip)
	var drawn := _strip_px(scene.controls)
	s._expect(kept.encloses(drawn), "%s: every pixel the strip draws (%s) is kept out of the hole (%s)" % [tag, drawn, kept])
	cursor[0] = Vector2(scene.position) + strip.get_center()
	clear.poll()
	await game.get_tree().process_frame
	var on_strip := _grab(scene)
	if plain != null and on_strip != null:
		s._expect(on_strip.get_region(kept).get_data() == plain.get_region(kept).get_data(), "%s: over the strip, the strip draws unchanged" % tag)
	cursor[0] = Vector2(scene.position) + middle
	clear.poll()
	await game.get_tree().process_frame
	game.set_all_on_top(false)
	var behind := _grab(scene)
	s._expect(not clear.inside and not clear.is_processing(), "%s: on top off: no hole, no polling" % tag)
	if plain != null and behind != null:
		s._expect(behind.get_pixelv(Vector2i(middle)).a > 0.99, "%s: on top off: the middle is the scene again" % tag)
	clear.cursor_source = func() -> Variant: return null


## The window pixels the hole keeps for a hit rect (window units): those whose centres lie inside it, the
## shader's own test. Between the exact sizes the strip's top inset is fractional (79.2 at 70%), so the whole
## pixels inside are not `ceil(position)` plus `floor(size)`: that box ends a row below the rect, on the scene
## under the hole (issue 464).
static func _kept_px(rect: Rect2) -> Rect2i:
	var from := Vector2i((rect.position - Vector2(0.5, 0.5)).ceil())
	var to := Vector2i((rect.end - Vector2(0.5, 0.5)).ceil())
	return Rect2i(from, to - from)


## The pixels the open strip draws: each button's frame at its point rect, snapped to whole device px as
## `SceneControls._frame` draws it.
static func _strip_px(controls: SceneControls) -> Rect2i:
	var out := Rect2i()
	for id in SceneControls.IDS:
		var r := controls.button_rect(id)
		var px := Rect2i(Vector2i((r.position * controls.ui_scale).round()), Vector2i((r.size * controls.ui_scale).round()))
		out = px if out.size == Vector2i.ZERO else out.merge(px)
	return out


func _mouse_clear_stills(tag: String, render: Image, c: Vector2i, r: float) -> void:
	var image := render.duplicate() as Image
	var bounds := Rect2i(Vector2i.ZERO, image.get_size())
	# The window's render is premultiplied and `blend_rect` blends straight alpha: unpremultiply the hole
	# so the stills show it as the screen will (elsewhere the scene's art is opaque).
	var box := Rect2i(c - Vector2i(int(r) + 2, int(r) + 2), Vector2i(int(r) * 2 + 4, int(r) * 2 + 4)).intersection(bounds)
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and p.a < 1.0:
				image.set_pixel(x, y, Color(minf(1.0, p.r / p.a), minf(1.0, p.g / p.a), minf(1.0, p.b / p.a), p.a))
	var files: Array = []
	for desk in [["dark", DESKTOP], ["light", DESKTOP_LIGHT]]:
		var desktop := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
		desktop.fill(Color(desk[1]))
		desktop.blend_rect(image, bounds, Vector2i.ZERO)
		var file := "%s__%s.png" % [tag, desk[0]]
		desktop.save_png(s.out_dir.path_join(file))
		files.append(file)
		var edge := Rect2i(c + Vector2i(int(r) - 60, -60), Vector2i(120, 120)).intersection(bounds)
		file = "%s__edge_%s_1x.png" % [tag, desk[0]]
		desktop.get_region(edge).save_png(s.out_dir.path_join(file))
		files.append(file)
	s.steps.append({"step": tag, "windows": ["scene"], "files": files, "checks": []})
	print("VibeNature snapshot: %s" % tag)


## Mouse clear's four sizes (issue 438), chosen as Config does: each over a light desktop at 1:1 side by side in
## one contact sheet, each checked see-through in the middle and opaque just past its rim, each with the strip
## drawn unchanged under a hole that overlaps it; and the frame's cost with no hole and with each.
func _mouse_clear_sizes() -> void:
	var scene := game.scene
	var clear := scene.mouse_clear
	if clear == null:
		return
	var sizes: Array = clear.tuning["diameters_pt"]
	s._expect(game.mouse_clear_pt() == int(clear.tuning["diameter_pt"]) and is_equal_approx(clear.size_pt(), 360.0),
			"mouse clear: the default is 360 points across (%d)" % clear.size_pt())
	var plain := _grab(scene)
	var cursor: Array = [null]
	clear.cursor_source = func() -> Variant: return cursor[0]
	game.set_all_on_top(true)
	var timing := ["none %s" % await _frame_cost(scene)]
	var tiles: Array[Image] = []
	for points in sizes:
		game.set_mouse_clear_size(int(points))
		s._expect(is_equal_approx(clear.size_pt(), float(points)) and int(game.settings.data["mouse_clear_size"]) == int(points),
				"mouse clear %d: chosen and saved" % points)
		var middle := _hole_spot(scene)
		cursor[0] = Vector2(scene.position) + middle
		clear.poll()
		await game.get_tree().process_frame
		var holed := _grab(scene)
		timing.append("%d %s" % [points, await _frame_cost(scene)])
		if plain == null or holed == null:
			continue
		var c := Vector2i(middle)
		var r := clear.radius()
		var past := c + Vector2i(int(ceil(r)) + 2, 0)
		s._expect(holed.get_pixelv(c).a < 0.004 and holed.get_pixelv(past).a > 0.99 * plain.get_pixelv(past).a,
				"mouse clear %d: see-through in the middle, the scene just past the rim (%.3f, %.3f)" % [points, holed.get_pixelv(c).a, holed.get_pixelv(past).a])
		var tile := _unpremultiplied(holed, c, r)
		var box := Rect2i(c - Vector2i(int(r) + 24, int(r) + 24), Vector2i(int(r) * 2 + 48, int(r) * 2 + 48)).intersection(Rect2i(Vector2i.ZERO, tile.get_size()))
		var desk := Image.create_empty(box.size.x, box.size.y, false, Image.FORMAT_RGBA8)
		desk.fill(Color(DESKTOP_LIGHT))
		desk.blend_rect(tile, box, Vector2i.ZERO)
		tiles.append(desk)
		var strip := scene.controls.hit_rect()
		cursor[0] = Vector2(scene.position) + strip.get_center() + Vector2(0, strip.size.y / 2.0 + 10.0)
		clear.poll()
		await game.get_tree().process_frame
		var near_strip := _grab(scene)
		if near_strip != null:
			var rect := _kept_px(strip)
			s._expect(near_strip.get_region(rect).get_data() == plain.get_region(rect).get_data(),
					"mouse clear %d: a hole over the strip leaves the strip drawn unchanged" % points)
	if not tiles.is_empty():
		var gap := 16
		var w := gap
		var h := 0
		for t in tiles:
			w += t.get_width() + gap
			h = maxi(h, t.get_height())
		var sheet := Image.create_empty(w, h + gap * 2, false, Image.FORMAT_RGBA8)
		sheet.fill(Color(DESKTOP_LIGHT))
		var x := gap
		for t in tiles:
			sheet.blit_rect(t, Rect2i(Vector2i.ZERO, t.get_size()), Vector2i(x, gap + (h - t.get_height()) / 2))
			x += t.get_width() + gap
		sheet.save_png(s.out_dir.path_join("mouse_clear_sizes__light_1x.png"))
		s.steps.append({"step": "mouse_clear_sizes", "windows": ["scene"], "files": ["mouse_clear_sizes__light_1x.png"], "checks": []})
	print("VibeNature snapshot: mouse clear frame cost (ms per frame: wall, waiting for the GPU / viewports CPU): %s" % ", ".join(timing))
	game.set_all_on_top(false)
	game.set_mouse_clear_size(int(clear.tuning["diameter_pt"]))
	clear.cursor_source = func() -> Variant: return null


## Where to put the cursor to test the hole: in the art, its whole reach clear of every hit region (the letter
## card can cover the very middle) if there is such a place; else (a large hole) one where the centre and the line
## to the rim on the right are clear and inside the window, so the ramp is measured where nothing is kept.
func _hole_spot(scene: LivingScene) -> Vector2:
	var regions: Array = scene.mouse_clear._hit.regions.values()
	var r := scene.mouse_clear.radius()
	var shares: Array[Vector2] = [Vector2(0.5, 0.5), Vector2(0.66, 0.6), Vector2(0.4, 0.75), Vector2(0.8, 0.7)]
	# 0.92: at 50% the letter card covers the middle down to about nine tenths of the window, and the hole
	# (twice the window's height) fits nowhere whole; the ramp is measured along the ground below the card.
	for y in [0.55, 0.65, 0.75, 0.85, 0.92]:
		for x in [0.3, 0.4, 0.5, 0.6]:
			shares.append(Vector2(x, y))
	for whole in [true, false]:
		for share in shares:
			var at := (Vector2(scene.size) * share).round()
			var reach := Rect2(at, Vector2.ZERO).grow(r + 2.0) if whole else Rect2(at, Vector2(r + 4.0, 1.0))
			if reach.end.x >= scene.size.x:
				continue
			if not regions.any(func(k: Rect2) -> bool: return k.intersects(reach)):
				return at
	return (Vector2(scene.size) / 2.0).round()


## The mean wall time of drawing a whole frame (the scene redrawn, the hole too when shown, waiting for the GPU)
## and the viewports' measured CPU time, over 60 frames after 10 to warm up (GPU timestamps read 0 off screen).
func _frame_cost(scene: LivingScene) -> String:
	await game.get_tree().process_frame
	var rids := [scene.get_viewport_rid(), game.get_tree().root.get_viewport_rid()]
	for rid in rids:
		RenderingServer.viewport_set_measure_render_time(rid, true)
	var wall := 0.0
	var cpu := 0.0
	for i in 70:
		if scene.mouse_clear != null and scene.mouse_clear.inside:
			scene.mouse_clear._hole.queue_redraw()
		WindowChrome.redraw(scene)
		var t0 := Time.get_ticks_usec()
		RenderingServer.force_draw(true)
		RenderingServer.force_sync()
		if i >= 10:
			wall += float(Time.get_ticks_usec() - t0) / 1000.0
			for rid in rids:
				cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	for rid in rids:
		RenderingServer.viewport_set_measure_render_time(rid, false)
	return "%.2f/%.2f" % [wall / 60.0, cpu / 60.0]


func _unpremultiplied(render: Image, c: Vector2i, r: float) -> Image:
	var image := render.duplicate() as Image
	var box := Rect2i(c - Vector2i(int(r) + 2, int(r) + 2), Vector2i(int(r) * 2 + 4, int(r) * 2 + 4)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var p := image.get_pixel(x, y)
			if p.a > 0.0 and p.a < 1.0:
				image.set_pixel(x, y, Color(minf(1.0, p.r / p.a), minf(1.0, p.g / p.a), minf(1.0, p.b / p.a), p.a))
	return image


## The screen picker (issue 174) with faked screens: two (a laptop and a big screen to its right,
## hovering the big one, then picked) and three (one to the left and one above the laptop).
func _pickers() -> void:
	var real := game.screens_source
	var laptop := {"rect": Rect2i(0, 0, 1512, 982), "usable": Rect2i(0, 38, 1512, 874), "primary": true, "scale": 2.0}
	var big := {"rect": Rect2i(1512, -458, 2560, 1440), "usable": Rect2i(1512, -433, 2560, 1415), "primary": false, "scale": 2.0}
	var left := {"rect": Rect2i(-1920, -98, 1920, 1080), "usable": Rect2i(-1920, -73, 1920, 1055), "primary": false, "scale": 1.0}
	var above := {"rect": Rect2i(-200, -1440, 2560, 1440), "usable": Rect2i(-200, -1415, 2560, 1415), "primary": false, "scale": 2.0}
	for setup in [["two", [laptop, big], 0, 1], ["three", [left, laptop, above], 1, 2]]:
		var screens: Array = setup[1]
		game.screens_source = func() -> Array: return screens
		game.move_scene_to_screen(int(setup[2]))
		game.scene_config.open(SceneConfigWindow.GENERAL)
		var picker := game.scene_config.screen_picker
		await game.get_tree().process_frame
		picker._hover(int(setup[3]))
		await game.get_tree().process_frame
		s._expect(picker.selected == int(setup[2]), "%s screens: the scene's screen is selected" % setup[0])
		_save(game.scene_config, "picker_%s_hover" % setup[0])
		picker.pick(int(setup[3]))
		picker._hover(-1)
		await game.get_tree().process_frame
		s._expect(game.scene.position + game.scene.size == Rect2i(screens[int(setup[3])]["usable"]).end,
				"%s screens: picking one moves the scene to its corner" % setup[0])
		_save(game.scene_config, "picker_%s_picked" % setup[0])
		game.scene_config.close_config()
	game.screens_source = real
	game.settings.data["scene_screen"] = {}
	game.settings.save()


## The scene in each bottom corner (issue 422), flush and at the largest lift: the corner of a desktop with
## the scene in it, over a dark and a light desktop, and 1:1 crops of the dissolving side edge (the left in
## the bottom-right, the right in the bottom-left) at its top and its middle. `snap.sh <godot> <out> corner`.
## Every corner, as made and mirrored (issue 424): the two edges against the screen straight and flush, the
## two open ones dissolving. Each saved transparent (`corner_<corner>_<made|mirrored>.png`) for
## `game/tools/corner_sheet.py`, which lays them over dark and light desktops with 1:1 crops of the edges.
## Also the lift: a bottom corner rises, a top one stays flush under the menu bar.
func run_corners() -> void:
	Pace.start_moving()
	game.set_scene_lift(0)
	game.set_scene_corner("bottom_right")
	game.set_scene_mirror(false)
	await _ready_scene()
	for corner in SceneScreens.CORNERS:
		for mirror in [false, true]:
			game.set_scene_corner(corner)
			game.set_scene_mirror(mirror)
			await game.get_tree().process_frame
			var scene := game.scene
			var tag := "corner_%s_%s" % [corner, "mirrored" if mirror else "made"]
			var left := SceneScreens.is_left(corner)
			var top := SceneScreens.is_top(corner)
			s._expect(scene.corner == corner and scene.mirrored == mirror and scene.controls.left == left, "%s: in its corner, %s" % [tag, "mirrored" if mirror else "as made"])
			var usable := game.scene_usable()
			s._expect(scene.position.x == (usable.position.x if left else usable.end.x - scene.size.x), "%s: flush to the screen's side" % tag)
			s._expect(scene.position.y == (usable.position.y if top else usable.end.y - scene.size.y), "%s: flush to the screen's %s" % [tag, "top" if top else "bottom"])
			s._expect(scene.size == Vector2i((scene.view_pt.size * scene.scale_px).round()), "%s: the window is the view (%s)" % [tag, scene.view_pt])
			var flush_lt := (scene.view_pt.position.x > 0.0) == (scene.world_left_flush() and scene.frame_pt.position.x > 0.0)
			s._expect(flush_lt and (scene.view_pt.position.y > 0.0) == top, "%s: a flush side shows the frame's edge, an open one its margin" % tag)
			var strip := scene.controls.strip_rect()
			var art_top := (scene.frame_pt.position.y - scene.view_pt.position.y) * scene.scale_px / scene.controls.ui_scale
			s._expect(strip.position.y >= art_top - 0.5, "%s: the strip sits on the art (%.1f below its top %.1f)" % [tag, strip.position.y, art_top])
			scene.controls.close_now()
			await game.get_tree().process_frame
			await game.get_tree().process_frame
			var image := _grab(scene)
			if image == null:
				continue
			image.save_png(s.out_dir.path_join(tag + ".png"))
			s.steps.append({"step": tag, "windows": ["scene"], "files": [tag + ".png"], "checks": []})
			print("VibeNature snapshot: %s" % tag)
	var lifts: Array = game.balance.data["display"]["scene_lifts_pt"]
	game.set_scene_mirror(false)
	game.set_scene_lift(int(lifts[-1]))
	for corner in ["bottom_left", "top_right"]:
		game.set_scene_corner(corner)
		var usable := game.scene_usable()
		var top := SceneScreens.is_top(corner)
		var want := usable.position.y if top else usable.end.y - game.scene.size.y - game.scene_lift_units()
		s._expect(game.scene.position.y == want, "%s: %s" % [corner, "flush under the menu bar, never lifted" if top else "lifted %d pt" % int(lifts[-1])])
	game.set_scene_lift(0)
	game.set_scene_corner("bottom_right")
	Pace.stop_moving()


## The rain's cloud line (issue 477): the scene in a bottom and a top corner at four moments of a shower,
## each the weather's phase held with its cloud and rain set, played a few seconds so the drops are falling.
## `rain_corner_<corner>_<moment>.png`; `game/tools/rain_sheet.py` lays them out with 1:1 crops.
const RAIN_MOMENTS := [
	{"name": "before", "phase": "rain", "cloud": 0.6, "rain": 0.0},
	{"name": "light", "phase": "rain", "cloud": 0.8, "rain": 0.3},
	{"name": "heavy", "phase": "rain", "cloud": 1.0, "rain": 1.0},
	{"name": "clearing", "phase": "clearing", "cloud": 0.62, "rain": 0.08},
]


func run_rain_corners() -> void:
	Pace.start_moving()
	game.set_scene_lift(0)
	game.set_scene_mirror(false)
	var scene := game.scene
	SnapshotScene.apply(scene, _scene_shots.clips["presets"]["rain"], _scene_shots.clips)
	scene.set_random_visits(false)
	for corner in ["bottom_right", "top_left"]:
		game.set_scene_corner(corner)
		for m in RAIN_MOMENTS:
			# The sky is the subject: a letter he happens to be reading is closed.
			if scene.letter_card != null:
				scene.letter_card.dismiss()
			scene.env.force_weather(String(m["phase"]))
			scene.env.weather.cloud = float(m["cloud"])
			scene.env.weather.rain = float(m["rain"])
			for i in 90:
				scene.advance(1.0 / 30.0, scene.minute)
				if i % 10 == 9:
					await game.get_tree().process_frame
			scene.controls.close_now()
			if scene.letter_card != null:
				scene.letter_card.visible = false
			await game.get_tree().process_frame
			await game.get_tree().process_frame
			var tag := "rain_corner_%s_%s" % [corner, String(m["name"])]
			var under := scene.rain.top_at(scene.size_pt.x * 0.5)
			s._expect(float(m["rain"]) <= 0.0 or (under >= scene.frame_pt.position.y and under < scene.rain.floor_y()),
					"%s: the rain comes out of the cloud line, inside the frame (%.1f pt)" % [tag, under])
			var image := _grab(scene)
			if image == null:
				continue
			image.save_png(s.out_dir.path_join(tag + ".png"))
			s.steps.append({"step": tag, "windows": ["scene"], "files": [tag + ".png"], "checks": []})
			print("VibeNature snapshot: %s" % tag)
	game.set_scene_corner("bottom_right")
	Pace.stop_moving()


func _ready_scene() -> void:
	var scene := game.scene
	SnapshotScene.apply(scene, _scene_shots.clips["presets"][PRESET], _scene_shots.clips)
	scene.set_random_visits(false)
	await _scene_shots.play(scene, PRESET, 2.0)
	await game.get_tree().process_frame


## The scene over a plain desktop, and a 1:1 crop of its top-right corner.
func _shot(step: String) -> void:
	# The strip draws itself on the next frame.
	await game.get_tree().process_frame
	var scene := game.scene
	var image := _grab(scene)
	if image == null:
		return
	var desktop := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	desktop.fill(Color(DESKTOP))
	desktop.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	desktop.save_png(s.out_dir.path_join("%s__scene.png" % step))
	var crop_size := Vector2i(mini(640, desktop.get_width()), mini(200, desktop.get_height()))
	var crop := desktop.get_region(Rect2i(Vector2i(desktop.get_width() - crop_size.x, 0), crop_size))
	crop.save_png(s.out_dir.path_join("%s__corner.png" % step))
	# The corner is mostly dissolving sky over the desktop: also over a bright desktop.
	var light := Image.create_empty(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	light.fill(Color(DESKTOP_LIGHT))
	light.blend_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	light.get_region(Rect2i(Vector2i(light.get_width() - crop_size.x, 0), crop_size)).save_png(s.out_dir.path_join("%s__corner_light.png" % step))
	s.steps.append({"step": step, "windows": ["scene"], "files": ["%s__scene.png" % step, "%s__corner.png" % step], "checks": []})
	print("VibeNature snapshot: %s" % step)


func _save(window: Window, step: String) -> void:
	var image := _grab(window)
	if image == null:
		return
	image.save_png(s.out_dir.path_join("%s.png" % step))
	s.steps.append({"step": step, "windows": [window.title], "files": ["%s.png" % step], "checks": []})
	print("VibeNature snapshot: %s" % step)


func _grab(window: Window) -> Image:
	if DisplayServer.get_name() == "headless":
		return null
	WindowChrome.redraw(window)
	RenderingServer.force_draw(false)
	var image: Image = window.get_texture().get_image()
	if image == null or image.is_empty():
		s._expect(false, "the %s window rendered" % window.title)
		return null
	image.convert(Image.FORMAT_RGBA8)
	return image
