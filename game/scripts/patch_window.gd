class_name PatchWindow
extends Window

## One patch in its own native window: sky on top, island in the middle, and the island's
## row just below its bottom edge, overlapping it a little: the tool squares right-aligned,
## the ✕ (dismiss) square at the left. Draw order is base, then
## creatures by layer (back, mid, front) in y order, then the front overlay, then the
## overlay layer (mini-games). Everything inside is in art pixels under one integer scale,
## which can change while the window is open (the island the avatar is on grows).

signal clicked(patch: PatchWindow, button: int, art_point: Vector2)
## The player dragged this island somewhere: it stays there, even over another.
signal moved_by_player(patch: PatchWindow)

## The tool squares take clicks this far above themselves too.
const ROW_REACH_PX := 8

var def: PatchDef
var sky_px: int
var scale_px: int
var mechanic: PatchMechanic
var pointer: PointerHandler
var tools: Array = []
var default_tool := ""
## The player put this island where it is (a drag); the game never moves it then.
var placed_by_player := false
var _art := Node2D.new()
var _layers := {}
var _overlay := Node2D.new()
var _click_shape := PackedVector2Array()
var _capturing := false
var _click_epsilon := 1.0
var _opaque: Image
var _row: Dictionary = {}
var _icons := {}
var _square := 0
var _squares := {}
var _close := Rect2()
var _selected := ""
var _highlight := ColorRect.new()


func setup(patch: PatchDef, sky: int, scale: int, click_epsilon: float, drag_threshold_px: float,
		patch_tools: Array = [], patch_default_tool: String = "", icon_for: Callable = Callable(), tool_row: Dictionary = {}) -> void:
	def = patch
	sky_px = sky
	scale_px = scale
	_click_epsilon = click_epsilon
	tools = patch_tools
	default_tool = patch_default_tool
	_row = tool_row
	_load_tool_icons(icon_for)
	title = "VibeNature · %s" % def.id
	WindowChrome.configure(self, art_size() * scale_px)
	_art.scale = Vector2(scale_px, scale_px)
	add_child(_art)
	_art.add_child(_island_sprite(def.base))
	for layer in PatchDef.LAYERS:
		var node := Node2D.new()
		node.name = layer
		node.y_sort_enabled = true
		_art.add_child(node)
		_layers[layer] = node
	if def.front != null:
		_art.add_child(_island_sprite(def.front))
	_art.add_child(_overlay)
	_build_tool_row()
	_opaque = _click_image()
	_click_shape = WindowChrome.set_click_shape(self, _opaque, Vector2i.ZERO, scale_px, _click_epsilon)
	pointer = PointerHandler.new(self, drag_threshold_px)
	pointer.clicked.connect(func(button: int, at: Vector2) -> void: clicked.emit(self, button, at / scale_px))
	pointer.dragged.connect(func() -> void:
		placed_by_player = true
		moved_by_player.emit(self))


func attach_mechanic(patch_mechanic: PatchMechanic) -> void:
	mechanic = patch_mechanic
	add_child(mechanic)


func _island_sprite(texture: Texture2D) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(0, sky_px)
	return sprite


func _row_height() -> int:
	if _row.is_empty():
		return 0
	return maxi(0, _square + int(_row["below_px"]) - int(_row["overlap_px"]) - int(_row.get("raise_px", 0)))


func art_size() -> Vector2i:
	return Vector2i(def.size.x, def.size.y + sky_px + _row_height())


## Each tool's icon, and the square size that holds the largest of them: `square_px` at
## least, or `square_per_icon` times the icon, so a 32 px icon (proposal 0007) sits in a
## 40 px square while an island of 16 px icons keeps its 20 px squares.
func _load_tool_icons(icon_for: Callable) -> void:
	_icons.clear()
	_square = 0
	if _row.is_empty():
		return
	_square = int(_row["square_px"])
	var per_icon := float(_row.get("square_per_icon", 1.0))
	for tool_id in tools:
		if not icon_for.is_valid():
			continue
		var texture: Texture2D = icon_for.call(String(tool_id))
		if texture == null:
			continue
		_icons[String(tool_id)] = texture
		_square = maxi(_square, ceili(maxi(texture.get_width(), texture.get_height()) * per_icon))
	if _row.has("square_fixed_px"):
		_square = int(_row["square_fixed_px"])


