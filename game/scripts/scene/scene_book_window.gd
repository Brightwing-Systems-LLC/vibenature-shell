class_name SceneBookWindow
extends Window

## The book (Skypatch issue 177), opened by the strip's 📖:
## a leather field journal in its own small window beside the scene, like Config. Two parts:
## **Photos** (the album, newest first, each photo as framed in the viewfinder, with date, time,
## weather and species; buttons to enlarge, export a copy, show it in Finder, delete it after asking
## once) and **Field guide** (every species seen in the scene, first and last seen, a picture from its
## sheet). Never a checklist, never anything "missing" (SPEC §2). Room for the elder's letters later
## (issue 127).
##
## Drawn with the bench's book kit (the companion's `journal/`,Skypatch issue 185):
## cover, the open journal as a two-page spread (Skypatch issue 189:
## `page_left` and `page_right` edge to edge make the spine; photos and guide entries fill the left page,
## then the right, then turn to the next spread; an enlarged photo sits on the right page with its
## caption and buttons on the left, never across the spine), `page_single` only when the screen is too
## narrow for a spread (`spread_min_width_pt`), ribbons for the parts, photo mounts, the action and turn
## buttons, entry cards and the empty-page note; @1x on a 1× screen and @2x on 2× and up, one sheet px
## per device px. The Delete / Keep words are the config kit's buttons. It may take keyboard focus only
## because the person opened it (SPEC §2.1).

signal closed

const PHOTOS := 0
const FIELD_GUIDE := 1
## The elder's letters (issue 213): the third ribbon, newest first, kept like photos.
const LETTERS := 2
const TAB_NAMES: Array[String] = ["Photos", "Field guide", "Letters"]
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var game: Game
var album: PhotoAlbum
var sightings: SceneSightings
var tuning: Dictionary = {}
## The config's field kit (theme, Delete/Keep buttons, body fonts) and the book's own kit.
var kit: SceneConfigKit
var book_kit: SceneConfigKit
var tabs := TabContainer.new()
## The photo shown large, or "".
var enlarged := ""
## The photo whose delete is asking, or "".
var confirming := ""
## Tests replace these so nothing opens: reveal(path), save_dialog(default_name, done(path)).
var reveal: Callable
var save_dialog: Callable
## Two pages side by side (the spread), or one (`page_single`) on a screen too narrow for it.
var spread := true
## The spread (or single page) each part is open at.
var turned_to: Array[int] = [0, 0, 0]
var _k := 1.0
## Each part: its pages ("Pages", edge to edge) and, over them, an enlarged photo's print.
var _parts: Array[Control] = [Control.new(), Control.new(), Control.new()]
var _header_row: Control
var _thumbs := {}


func setup(owner_game: Game, photo_album: PhotoAlbum, seen: SceneSightings) -> void:
	game = owner_game
	album = photo_album
	sightings = seen
	reveal = func(path: String) -> void:
		if not Snapshot.on():
			OS.shell_show_in_file_manager(path)
	save_dialog = _native_save_dialog
	tuning = game.balance.data["scene_book"]
	_k = Game.ui_scale(Snapshot.on(), DisplayServer.screen_get_max_scale())
	title = "VibeNature · field journal"
	visible = false
	borderless = true
	unresizable = true
	transparent = false
	transparent_bg = false
	unfocusable = false
	size = Vector2i((Vector2(float(tuning["size_pt"][0]), float(tuning["size_pt"][1])) * _k).round())
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	kit = SceneConfigKit.new(_k)
	book_kit = SceneConfigKit.new(_k, SceneConfigKit.book_dir())
	theme = _theme()

	var cover := Panel.new()
	cover.name = "Cover"
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.add_theme_stylebox_override("panel", book_kit.style("cover"))
	add_child(cover)
	var pad := _lay("cover_inset_pt") * _k
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = pad
	box.offset_top = pad
	box.offset_right = -pad
	box.offset_bottom = -pad
	box.add_theme_constant_override("separation", int(_pt("gap_pt")))
	add_child(box)
	_header_row = _header()
	box.add_child(_header_row)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	for part in [PHOTOS, FIELD_GUIDE, LETTERS]:
		var holder := _parts[part]
		holder.name = TAB_NAMES[part].replace(" ", "")
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pages := HBoxContainer.new()
		pages.name = "Pages"
		pages.set_anchors_preset(Control.PRESET_FULL_RECT)
		pages.add_theme_constant_override("separation", 0)
		holder.add_child(pages)
		tabs.add_child(holder)
		tabs.set_tab_title(part, TAB_NAMES[part])
	album.changed.connect(func() -> void:
		if visible:
			_thumbs.clear()
			refresh())
	window_input.connect(_on_key)


