class_name SceneAvatarPicker
extends VBoxContainer

## The avatar picker in Config's Avatar tab (Skypatch issue 202):
## a preview, Body 1 or Body 2 as two silhouettes, the five looks of that body by picture, then swatches
## for skin (12), hair colour (only the look's `hair_allowed`; the row hides when there is one) and top (9).
## Pictures are the swapped look at one sheet px per device px, never resampled, on the field kit's
## segment tiles (gold when chosen). Nothing is labelled by gender. A choice emits `changed` with the whole look.

signal changed(look: Dictionary)
## The van's paint (issue 279): {body, accent}, from the "Your van" rows under the look's.
signal van_changed(choice: Dictionary)

## [field, heading] of the van's rows (`setup_van`); the field is "van_" + the paint material.
const VAN_ROWS: Array = [["van_body", "Body colour"], ["van_accent", "Accent colour"]]

## [field, heading, kind]
const ROWS: Array = [
	["body", "Body", "silhouette"],
	["look", "Look", "picture"],
	["skin", "Skin tone", "swatch"],
	["hair", "Hair colour", "swatch"],
	["top", "Top colour", "swatch"],
]

var kit: SceneConfigKit
var cfg: Dictionary = {}
var tuning: Dictionary = {}
var look: Dictionary = {}
var k := 1.0
var min_small_pt := 12.0
var preview := TextureRect.new()
## field -> {str(value): Tile}
var tiles := {}
## field -> the row's box (the hair row hides when the look has one hair colour).
var rows := {}
var _flows := {}
var _filled := {}
## The van's sheet and meta (`setup_van`), and its paint now.
var van_art := ""
var van_meta: Dictionary = {}
var van: Dictionary = {}
var van_preview := TextureRect.new()


func setup(owner_kit: SceneConfigKit, ui_scale: float, look_cfg: Dictionary, start: Dictionary, small_pt: float) -> void:
	kit = owner_kit
	k = ui_scale
	cfg = look_cfg
	tuning = cfg["picker"]
	min_small_pt = small_pt
	look = AvatarLook.sanitize(start, cfg)
	add_theme_constant_override("separation", int(_pt("gap_pt")))
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", int(10 * k))
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var crop: Array = tuning["preview_crop"]
	preview.custom_minimum_size = Vector2(float(crop[2]), float(crop[3]))
	top.add_child(preview)
	add_child(top)
	for row in ROWS:
		var field := String(row[0])
		var box := _row(field, String(row[1]), String(row[2]))
		rows[field] = box
		# The body choice sits beside the preview; the rest below it at full width.
		if field == "body":
			box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			top.add_child(box)
		else:
			add_child(box)
	refresh()


## "Your van" (issue 279): a heading, the van parked as it stands on the bank (facing left, painted, one sheet px
## per device px) and body and accent swatches from the bench's paint ramps. Without the van's paint, no rows.
func setup_van(art: String, meta: Dictionary, start: Dictionary) -> void:
	van_art = art
	van_meta = meta
	if VanPaint.options(meta, "body").is_empty():
		return
	van = VanPaint.sanitize(start, meta)
	var box := VBoxContainer.new()
	box.name = "YourVan"
	box.add_theme_constant_override("separation", int(_pt("gap_pt")))
	var heading := Label.new()
	heading.text = "Your van"
	_style(heading, "label")
	heading.add_theme_color_override("font_color", kit.colour("ink"))
	box.add_child(heading)
	van_preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	van_preview.stretch_mode = TextureRect.STRETCH_KEEP
	van_preview.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(van_preview)
	for row in VAN_ROWS:
		var r := _row(String(row[0]), String(row[1]), "swatch")
		rows[String(row[0])] = r
		box.add_child(r)
	rows["van"] = box
	add_child(box)
	refresh()


## Shows `choice` without emitting (Config opening).
func set_van(choice: Dictionary) -> void:
	if van_meta.is_empty():
		return
	van = VanPaint.sanitize(choice, van_meta)
	refresh()


## Shows `new_look` without emitting (Config opening).
func set_look(new_look: Dictionary) -> void:
	look = AvatarLook.sanitize(new_look, cfg)
	refresh()


