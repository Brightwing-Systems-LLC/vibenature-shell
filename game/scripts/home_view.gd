class_name HomeView
extends Node

## Home, in the root window: the bench (where the avatar starts, sits when idle, and goes
## back to), the mailbox (results hop in; a still glow until it is opened), the sign (a
## settings gear labelled Config; a click opens Config) and the wordmark. Every size and position comes from
## the delivery: `home/layout` places the props, the bench lists its `seats`, the mailbox
## its `slot`.

signal bench_clicked
signal mailbox_clicked
signal sign_clicked
signal right_clicked
signal alt_clicked

var window: Window
var scale_px := 2
var pointer: PointerHandler
var _art := Node2D.new()
var _avatar_layer := Node2D.new()
var _mailbox: CreatureSprite
var _bucks := PixelNumber.new()
## name -> Rect2 in art pixels, for clicks.
var _rects := {}
var _seats: Array = []
var _slot := Rect2()
var _textures := {}
## Clear art pixels above the props, so the avatar's head clears the window's top edge.
var _headroom := 0


func setup(root: Window, scale: int, balance: Balance, idle_fps_max: float) -> void:
	window = root
	scale_px = scale
	window.title = "VibeNature · home"
	var placeholders: Dictionary = balance.data["placeholders"]
	var layout := AssetLibrary.load_meta("home", "layout")
	var size := AssetLibrary.vec2i(layout.get("size", placeholders["home"]))
	var place: Dictionary = layout.get("place", {})
	var ground_y := int(layout.get("ground_y", size.y / 2))
	_headroom = int(balance.data["home"]["headroom_px"])
	WindowChrome.configure(window, (size + Vector2i(0, _headroom)) * scale_px)
	_art.scale = Vector2(scale_px, scale_px)
	_art.position = Vector2(0, _headroom * scale_px)
	add_child(_art)

	var wordmark_at := AssetLibrary.vec2i(place.get("wordmark", [0, size.y - 20]))
	_prop("wordmark", wordmark_at, Vector2i(size.x, 20), Color("f9c22b"))
	var bench_at := AssetLibrary.vec2i(place.get("bench", [size.x / 4, ground_y - 24]))
	var bench_size := _prop("bench", bench_at, Vector2i(size.x / 2, 24), Color("8a4836"))
	for seat in AssetLibrary.load_meta("home", "bench").get("seats", []):
		_seats.append(Vector2(bench_at + AssetLibrary.vec2i(seat["at"])))
	if _seats.is_empty():
		_seats.append(Vector2(bench_at) + Vector2(bench_size.x / 2.0, bench_size.y / 2.0))
	var sign_at := AssetLibrary.vec2i(place.get("sign", [size.x - 36, ground_y - 40]))
	var sign_meta := AssetLibrary.load_meta("home", "sign")
	if int(sign_meta.get("version", 0)) >= int(balance.data["home"]["sign_gear_from_version"]):
		_prop("sign", sign_at, Vector2i(32, 40), Color("c28d75"))
	else:
		# The delivered sign is still the old A-frame; the gear's art is
		# Skypatch issue 31. Same footprint meanwhile.
		var old := AssetLibrary.load_texture("home", "sign", "sign")
		var footprint := Vector2i(43, 50) if old == null else Vector2i(old.get_width(), old.get_height())
		_prop("sign", sign_at, footprint, Color.WHITE, ImageTexture.create_from_image(HomeView.placeholder_gear(footprint)))

	var mailbox_at := AssetLibrary.vec2i(place.get("mailbox", [0, ground_y - 32]))
	var mailbox_meta := AssetLibrary.load_meta("home", "mailbox")
	var mailbox_def := CreatureDef.load_single("home", "mailbox", idle_fps_max, CreatureDef.sheet_layer(
			Vector2i(16, 32), 2, Color("4d65b4"), {"closed": {"frames": [0], "fps": 1.0, "loop": true}},
			Vector2i(8, 31)))
	_mailbox = CreatureSprite.new(mailbox_def)
	_mailbox.set_layer("front")
	var sheet: Dictionary = mailbox_def.layers["front"]
	var anchor: Vector2i = sheet["anchor"]
	var frame: Vector2i = sheet["frame_size"]
	_mailbox.position = Vector2(mailbox_at + anchor)
	_art.add_child(_mailbox)
	_mailbox.show_frame(0)
	_rects["mailbox"] = Rect2(Vector2(mailbox_at), Vector2(frame))
	var slot: Array = mailbox_meta.get("slot", [frame.x / 2 - 4, frame.y / 3, 8, 3])
	_slot = Rect2(Vector2(mailbox_at) + Vector2(float(slot[0]), float(slot[1])), Vector2(float(slot[2]), float(slot[3])))

	_art.add_child(_avatar_layer)
	_bucks.position = Vector2(mailbox_at) + Vector2(AssetLibrary.vec2i(balance.data["home"]["counter_offset_px"]))
	_art.add_child(_bucks)

	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	for prop in ["wordmark", "bench", "sign"]:
		var texture := _textures.get(prop) as Texture2D
		if texture != null:
			var piece := texture.get_image()
			if piece.is_compressed():
				piece.decompress()
			piece.convert(Image.FORMAT_RGBA8)
			image.blend_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(_rects[prop].position))
	image.fill_rect(Rect2i(_rects["mailbox"]), Color.WHITE)
	# The props stand apart; a thin invisible band along the ground joins them into one
	# clickable shape (the click-through shape is a single polygon).
	var band := int(balance.data["home"]["click_band_px"])
	image.fill_rect(Rect2i(0, ground_y - band, size.x, maxi(wordmark_at.y - ground_y + band * 2, band)), Color.WHITE)
	WindowChrome.set_click_shape(window, image, Vector2i(0, _headroom), scale_px, float(balance.data["display"]["click_shape_epsilon"]))
	pointer = PointerHandler.new(window, float(balance.data["input"]["drag_threshold_px"]))
	pointer.clicked.connect(_on_click)
	pointer.alt_clicked.connect(func(_at: Vector2) -> void: alt_clicked.emit())