## Shows the book on `tab`, beside the scene, and takes keyboard focus (the person opened it).
func open(tab: int) -> void:
	tabs.current_tab = tab
	enlarged = ""
	confirming = ""
	turned_to = [0, 0, 0]
	var usable := game.scene_usable()
	use_spread(usable.size.x <= 0 or SceneBookWindow.fits_spread(usable.size.x / _k, tuning))
	position = SceneConfigWindow.place_beside(Rect2i(game.scene.position, game.scene.size), size, game.scene_usable(),
			int(_pt("gap_to_scene_pt")))
	show()
	grab_focus()


func close_book() -> void:
	if not visible:
		return
	hide()
	_thumbs.clear()
	closed.emit()


## True when a screen `width_pt` wide has room for the spread; narrower, the book is one page.
static func fits_spread(width_pt: float, book_tuning: Dictionary) -> bool:
	return width_pt >= float(book_tuning["spread_min_width_pt"])


## The spread (two pages) or a single page, at the window size for it.
func use_spread(on: bool) -> void:
	spread = on
	var pt: Array = tuning["size_pt"] if on else tuning["narrow_size_pt"]
	size = Vector2i((Vector2(float(pt[0]), float(pt[1])) * _k).round())
	refresh()


func pages_per_view() -> int:
	return 2 if spread else 1


## Turns the part's pages by `step` spreads (or single pages), within the ones there are.
func turn(part: int, step: int) -> void:
	turned_to[part] = clampi(turned_to[part] + step, 0, _views(part) - 1)
	enlarged = ""
	confirming = ""
	refresh()


func refresh() -> void:
	_build_photos()
	_build_guide()
	_build_letters()


## How many spreads (or single pages) a part fills.
func _views(part: int) -> int:
	var count := album.photos().size() if part == PHOTOS else (sightings.entries().size() if sightings != null else 0)
	if part == LETTERS:
		count = _letters().size()
	var per := int(tuning[["photos_per_page", "entries_per_page", "letters_per_page"][part]]) * pages_per_view()
	return maxi(1, ceili(float(count) / per))


func _letters() -> Array:
	return game.letters.kept() if game != null and game.letters != null else []


## Sends the photo to the elder (one click, never undone), then shows its sent mark.
func send_photo(id: String) -> void:
	game.send_photo(id)
	refresh()


func enlarge(id: String) -> void:
	enlarged = id
	confirming = ""
	refresh()


func back_to_album() -> void:
	enlarged = ""
	confirming = ""
	refresh()


func ask_delete(id: String) -> void:
	confirming = id
	refresh()


func keep(_id: String) -> void:
	confirming = ""
	refresh()


func delete_photo(id: String) -> void:
	confirming = ""
	if enlarged == id:
		enlarged = ""
	_thumbs.erase(id)
	album.remove(id)
	refresh()


func reveal_photo(id: String) -> void:
	reveal.call(album.path_of(id))


## Asks where to save a copy (a native save dialog), then saves the photo there.
func export_photo(id: String) -> void:
	var photo := _photo(id)
	if photo.is_empty():
		return
	save_dialog.call(PhotoAlbum.export_name(photo), func(path: String) -> void: album.export_to(id, path))


func _native_save_dialog(default_name: String, done: Callable) -> void:
	if Snapshot.on():
		return
	var start := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	DisplayServer.file_dialog_show("Save a copy of this photo", start, default_name, false,
			DisplayServer.FILE_DIALOG_MODE_SAVE_FILE, PackedStringArray(["*.png ; PNG image"]),
			func(ok: bool, paths: PackedStringArray, _filter: int) -> void:
				if ok and not paths.is_empty():
					done.call(paths[0]))