## Picks `value` for `field`, as a click on its tile does. Body 1 or 2 moves to that body's first look.
func choose(field: String, value: Variant) -> void:
	if field.begins_with("van_"):
		var paint := van.duplicate()
		paint[field.trim_prefix("van_")] = String(value)
		paint = VanPaint.sanitize(paint, van_meta)
		if VanPaint.key(paint) == VanPaint.key(van):
			return
		van = paint
		refresh()
		van_changed.emit(van.duplicate())
		return
	var next := look.duplicate()
	match field:
		"body":
			if AvatarLook.body(String(look["look"])) != int(value):
				var choices := AvatarLook.looks_for_body(int(value))
				if choices.is_empty():
					return
				next = AvatarLook.with_look(look, String(choices[0]), cfg)
		"look":
			next = AvatarLook.with_look(look, String(value), cfg)
		_:
			next[field] = String(value)
			next = AvatarLook.sanitize(next, cfg)
	if AvatarLook.key(next) == AvatarLook.key(look):
		return
	look = next
	refresh()
	changed.emit(look.duplicate())


## The value shown as chosen for `field`.
func current(field: String) -> String:
	if field.begins_with("van_"):
		return String(van.get(field.trim_prefix("van_"), ""))
	return str(AvatarLook.body(String(look["look"]))) if field == "body" else String(look[field])


## The option ids a row shows now.
func options(field: String) -> Array:
	match field:
		"body":
			return [1, 2]
		"look":
			return AvatarLook.looks_for_body(AvatarLook.body(String(look["look"])))
		"van_body", "van_accent":
			return VanPaint.options(van_meta, field.trim_prefix("van_"))
		_:
			return AvatarLook.options(field, String(look["look"]))


func refresh() -> void:
	preview.texture = _crop(AvatarLook.frame_image(look, 0), "preview_crop")
	if not van.is_empty():
		var parked := int(van_meta["animations"]["parked"]["frames"][0])
		var image := VanPaint.frame_image(van_art, van_meta, van, parked, true)
		van_preview.texture = ImageTexture.create_from_image(image) if image != null else null
	for field in tiles:
		var wanted := options(field)
		if _filled.get(field, []) != wanted:
			_fill(field, wanted)
		for id in tiles[field]:
			var tile: Tile = tiles[field][id]
			tile.selected = current(field) == id
			if field == "look":
				tile.picture = _crop(AvatarLook.frame_image(AvatarLook.with_look(look, String(id), cfg), 0), "look_crop")
			tile.queue_redraw()
	rows["hair"].visible = options("hair").size() > 1


## The silhouette of a body: a look's resting frame, every drawn pixel in one ink colour.
func _silhouette(body_type: int) -> Texture2D:
	var look_id := String(cfg["silhouette"].get(str(body_type), ""))
	if AvatarLook.meta(look_id).is_empty():
		var any := AvatarLook.looks_for_body(body_type)
		if any.is_empty():
			return null
		look_id = String(any[0])
	var image := AvatarLook.frame_image(AvatarLook.look_defaults(look_id), 0)
	if image == null:
		return null
	var ink := Color(String(tuning["silhouette"]))
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.0:
				image.set_pixel(x, y, ink)
	return _crop(image, "body_crop")


## A frame cut round its anchor, at one sheet px per device px (never resampled).
func _crop(image: Image, crop_key: String) -> Texture2D:
	if image == null:
		return null
	var crop: Array = tuning[crop_key]
	var any := AvatarLook.meta(String(look["look"]))
	var anchor := AssetLibrary.vec2i(any.get("log", {}).get("anchor", [0, 0]))
	var want := Rect2i(anchor.x + int(crop[0]), anchor.y + int(crop[1]), int(crop[2]), int(crop[3]))
	var have := want.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var out := Image.create_empty(want.size.x, want.size.y, false, Image.FORMAT_RGBA8)
	if have.has_area():
		out.blit_rect(image, have, have.position - want.position)
	return ImageTexture.create_from_image(out)


func _row(field: String, heading: String, kind: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(_pt("row_gap_pt")))
	var label := Label.new()
	label.text = heading
	_style(label, "label")
	label.add_theme_color_override("font_color", kit.colour("ink"))
	box.add_child(label)
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", int(_pt("gap_pt")))
	flow.add_theme_constant_override("v_separation", int(_pt("gap_pt")))
	flow.set_meta("kind", kind)
	box.add_child(flow)
	_flows[field] = flow
	tiles[field] = {}
	return box