## Draws a prop from `home/<name>/<name>.png` with its top-left at `at`, or a placeholder
## block. Returns its size.
func _prop(prop: String, at: Vector2i, placeholder: Vector2i, color: Color, drawn: Texture2D = null) -> Vector2i:
	var texture := drawn if drawn != null else AssetLibrary.load_texture("home", prop, prop)
	if texture == null:
		texture = AssetLibrary.solid_texture(placeholder, color)
	_textures[prop] = texture
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = Vector2(at)
	_art.add_child(sprite)
	var size := Vector2i(texture.get_width(), texture.get_height())
	_rects[prop] = Rect2(Vector2(at), Vector2(size))
	return size


## A stand-in for the gear sign: an eight-toothed cog over the word CONFIG, in the
## palette, filling `size` with its bottom on the ground line.
static func placeholder_gear(size: Vector2i) -> Image:
	var image := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	var text_h := 7
	var gear_d := mini(size.x - 2, size.y - text_h - 6)
	var centre := Vector2(size.x / 2.0, gear_d / 2.0 + 1.0)
	var outer := gear_d / 2.0
	var body := outer * 0.78
	var hole := outer * 0.3
	var tooth := TAU / 8.0
	var light := Color("c7dcd0")
	var shade := Color("7f708a")
	var edge := Color("3e3546")
	var inside := func(x: int, y: int) -> bool:
		var d := Vector2(x + 0.5, y + 0.5) - centre
		var r := d.length()
		var reach := outer if fposmod(d.angle() + tooth / 4.0, tooth) < tooth / 2.0 else body
		return r <= reach and r >= hole
	for y in size.y:
		for x in size.x:
			if not inside.call(x, y):
				continue
			var rim: bool = not (inside.call(x - 1, y) and inside.call(x + 1, y) and inside.call(x, y - 1) and inside.call(x, y + 1))
			var d := Vector2(x + 0.5, y + 0.5) - centre
			var color := Color("9babb2")
			if rim:
				color = edge
			elif d.x + d.y < -outer * 0.5:
				color = light
			elif d.x + d.y > outer * 0.6:
				color = shade
			image.set_pixel(x, y, color)
	var glyphs := {
		"C": [".###.", "#...#", "#....", "#....", "#....", "#...#", ".###."],
		"O": [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
		"N": ["#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"],
		"F": ["#####", "#....", "#....", "####.", "#....", "#....", "#...."],
		"I": [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
		"G": [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
	}
	var word := "CONFIG"
	var x0 := (size.x - (word.length() * 6 - 1)) / 2
	var y0 := size.y - text_h - 2
	for i in word.length():
		var rows: Array = glyphs[word[i]]
		for row in rows.size():
			for col in 5:
				if String(rows[row])[col] != "#":
					continue
				var at := Vector2i(x0 + i * 6 + col, y0 + row)
				if at.x + 1 < size.x and at.y + 1 < size.y:
					image.set_pixelv(at + Vector2i(1, 1), Color("2e222f"))
				image.set_pixelv(at, Color("f9c22b"))
	return image


func _on_click(button: int, at: Vector2) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		right_clicked.emit()
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	var art := at / scale_px - Vector2(0, _headroom)
	if _rects["mailbox"].has_point(art):
		mailbox_clicked.emit()
	elif _rects["sign"].has_point(art):
		sign_clicked.emit()
	else:
		bench_clicked.emit()


## Where the avatar is drawn at home.
func avatar_host() -> Node2D:
	return _avatar_layer


func seat_point(index: int = -1) -> Vector2:
	if index < 0 or index >= _seats.size():
		index = _seats.size() / 2
	return _seats[index]


## Where results land: the middle of the mailbox's slot, in screen coordinates.
func bin_screen_point() -> Vector2:
	return Vector2(window.position) + (_slot.get_center() + Vector2(0, _headroom)) * scale_px


## The mailbox's `has_mail` frame (a still glow) or `closed`.
func set_bin_full(full: bool) -> void:
	_mailbox.show_frame(1 if full else 0)


func set_bucks(bucks: int) -> void:
	if _bucks.set_value(bucks):
		WindowChrome.redraw(window)