# Photos ---------------------------------------------------------------------------------------

func _build_photos() -> void:
	var photos := album.photos()
	if enlarged != "" and _photo(enlarged).is_empty():
		enlarged = ""
	turned_to[PHOTOS] = clampi(turned_to[PHOTOS], 0, _views(PHOTOS) - 1)
	var per := int(tuning["photos_per_page"])
	var pages := _pages(PHOTOS, photos.size(), per)
	if photos.is_empty():
		pages[0].add_child(_empty_note("No photos yet: the camera is in the scene's top-right corner."))
		return
	if enlarged != "":
		_parts[PHOTOS].add_child(_print_view(_photo(enlarged)))
	var first := turned_to[PHOTOS] * per * pages.size()
	for p in pages.size():
		pages[p].name = "PhotoPage_%d" % p
		for i in range(first + p * per, mini(first + (p + 1) * per, photos.size())):
			pages[p].add_child(_card(photos[i], i))


func _card(photo: Dictionary, index: int) -> Control:
	var id := String(photo["id"])
	var card := VBoxContainer.new()
	card.name = "Photo_" + id
	card.add_theme_constant_override("separation", int(_lay("caption_gap_pt") * _k))
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := Vector2i((Vector2(float(tuning["thumb_pt"][0]), float(tuning["thumb_pt"][1])) * _k).round())
	var mount := _mounted(_thumb(id, box), "mount_tape" if index % 2 == 1 else "mount_corners")
	mount.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mount.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			enlarge(id))
	card.add_child(mount)
	card.add_child(_caption(photo))
	card.add_child(_photo_buttons(id, true))
	return card


## An enlarged photo as a loose print laid on the open journal ("EnlargedView", over every page): the
## photo in its mount, as large as the pages allow, centred over them with a soft shadow, so it sits
## above the spine rather than across it; its caption and buttons ("Enlarged") just below. A click
## anywhere off the print and its words goes back to the pages.
func _print_view(photo: Dictionary) -> Control:
	var view := Control.new()
	view.name = "EnlargedView"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_STOP
	view.gui_input.connect(func(event: InputEvent) -> void:
		var click := event as InputEventMouseButton
		if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			back_to_album())
	# The pages under the print fade back, so its words never sit on another photo's buttons.
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Color(tuning["print_scrim"])
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(centre)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", int(_lay("caption_gap_pt") * _k))
	centre.add_child(column)
	var inset := _lay("photo_inset_pt") * _k
	var fit := print_area() - Vector2(2.0, 2.0) * _pt("print_margin_pt") - Vector2(0.0, _pt("print_words_pt")) \
			- Vector2(inset * 2.0 + _k, inset * 2.0 + _k)
	var tex := SceneBookWindow.print_texture(album.image(String(photo["id"])), fit)
	var print_box := Control.new()
	print_box.name = "EnlargedPhoto"
	print_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mounted := _mounted(tex, "mount_corners")
	print_box.custom_minimum_size = mounted.custom_minimum_size
	print_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var shadow := Panel.new()
	shadow.name = "Shadow"
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var soft := StyleBoxFlat.new()
	soft.bg_color = Color(0, 0, 0, 0)
	soft.draw_center = false
	soft.shadow_color = Color(tuning["print_shadow"])
	soft.shadow_size = int(_pt("print_shadow_pt"))
	soft.shadow_offset = Vector2(0.0, _pt("print_shadow_pt") * 0.4)
	shadow.add_theme_stylebox_override("panel", soft)
	print_box.add_child(shadow)
	print_box.add_child(mounted)
	column.add_child(print_box)
	var words := VBoxContainer.new()
	words.name = "Enlarged"
	words.mouse_filter = Control.MOUSE_FILTER_STOP
	words.add_theme_constant_override("separation", int(_lay("caption_gap_pt") * _k))
	words.add_child(_caption(photo, true))
	words.add_child(_photo_buttons(String(photo["id"]), false))
	column.add_child(words)
	return view