## (Re)makes a row's tiles for `values`: the looks change with the body, the hair colours with the look.
func _fill(field: String, values: Array) -> void:
	var flow: HFlowContainer = _flows[field]
	var kind := String(flow.get_meta("kind"))
	for child in flow.get_children():
		flow.remove_child(child)
		child.queue_free()
	tiles[field] = {}
	for value in values:
		var tile := Tile.new()
		tile.picker = self
		tile.field = field
		tile.value = value
		tile.kind = kind
		var pad := _pt("tile_pad_pt") * 2.0
		match kind:
			"swatch":
				if field.begins_with("van_"):
					tile.colours = VanPaint.ramp(van_meta, field.trim_prefix("van_"), String(value))
					tile.tooltip_text = VanPaint.word(van_meta, field.trim_prefix("van_"), String(value))
				else:
					tile.colours = AvatarLook.ramp(field, String(value))
					tile.tooltip_text = AvatarLook.word(field, String(value))
				var s: Array = tuning["swatch_pt"]
				tile.custom_minimum_size = Vector2(float(s[0]), float(s[1])) * k
			"silhouette":
				tile.caption = "Body %d" % int(value)
				tile.tooltip_text = tile.caption
				tile.picture = _silhouette(int(value))
				var crop: Array = tuning["body_crop"]
				tile.custom_minimum_size = Vector2(float(crop[2]) + pad, float(crop[3]) + pad + _caption_h())
			_:
				tile.tooltip_text = "Look %d" % (AvatarLook.ids().find(value) + 1)
				var crop: Array = tuning["look_crop"]
				tile.custom_minimum_size = Vector2(float(crop[2]) + pad, float(crop[3]) + pad)
		tiles[field][str(value)] = tile
		flow.add_child(tile)
	_filled[field] = values.duplicate()


func _caption_h() -> float:
	return roundf(_small_pt() * 1.5 * k)


func _small_pt() -> float:
	return maxf(kit.font_size_pt("small"), min_small_pt)


func _style(label: Label, style_name: String) -> void:
	var size_pt := kit.font_size_pt(style_name)
	if style_name == "small":
		size_pt = _small_pt()
	label.add_theme_font_override("font", kit.font(style_name))
	label.add_theme_font_size_override("font_size", int(round(size_pt * k)))


func _pt(key: String) -> float:
	return float(tuning[key]) * k


## One choice on the kit's tile: a swatch of the ramp, or a picture (with its word under it for a body).
class Tile:
	extends Control

	var picker: SceneAvatarPicker
	var field := ""
	var value: Variant
	var kind := "swatch"
	var colours: Array[Color] = []
	var picture: Texture2D
	var caption := ""
	var selected := false
	var hovered := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_NONE
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		mouse_entered.connect(func() -> void:
			hovered = true
			queue_redraw())
		mouse_exited.connect(func() -> void:
			hovered = false
			queue_redraw())

	func _gui_input(event: InputEvent) -> void:
		var button := event as InputEventMouseButton
		if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			picker.choose(field, value)
			accept_event()

	func _draw() -> void:
		var kit := picker.kit
		var state := "selected" if selected else ("hover" if hovered else "normal")
		var rect := Rect2(Vector2.ZERO, size)
		draw_style_box(kit.style("segment", state), rect)
		var pad := picker._pt("tile_pad_pt")
		var inner := rect.grow(-pad)
		if kind == "swatch" and not colours.is_empty():
			# The ramp in bands, light at the top, as the colour falls on a figure.
			var n := colours.size()
			draw_rect(inner, colours[n / 2])
			var band := floorf(inner.size.y / 4.0)
			draw_rect(Rect2(inner.position.x, inner.end.y - band, inner.size.x, band), colours[1])
			draw_rect(Rect2(inner.position, Vector2(inner.size.x, band)), colours[n - 1])
		if picture != null:
			var at := (inner.position + Vector2((inner.size.x - picture.get_width()) / 2.0, 0)).floor()
			draw_texture(picture, at)
			if caption != "":
				var font := kit.font("small")
				var font_size := int(round(picker._small_pt() * picker.k))
				var base := Vector2(inner.position.x, inner.position.y + picture.get_height() + font_size)
				draw_string(font, base.floor(), caption, HORIZONTAL_ALIGNMENT_CENTER, inner.size.x, font_size, kit.colour("ink"))