## The row from the human's mockup (a private design note):
## light green tiles with a darker border, each holding a tool's icon, right-aligned at the
## island art's full right edge; a red ✕ tile of the same size at its full left edge (issue 66).
## Their tops overlap the island, tucked up by `raise_px`.
func _build_tool_row() -> void:
	if _row.is_empty():
		return
	var square := _square
	var gap := int(_row["gap_px"])
	var tools_w := tools.size() * square + maxi(0, tools.size() - 1) * gap
	var y := sky_px + def.size.y - int(_row["overlap_px"]) - int(_row.get("raise_px", 0))
	var x := def.size.x - int(_row["margin_right_px"]) - tools_w
	_highlight.color = Color("fbff86")
	_highlight.size = Vector2(square + 2, square + 2)
	_highlight.visible = false
	_highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.add_child(_highlight)
	for tool_id in tools:
		_art.add_child(_tile(Rect2(x, y, square, square), Color(String(_row["tile_color"])), Color(String(_row["border_color"]))))
		if _icons.has(String(tool_id)):
			var icon := Sprite2D.new()
			icon.name = "icon_" + String(tool_id)
			icon.texture = _icons[String(tool_id)]
			icon.centered = false
			var fill := float(_row.get("icon_fill", 0.8)) * square
			var zoom := maxi(1, floori(fill / maxi(icon.texture.get_width(), icon.texture.get_height())))
			icon.scale = Vector2(zoom, zoom)
			icon.position = Vector2(x + (square - icon.texture.get_width() * zoom) / 2, y + (square - icon.texture.get_height() * zoom) / 2)
			_art.add_child(icon)
		_squares[String(tool_id)] = Rect2(x, y, square, square)
		x += square + gap
	_close = Rect2(int(_row["margin_left_px"]), y, square, square)
	var close := _tile(_close, Color(String(_row["close_color"])), Color(String(_row["close_color"])))
	close.name = "close"
	_art.add_child(close)
	var mark := Sprite2D.new()
	mark.texture = ImageTexture.create_from_image(PatchWindow.close_mark(square, Color(String(_row["close_mark_color"]))))
	mark.centered = false
	mark.position = _close.position
	_art.add_child(mark)


## A tile: its border colour, with the fill inset by `border_px`.
func _tile(rect: Rect2, fill: Color, border: Color) -> ColorRect:
	var edge := ColorRect.new()
	edge.color = border
	edge.position = rect.position
	edge.size = rect.size
	edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var inset := float(_row["border_px"])
	var inner := ColorRect.new()
	inner.color = fill
	inner.position = Vector2(inset, inset)
	inner.size = rect.size - Vector2(inset, inset) * 2.0
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edge.add_child(inner)
	return edge


## A bold ✕ filling the middle of a `square` px tile, in `color`.
static func close_mark(square: int, color: Color) -> Image:
	var image := Image.create_empty(square, square, false, Image.FORMAT_RGBA8)
	var pad := square / 4
	var half := maxf(1.0, square / 10.0)
	for yy in range(pad, square - pad):
		for xx in range(pad, square - pad):
			var cx := xx + 0.5
			var cy := yy + 0.5
			if absf(cx - cy) <= half or absf(cx + cy - square) <= half:
				image.set_pixel(xx, yy, color)
	return image


## The icon drawn in a tool's square, or null.
func tool_icon(tool_id: String) -> Sprite2D:
	return _art.get_node_or_null("icon_" + tool_id) as Sprite2D


## A tool's square in art pixels, or an empty rect.
func tool_square(tool_id: String) -> Rect2:
	return _squares.get(tool_id, Rect2())


## The island's opaque pixels plus the tool squares, joined by a strip so they make the
## one click-through shape.
func _click_image() -> Image:
	var size := art_size()
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var island := def.opaque_image()
	image.blend_rect(island, Rect2i(Vector2i.ZERO, island.get_size()), Vector2i(0, sky_px))
	var rects: Array = _squares.values()
	if _close.size != Vector2.ZERO:
		rects.append(_close)
	var row := Rect2()
	for rect: Rect2 in rects:
		row = rect if row.size == Vector2.ZERO else row.merge(rect)
		image.fill_rect(Rect2i(rect.grow_individual(0, ROW_REACH_PX, 0, 0)), Color.WHITE)
	# The click-through shape is one polygon, and the island may not reach down to the ✕
	# at its left, so a thin strip joins the squares; the gaps beside it stay click-through.
	if row.size != Vector2.ZERO:
		image.fill_rect(Rect2i(int(row.position.x), int(row.get_center().y) - 1, int(row.size.x), 2), Color.WHITE)
		# A shelf island's underside (and the loose rocks under it) hangs free above the row:
		# a thin upright joins the row to the middle of the island's body.
		var middle := sky_px + def.size.y / 2
		image.fill_rect(Rect2i(int(row.get_center().x) - 1, middle, 2, int(row.get_center().y) + 1 - middle), Color.WHITE)
	return image