## The room for a print: the part's area under the ribbons (the window less the cover, header and ribbons),
## worked out from minimum sizes so it holds before any layout.
func print_area() -> Vector2:
	var inset := _lay("cover_inset_pt") * _k
	var top := _header_row.get_combined_minimum_size().y + _pt("gap_pt") + tabs.get_tab_bar().get_combined_minimum_size().y
	return Vector2(size) - Vector2(2.0 * inset, 2.0 * inset + top)


## A photo scaled to fit `fit` (device px), keeping its aspect: down smoothly, up only by whole pixels.
static func print_texture(img: Image, fit: Vector2) -> Texture2D:
	if img == null:
		return null
	var s := minf(fit.x / img.get_width(), fit.y / img.get_height())
	if s >= 1.0:
		var whole := floori(s)
		if whole > 1:
			img.resize(img.get_width() * whole, img.get_height() * whole, Image.INTERPOLATE_NEAREST)
	else:
		img.resize(maxi(1, int(img.get_width() * s)), maxi(1, int(img.get_height() * s)), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(img)


## Clears a part and lays out its pages for the current view: page_left and page_right edge to edge
## (the spine between), or page_single; each with its padding, a box for its items, and a foot with
## the page number and the turn buttons on the outer sides. Returns the item boxes, left to right.
func _pages(part: int, count: int, per: int) -> Array[VBoxContainer]:
	for child in _parts[part].get_children():
		if child.name != "Pages":
			_parts[part].remove_child(child)
			child.queue_free()
	var holder := _parts[part].get_node("Pages") as HBoxContainer
	_clear(holder)
	var pieces: Array = ["page_left", "page_right"] if spread else ["page_single"]
	var at := turned_to[part]
	var boxes: Array[VBoxContainer] = []
	var pad := _lay("page_padding_pt") * _k
	for p in pieces.size():
		var page := Panel.new()
		page.name = "Page_" + pieces[p]
		page.add_theme_stylebox_override("panel", book_kit.style(pieces[p]))
		page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		page.clip_contents = true
		var column := VBoxContainer.new()
		column.set_anchors_preset(Control.PRESET_FULL_RECT)
		column.offset_left = pad
		column.offset_right = -pad
		column.offset_top = pad
		column.offset_bottom = -_lay("turn_inset_pt") * _k
		column.add_theme_constant_override("separation", int(_pt("gap_pt")))
		page.add_child(column)
		var items := VBoxContainer.new()
		items.size_flags_vertical = Control.SIZE_EXPAND_FILL
		items.add_theme_constant_override("separation", int(_pt("gap_pt")))
		column.add_child(items)
		var foot := HBoxContainer.new()
		foot.name = "Foot"
		var first := p == 0
		var last := p == pieces.size() - 1
		foot.add_child(_turn("turn_prev", part, -1) if first and at > 0 else _plate_gap())
		var page_no := at * pieces.size() + p
		var number := _label(str(page_no + 1) if count > page_no * per else "")
		_styled(number, "small")
		number.add_theme_color_override("font_color", book_kit.colour("ink_soft"))
		number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		number.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		foot.add_child(number)
		foot.add_child(_turn("turn_next", part, 1) if last and at < _views(part) - 1 else _plate_gap())
		column.add_child(foot)
		holder.add_child(page)
		boxes.append(items)
	return boxes


## A turn button, only where there is a page to turn to (else `_plate_gap` keeps its room).
func _turn(piece: String, part: int, step: int) -> TextureButton:
	return _action(piece, "Turn the page back" if step < 0 else "Turn the page", func() -> void: turn(part, step),
			"TurnPrev" if step < 0 else "TurnNext")


func _plate_gap() -> Control:
	var gap := Control.new()
	gap.custom_minimum_size = book_kit.size_pt("turn_next") * _k
	return gap


## The day, time and weather on one line in the caption hand, who was about under it.
func _caption(photo: Dictionary, large := false) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(1 * _k))
	var words: Array[String] = [SceneBookWindow.day_text(String(photo["date"])), String(photo["time"])]
	if String(photo["weather"]) != "":
		words.append(String(photo["weather"]))
	var line := _label(" · ".join(words))
	_caption_styled(line, "note" if large else "caption")
	line.add_theme_color_override("font_color", book_kit.colour("caption"))
	box.add_child(line)
	var names: Array[String] = []
	for s in photo["species"]:
		names.append(_species_name(String(s)))
	if not names.is_empty():
		var who := _note(", ".join(names))
		if not large:
			who.max_lines_visible = 2
			who.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		box.add_child(who)
	if not large:
		# Every cell's caption is the same height (two species lines), so the buttons line up across a row.
		var line_h := line.get_theme_font("font").get_height(line.get_theme_font_size("font_size"))
		var small_size := int(round(maxf(kit.font_size_pt("small"), float(game.balance.data["scene_config"]["min_small_pt"])) * _k))
		var small_h := kit.font("small").get_height(small_size)
		box.custom_minimum_size.y = ceilf(line_h + 2.0 * small_h + 2.0 * _k)
		box.clip_contents = true
	return box


func _photo_buttons(id: String, in_album: bool) -> Control:
	var row := HBoxContainer.new()
	row.name = "Buttons"
	row.add_theme_constant_override("separation", int(_lay("action_gap_pt") * _k))
	if confirming == id:
		var ask := _label("Delete this photo?")
		_styled(ask, "label")
		ask.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ask)
		row.add_child(_button("Delete", func() -> void: delete_photo(id), "ConfirmDelete"))
		row.add_child(_button("Keep", func() -> void: keep(id), "Keep"))
		return row
	if in_album:
		row.add_child(_action("act_enlarge", "Enlarge", func() -> void: enlarge(id), "Enlarge"))
	else:
		row.add_child(_action("act_close", "Back to the album", back_to_album, "Back"))
	row.add_child(_action("act_export", "Save a copy…", func() -> void: export_photo(id), "Export"))
	row.add_child(_action("act_reveal", "Show in Finder", func() -> void: reveal_photo(id), "Reveal"))
	row.add_child(_action("act_delete", "Delete", func() -> void: ask_delete(id), "Delete"))
	row.add_child(_send_or_sent(id))
	return row


## "Send to {elder_name}" (the config kit's button), or once sent, a small "Sent" in the caption hand.
func _send_or_sent(id: String) -> Control:
	if game == null or game.letters == null:
		return Control.new()
	if game.letters.is_sent(id):
		var mark := _label("Sent")
		mark.name = "SentMark"
		mark.tooltip_text = "Sent to %s" % game.letters.name_of(game.elder_choice())
		mark.mouse_filter = Control.MOUSE_FILTER_PASS
		_caption_styled(mark, "caption")
		mark.add_theme_color_override("font_color", book_kit.colour("caption"))
		mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		return mark
	var send := _button("Send to %s" % game.letters.name_of(game.elder_choice()), func() -> void: send_photo(id), "Send")
	send.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return send


## A picture under one of the kit's mounts: the photo inset photo_inset_pt (one more on the
## shadow's sides), the mount over it. Drawn untilted (a tilted photo has stepped edges).
func _mounted(tex: Texture2D, piece: String) -> Control:
	var inset := _lay("photo_inset_pt") * _k
	var pic_size := Vector2(tex.get_size()) if tex != null else Vector2(160, 72) * _k
	var holder := Control.new()
	holder.custom_minimum_size = (pic_size + Vector2(inset * 2.0 + _k, inset * 2.0 + _k)).round()
	holder.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var pic := TextureRect.new()
	pic.texture = tex
	pic.position = Vector2(inset, inset)
	pic.size = pic_size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(pic)
	var mount := Panel.new()
	mount.set_anchors_preset(Control.PRESET_FULL_RECT)
	mount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mount.add_theme_stylebox_override("panel", book_kit.style(piece))
	holder.add_child(mount)
	holder.mouse_entered.connect(func() -> void: mount.add_theme_stylebox_override("panel", book_kit.style(piece, "hover")))
	holder.mouse_exited.connect(func() -> void: mount.add_theme_stylebox_override("panel", book_kit.style(piece)))
	holder.set_meta("picture", pic)
	return holder