## The ✕ square in art pixels, or an empty rect.
func close_square() -> Rect2:
	return _close


func close_at(art_point: Vector2) -> bool:
	return _close.has_point(art_point)


## The tool square under `art_point`, or "".
func tool_at(art_point: Vector2) -> String:
	for tool_id in _squares:
		if _squares[tool_id].has_point(art_point):
			return tool_id
	return ""


func select_tool(tool_id: String) -> void:
	_selected = tool_id
	if _squares.has(tool_id):
		_highlight.position = _squares[tool_id].position - Vector2.ONE
		_highlight.visible = true
	else:
		_highlight.visible = false
	if mechanic != null:
		mechanic.on_tool_selected(tool_id)
	redraw()


## True on the island's own pixels (not the sky, not the tool row).
func on_island(art_point: Vector2) -> bool:
	var p := Vector2i(art_point.floor())
	var island_point := p - Vector2i(0, sky_px)
	if island_point.x < 0 or island_point.y < 0 or island_point.x >= def.size.x or island_point.y >= def.size.y:
		return false
	return _opaque.get_pixelv(p).a > 0.5


## Redraws everything at a new scale, keeping the window's bottom centre where it is
## and the window on its screen.
func rescale(new_scale: int) -> void:
	if new_scale == scale_px:
		return
	var old_size := Vector2(size)
	var bottom_centre := Vector2(position) + Vector2(old_size.x / 2.0, old_size.y)
	scale_px = new_scale
	var new_size := art_size() * scale_px
	var was_on_top := always_on_top
	WindowChrome.configure(self, new_size)
	always_on_top = was_on_top
	_art.scale = Vector2(scale_px, scale_px)
	var at := Vector2i((bottom_centre - Vector2(new_size.x / 2.0, new_size.y)).round())
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(get_window_id()))
	# A headless run has no real screen to keep it on.
	if screen.has_area():
		at.x = clampi(at.x, screen.position.x, maxi(screen.position.x, screen.end.x - new_size.x))
		at.y = clampi(at.y, screen.position.y, maxi(screen.position.y, screen.end.y - new_size.y))
	position = at
	_click_shape = WindowChrome.click_shape(_opaque, Vector2i.ZERO, scale_px, _click_epsilon)
	mouse_passthrough_polygon = PackedVector2Array() if _capturing else _click_shape
	WindowChrome.wake(self)


func layer_node(layer: String) -> Node2D:
	return _layers.get(layer, _layers["front"])


## Above the front overlay: mini-games and anything that must not be hidden.
func overlay() -> Node2D:
	return _overlay


## A spot's anchor point in window art pixels.
func spot_point(spot_name: String) -> Vector2:
	return Vector2(def.spots[spot_name]["at"] + Vector2i(0, sky_px))


func spot_layer(spot_name: String) -> String:
	return def.spots[spot_name]["layer"]


## Island pixel coordinates to window art pixels.
func island_to_art(point: Vector2) -> Vector2:
	return point + Vector2(0, sky_px)


func art_to_screen(point: Vector2) -> Vector2:
	return Vector2(position) + point * scale_px


## Where the avatar appears: a `stand` spot if the island has one, else its front
## ground spot, else the middle of the island's front band.
func arrival_point() -> Vector2:
	for kind in ["stand", "ground"]:
		for spot_name in def.spots_of_kind(kind):
			if def.spots[spot_name]["layer"] == "front":
				return spot_point(spot_name)
	return island_to_art(Vector2(def.size.x * 0.5, def.size.y * 0.55)).round()


## While true the whole window takes clicks (the avatar is here, or a mini-game is up),
## so a click on the sky can mean "go home".
func set_capture_all(capture: bool) -> void:
	if capture == _capturing:
		return
	_capturing = capture
	mouse_passthrough_polygon = PackedVector2Array() if capture else _click_shape


func redraw() -> void:
	WindowChrome.redraw(self)


## Lights the whole island `k` times over (1 is normal): the camera's flash (issue 77).
func set_brightness(k: float) -> void:
	_art.modulate = Color(k, k, k, 1.0)
	redraw()


## Redraws whenever `sprite` changes frame, texture or visibility.
func watch(sprite: Sprite2D) -> void:
	sprite.frame_changed.connect(redraw)
	sprite.texture_changed.connect(redraw)
	sprite.visibility_changed.connect(redraw)