func _thumb(id: String, px: Vector2i) -> Texture2D:
	if _thumbs.has(id):
		return _thumbs[id]
	var img := album.image(id)
	if img == null:
		return null
	var scale := minf(float(px.x) / img.get_width(), float(px.y) / img.get_height())
	img.resize(maxi(1, int(img.get_width() * scale)), maxi(1, int(img.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	_thumbs[id] = ImageTexture.create_from_image(img)
	return _thumbs[id]


func _photo(id: String) -> Dictionary:
	for p in album.photos():
		if String(p["id"]) == id:
			return p
	return {}


func _species_name(id: String) -> String:
	if sightings != null and sightings.seen.has(id):
		return String(sightings.seen[id]["name"])
	return id.replace("_", " ")


# Letters --------------------------------------------------------------------------------------

func _build_letters() -> void:
	var kept := _letters()
	turned_to[LETTERS] = clampi(turned_to[LETTERS], 0, _views(LETTERS) - 1)
	var per := int(tuning["letters_per_page"])
	var pages := _pages(LETTERS, kept.size(), per)
	if kept.is_empty():
		pages[0].add_child(_empty_note("Letters are kept here."))
		return
	var first := turned_to[LETTERS] * per * pages.size()
	for p in pages.size():
		pages[p].name = "LetterPage_%d" % p
		for i in range(first + p * per, mini(first + (p + 1) * per, kept.size())):
			pages[p].add_child(_letter_card(kept[i]))


## One letter on the kit's note card, in the caption hand: the elder's portrait (a sprite slot, issue 241;
## nothing while it is missing), the day it came and the photo it answers, the body, the sign-off and name.
func _letter_card(letter: Dictionary) -> Control:
	var centre := CenterContainer.new()
	centre.name = "Letter_" + String(letter["id"])
	centre.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var card := PanelContainer.new()
	var style := book_kit.style("note")
	var pad := _lay("note_pad_pt") * _k
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad * 0.75
	style.content_margin_bottom = pad * 0.75
	card.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", int(_lay("caption_gap_pt") * _k * 2.0))
	var width := float(tuning["letter_width_pt"]) * _k
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", int(8 * _k))
	var portrait := _portrait(String(letter.get("elder", "")))
	if portrait != null:
		head.add_child(portrait)
	var when := VBoxContainer.new()
	when.size_flags_vertical = Control.SIZE_SHRINK_END
	var came := _label(SceneBookWindow.day_text(String(letter["day"])))
	_caption_styled(came, "caption")
	came.add_theme_color_override("font_color", book_kit.colour("caption"))
	when.add_child(came)
	if String(letter.get("photo_date", "")) != "":
		var about := _label("About your photo of %s, %s" % [SceneBookWindow.day_text(String(letter["photo_date"])), String(letter["photo_time"])])
		about.name = "AboutPhoto"
		_caption_styled(about, "caption")
		about.add_theme_color_override("font_color", book_kit.colour("ink_soft"))
		when.add_child(about)
	head.add_child(when)
	column.add_child(head)
	var body := _label(String(letter["body"]))
	body.name = "Body"
	_caption_styled(body, "note")
	body.add_theme_color_override("font_color", book_kit.colour("on_note"))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.custom_minimum_size.x = width
	column.add_child(body)
	for line in [String(letter.get("sign_off", "")), String(letter.get("name", ""))]:
		var signed := _label(line)
		_caption_styled(signed, "note")
		signed.add_theme_color_override("font_color", book_kit.colour("on_note"))
		column.add_child(signed)
	card.add_child(column)
	centre.add_child(card)
	return centre


## The elder's portrait from its slot (the companion's elder/elders.json `portrait`), at one sheet px per point on
## whole device px; null while the bench has not delivered it.
func _portrait(elder_id: String) -> Control:
	if game == null or game.letters == null:
		return null
	# In the player's skin tone (issue 199), like the welcome's.
	var tex := game.elder_portrait(elder_id)
	if tex == null:
		return null
	var pic := TextureRect.new()
	pic.name = "Portrait"
	pic.texture = tex
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(float(tuning["portrait_pt"][0]), float(tuning["portrait_pt"][1])) * maxf(1.0, roundf(_k))
	return pic


# Field guide ----------------------------------------------------------------------------------

func _build_guide() -> void:
	var entries := sightings.entries() if sightings != null else []
	turned_to[FIELD_GUIDE] = clampi(turned_to[FIELD_GUIDE], 0, _views(FIELD_GUIDE) - 1)
	var per := int(tuning["entries_per_page"])
	var pages := _pages(FIELD_GUIDE, entries.size(), per)
	if entries.is_empty():
		pages[0].add_child(_empty_note("The animals that visit the scene are noted here, with when you first and last saw them."))
		return
	var first := turned_to[FIELD_GUIDE] * per * pages.size()
	for p in pages.size():
		pages[p].name = "GuidePage_%d" % p
		for i in range(first + p * per, mini(first + (p + 1) * per, entries.size())):
			pages[p].add_child(_guide_row(entries[i]))


## One entry card: the picture in its well (whole art px), the name, first and last seen.
func _guide_row(entry: Dictionary) -> Control:
	var card := Panel.new()
	card.name = "Seen_" + String(entry["key"])
	card.add_theme_stylebox_override("panel", book_kit.style("entry"))
	card.custom_minimum_size = Vector2(0, book_kit.size_pt("entry").y * _k)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var slot: Array = book_kit.meta["layout"]["entry_slot_pt"]
	var well := Rect2(Vector2(float(slot[0]), float(slot[1])) * _k, Vector2(float(slot[2]), float(slot[2])) * _k)
	var tex := SceneSightings.picture(String(entry.get("sheet", "")))
	var pic := Control.new()
	pic.name = "Picture"
	pic.position = well.position
	pic.size = well.size
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pic.clip_contents = true
	pic.draw.connect(func() -> void:
		if tex == null:
			return
		var drawn := SceneBookWindow.whole_px_size(tex.get_size(), well.size)
		pic.draw_texture_rect(tex, Rect2(((well.size - drawn) / 2.0).round(), drawn), false))
	card.add_child(pic)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", int(1 * _k))
	words.set_anchors_preset(Control.PRESET_FULL_RECT)
	words.offset_left = well.end.x + 10.0 * _k
	words.offset_right = -12.0 * _k
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_label := _label(SceneBookWindow.sentence_case(String(entry["name"])))
	_styled(name_label, "label")
	name_label.add_theme_color_override("font_color", book_kit.colour("heading"))
	words.add_child(name_label)
	# A page is half the window: first and last seen take a line each rather than trimming.
	for line in ["First seen %s" % _when(float(entry["first"])), "Last seen %s" % _when(float(entry["last"]))]:
		var seen_line := _note(line)
		seen_line.autowrap_mode = TextServer.AUTOWRAP_OFF
		seen_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		words.add_child(seen_line)
	card.add_child(words)
	return card


## A sheet frame drawn at a whole number of device px per sheet px (or ½) that fits `box`.
static func whole_px_size(frame: Vector2, box: Vector2) -> Vector2:
	var fit := minf(box.x / frame.x, box.y / frame.y)
	var s := floorf(fit) if fit >= 1.0 else 0.5
	return frame * s


func _when(unix: float) -> String:
	var d := game.clock.local(unix)
	var date := "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]
	var time := "%02d:%02d" % [int(d["hour"]), int(d["minute"])]
	if date == game.clock.date_key():
		return "today, %s" % time
	return SceneBookWindow.day_text(date)


## "2026-10-18" -> "18 Oct 2026".
static func day_text(date: String) -> String:
	var parts := date.split("-")
	if parts.size() != 3:
		return date
	return "%d %s %s" % [int(parts[2]), MONTHS[clampi(int(parts[1]) - 1, 0, 11)], parts[0]]


static func sentence_case(text: String) -> String:
	return text if text == "" else text.substr(0, 1).to_upper() + text.substr(1)


# Shared pieces --------------------------------------------------------------------------------

func _header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(6 * _k))
	var heading := _label("Field journal")
	heading.name = "Title"
	_styled(heading, "heading")
	heading.add_theme_font_size_override("font_size", int(round(float(tuning["title_pt"]) * _k)))
	heading.add_theme_color_override("font_color", book_kit.colour("on_cover"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	var close := _action("act_close", "Close", close_book, "Close")
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(close)
	return row


## The empty page's note card, in the caption hand.
func _empty_note(text: String) -> Control:
	var centre := CenterContainer.new()
	centre.name = "EmptyNote"
	centre.custom_minimum_size.y = 120 * _k
	var card := PanelContainer.new()
	var style := book_kit.style("note")
	var pad := _lay("note_pad_pt") * _k
	style.content_margin_left = pad
	style.content_margin_right = pad
	style.content_margin_top = pad * 0.75
	style.content_margin_bottom = pad * 0.75
	card.add_theme_stylebox_override("panel", style)
	var label := _label(text)
	_caption_styled(label, "note")
	label.add_theme_color_override("font_color", book_kit.colour("on_note"))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.custom_minimum_size.x = float(tuning["note_width_pt"]) * _k
	card.add_child(label)
	centre.add_child(card)
	return centre


## The config kit's theme with the book's ribbons for the parts (each part draws its own pages).
func _theme() -> Theme:
	var t := SceneConfigWindow.field_theme(kit, _k)
	t.set_stylebox("panel", "TabContainer", StyleBoxEmpty.new())
	var pad := _lay("ribbon_pad_pt")
	for pair in [["tab_selected", "selected"], ["tab_unselected", "normal"], ["tab_hovered", "hover"]]:
		var tab := SceneConfigWindow.pad_pt(_k, book_kit.style("ribbon", pair[1]), pad, 3)
		tab.expand_margin_bottom = _lay("ribbon_overlap_pt") * _k
		t.set_stylebox(pair[0], "TabContainer", tab)
	t.set_color("font_selected_color", "TabContainer", book_kit.colour("on_ribbon_selected"))
	t.set_color("font_unselected_color", "TabContainer", book_kit.colour("on_ribbon"))
	t.set_color("font_hovered_color", "TabContainer", book_kit.colour("on_ribbon"))
	t.set_constant("tab_separation", "TabContainer", int(_lay("ribbon_gap_pt") * _k))
	return t


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _styled(label: Label, style_name: String) -> void:
	var size_pt := kit.font_size_pt(style_name)
	if style_name == "small":
		size_pt = maxf(size_pt, float(game.balance.data["scene_config"]["min_small_pt"]))
	label.add_theme_font_override("font", kit.font(style_name))
	label.add_theme_font_size_override("font_size", int(round(size_pt * _k)))


func _caption_styled(label: Label, style_name: String) -> void:
	label.add_theme_font_override("font", book_kit.caption_font(style_name))
	label.add_theme_font_size_override("font_size", int(round(book_kit.caption_size_pt(style_name) * _k)))


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _note(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", book_kit.colour("ink_soft"))
	_styled(label, "small")
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


## One of the kit's wooden action buttons (fixed size, its own states), with a tooltip.
func _action(piece: String, tip: String, call: Callable, node_name: String) -> TextureButton:
	var button := TextureButton.new()
	button.name = node_name
	button.tooltip_text = tip
	button.focus_mode = Control.FOCUS_NONE
	button.texture_normal = book_kit.texture(piece, "normal")
	button.texture_hover = book_kit.texture(piece, "hover")
	button.texture_pressed = book_kit.texture(piece, "pressed")
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(call)
	return button


func _button(text: String, call: Callable, node_name: String) -> Button:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = book_kit.size_pt("act_close").y * _k
	button.pressed.connect(call)
	return button


func _on_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		if enlarged != "":
			back_to_album()
		else:
			close_book()


func _pt(key: String) -> float:
	return float(tuning[key]) * _k


## A number from the book kit's layout (points).
func _lay(key: String) -> float:
	return float(book_kit.meta["layout"][key])
