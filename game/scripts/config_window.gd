class_name ConfigWindow
extends Window

## Config: the player's settings, opened by home's sign (and once by itself, on the first
## run). Tabs: General (scale, on top, day phases, quit), Avatar (the avatar worn,
## playing its front idle; the six whole avatars are no longer chosen here, issue 202: the look is
## chosen in the scene's Config), Islands (every island in the
## collection, on or off; off is what an island's ✕ does), Journal (every bird photographed
## and fish caught, with the days: a list to look at, never a checklist to finish). A
## Triggers tab comes later.
##
## The one window that may take keyboard focus (SPEC §2.1, the exception the human made in
## Skypatch issue 30): it has text to type into,
## and it only ever opens because the player asked for it, or on the very first run.
## Plain controls like the debug panel, coloured from the palette.

signal closed

const GENERAL := 0
const AVATAR := 1
const ISLANDS := 2
const JOURNAL := 3
const TAB_NAMES: Array[String] = ["General", "Avatar", "Islands", "Journal"]
const MONTHS: Array[String] = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var game: Game
var tabs := TabContainer.new()
## island id -> CheckButton
var island_switches := {}
var _k := 1
var _colors := {}
var _previews: Array[CreatureSprite] = []
var _islands_box := VBoxContainer.new()
var _journal_box := VBoxContainer.new()
## "birds/<id>" or "fish/<id>" -> Texture2D: the journal's pictures
var _journal_icons := {}
var _scale_label := Label.new()
var _on_top := CheckButton.new()
var _over_full_screen := CheckButton.new()
var _desktop_flights := CheckButton.new()
var _pointer: PointerHandler


func setup(owner_game: Game) -> void:
	game = owner_game
	var tuning: Dictionary = game.balance.data["config"]
	for key in tuning["colors"]:
		_colors[key] = Color(String(tuning["colors"][key]))
	_k = maxi(1, roundi(DisplayServer.screen_get_max_scale()))
	title = "VibeNature · config"
	visible = false
	borderless = true
	unresizable = true
	transparent = false
	transparent_bg = false
	unfocusable = false
	size = AssetLibrary.vec2i(tuning["size_px"]) * _k
	content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	theme = _theme(int(tuning["font_px"]) * _k)

	var background := Panel.new()
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 10 * _k
	box.offset_top = 8 * _k
	box.offset_right = -10 * _k
	box.offset_bottom = -10 * _k
	box.add_theme_constant_override("separation", 6 * _k)
	add_child(box)
	var top := HBoxContainer.new()
	var heading := Label.new()
	heading.text = "Config"
	heading.add_theme_color_override("font_color", _colors["accent"])
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	top.add_child(_button("Close", close_config))
	box.add_child(top)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.focus_mode = Control.FOCUS_NONE
	box.add_child(tabs)
	_add_tab(TAB_NAMES[GENERAL], _general())
	_add_tab(TAB_NAMES[AVATAR], _avatars(int(tuning["avatar_columns"]), int(tuning["avatar_preview_scale"])))
	_islands_box.add_theme_constant_override("separation", 4 * _k)
	_add_tab(TAB_NAMES[ISLANDS], _islands_box)
	_journal_box.add_theme_constant_override("separation", 4 * _k)
	_add_tab(TAB_NAMES[JOURNAL], _journal_box)
	_pointer = PointerHandler.new(self, float(game.balance.data["input"]["drag_threshold_px"]))
	window_input.connect(_on_key)


## Shows Config on `tab`, beside home, and takes keyboard focus.
func open(tab: int) -> void:
	tabs.current_tab = tab
	refresh()
	var anchor: Window = game.scene if game.scene_mode else game.get_window()
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen(anchor.get_window_id()))
	var at := Vector2i(anchor.position.x + anchor.size.x - size.x, anchor.position.y - size.y - 8 * _k)
	if at.y < screen.position.y:
		at.y = anchor.position.y + anchor.size.y - size.y
	at.x = clampi(at.x, screen.position.x, maxi(screen.position.x, screen.end.x - size.x))
	at.y = clampi(at.y, screen.position.y, maxi(screen.position.y, screen.end.y - size.y))
	position = at
	for preview in _previews:
		preview.play("idle")
	show()
	grab_focus()


func close_config() -> void:
	if not visible:
		return
	for preview in _previews:
		preview.show_frame(0)
	hide()
	closed.emit()


## Brings every switch and the selection up to date (an ✕ may have closed an island).
func refresh() -> void:
	_scale_label.text = "Island size: %s" % game.scale_name(game.settings.art_scale(game.balance.data["display"]["art_scales"]))
	_on_top.set_pressed_no_signal(bool(game.settings.data["on_top"]))
	_over_full_screen.set_pressed_no_signal(bool(game.settings.data["show_over_full_screen"]))
	_desktop_flights.set_pressed_no_signal(bool(game.settings.data["desktop_flights"]))
	_build_islands()
	_build_journal()


func _add_tab(tab_name: String, content: Control) -> void:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	tabs.add_child(scroll)


func _general() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6 * _k)
	var scale_row := HBoxContainer.new()
	_scale_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scale_row.add_child(_scale_label)
	scale_row.add_child(_button("Smaller", func() -> void: game.change_scale(-1)))
	scale_row.add_child(_button("Larger", func() -> void: game.change_scale(1)))
	box.add_child(scale_row)
	_on_top.text = "Keep VibeNature above other windows"
	_on_top.focus_mode = Control.FOCUS_NONE
	_on_top.toggled.connect(func(on: bool) -> void: game.set_all_on_top(on))
	box.add_child(_on_top)
	_over_full_screen.text = "Show over full-screen apps"
	_over_full_screen.focus_mode = Control.FOCUS_NONE
	_over_full_screen.toggled.connect(func(on: bool) -> void: game.set_show_over_full_screen(on))
	box.add_child(_over_full_screen)
	_desktop_flights.text = "Birds sometimes fly out over the desktop"
	_desktop_flights.focus_mode = Control.FOCUS_NONE
	_desktop_flights.toggled.connect(func(on: bool) -> void: game.set_desktop_flights(on))
	box.add_child(_desktop_flights)

	box.add_child(_heading("Day phases"))
	var phases := GridContainer.new()
	phases.columns = 2
	var phase_data: Dictionary = game.settings.data["day_phases"]
	for phase in phase_data:
		phases.add_child(_label(String(phase).replace("_", " ")))
		phases.add_child(_time_edit(String(phase_data[phase]), func(value: String) -> void: _set_phase(String(phase), value)))
	box.add_child(phases)
	var note := _label("New times count from the next time VibeNature starts.")
	note.add_theme_color_override("font_color", _colors["dim_text"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(note)

	box.add_child(_heading("Close up"))
	box.add_child(_button("Quit VibeNature (saves first)", game.quit))
	return box


## The avatar worn, playing its front idle. Not a choice any more (issue 202): the island game wears
## the whole avatar for the body of the look chosen in the scene's Config.
func _avatars(_columns: int, preview_scale: int) -> Control:
	var box := VBoxContainer.new()
	var placeholders: Dictionary = game.balance.data["placeholders"]
	var id := Avatar.resolve_id(String(game.settings.data["avatar_id"]), Avatar.choices(placeholders))
	var def := Avatar.load_def(id, placeholders, game.idle_fps_max)
	var sheet: Dictionary = def.layers["front"]
	var frame: Vector2i = sheet["frame_size"]
	var px := preview_scale * _k
	var holder := Control.new()
	holder.name = "worn_avatar"
	holder.custom_minimum_size = Vector2(frame * px) + Vector2(8, 8) * _k
	var preview := CreatureSprite.new(def)
	preview.set_layer("front")
	preview.scale = Vector2(px, px)
	preview.position = Vector2(sheet["anchor"] * px) + Vector2(4, 4) * _k
	preview.show_frame(0)
	holder.add_child(preview)
	_previews.append(preview)
	box.add_child(holder)
	var note := _label("Choose how you look in the living scene's settings.")
	note.add_theme_color_override("font_color", _colors["dim_text"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	box.add_child(note)
	return box


## "b_slender_p2" -> "Slender 2".
static func avatar_name(id: String) -> String:
	var parts := id.split("_")
	if parts.size() < 3:
		return id
	return "%s %s" % [parts[1].capitalize(), parts[-1].trim_prefix("p")]


func _build_islands() -> void:
	for child in _islands_box.get_children():
		_islands_box.remove_child(child)
		child.queue_free()
	island_switches.clear()
	var note := _label("Off puts an island away, as its red square does. It keeps everything it had.")
	note.add_theme_color_override("font_color", _colors["dim_text"])
	note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_islands_box.add_child(note)
	var out := game.patch_ids_out()
	var ids: Array = game.collection.owned.keys()
	ids.sort()
	for id in ids:
		var switch := CheckButton.new()
		switch.name = String(id)
		switch.focus_mode = Control.FOCUS_NONE
		switch.text = game.content.patch_name(String(id))
		if not out.has(id):
			switch.text += "  (not out today)"
		switch.button_pressed = not game.settings.is_dismissed(String(id))
		switch.toggled.connect(func(on: bool) -> void: game.set_island_dismissed(String(id), not on))
		island_switches[String(id)] = switch
		_islands_box.add_child(switch)


## The life list of birds and fish, most recently seen first: a picture, the name, how many
## times, and the first and last day. Nothing to complete, nothing counted against.
func _build_journal() -> void:
	for child in _journal_box.get_children():
		_journal_box.remove_child(child)
		child.queue_free()
	for section in [["birds", "Birds photographed", "No photos yet. A bird that perches can be photographed with the camera."],
			["fish", "Fish caught", "No fish yet. Bait the line at the fishing hole and wait for a bite."],
			["night", "Night visitors", ""]]:
		var category := String(section[0])
		var entries := game.journal.entries(category)
		if entries.is_empty() and String(section[2]) == "":
			continue
		_journal_box.add_child(_heading(String(section[1])))
		if entries.is_empty():
			var note := _label(String(section[2]))
			note.add_theme_color_override("font_color", _colors["dim_text"])
			note.autowrap_mode = TextServer.AUTOWRAP_WORD
			_journal_box.add_child(note)
			continue
		for entry in entries:
			_journal_box.add_child(_journal_row(category, entry))


func _journal_row(category: String, entry: Dictionary) -> Control:
	var id := String(entry["id"])
	var row := HBoxContainer.new()
	row.name = "%s_%s" % [category, id]
	row.add_theme_constant_override("separation", 6 * _k)
	var picture := TextureRect.new()
	picture.texture = _journal_icon(category, id)
	picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var px := int(game.balance.data["config"]["journal_icon_scale"]) * _k
	picture.custom_minimum_size = picture.texture.get_size() * px
	var frame := CenterContainer.new()
	frame.custom_minimum_size = Vector2.ONE * int(game.balance.data["config"]["journal_icon_box_px"]) * px
	frame.add_child(picture)
	row.add_child(frame)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	var count := int(entry["count"])
	text.add_child(_label(game.content.species_name(category, id) + ("  ×%d" % count if count > 1 else "")))
	var days := _label(ConfigWindow.seen_text(String(entry["first"]), String(entry["last"])))
	days.add_theme_color_override("font_color", _colors["dim_text"])
	text.add_child(days)
	row.add_child(text)
	return row


func _journal_icon(category: String, id: String) -> Texture2D:
	var key := "%s/%s" % [category, id]
	if not _journal_icons.has(key):
		if category == "birds":
			_journal_icons[key] = ImageTexture.create_from_image(Polaroid.bird_picture(game.birds.def_for(id)))
		elif category == "night":
			var def := CreatureDef.load_creature("fauna", id, game.balance.data["placeholders"]["small_creature"],
					game.idle_fps_max, game.content.color_of("night", id))
			_journal_icons[key] = ImageTexture.create_from_image(Polaroid.bird_picture(def))
		else:
			_journal_icons[key] = game.item_texture({"kind": "fish", "id": id})
	return _journal_icons[key]


## "First seen Oct 15 · last Oct 16"; one day when they are the same; "" for old saves.
static func seen_text(first: String, last: String) -> String:
	if first == "":
		return ""
	if last == "" or last == first:
		return "Seen %s" % ConfigWindow.day_name(first)
	return "First seen %s · last %s" % [ConfigWindow.day_name(first), ConfigWindow.day_name(last)]


## "2026-10-15" -> "Oct 15".
static func day_name(day_key: String) -> String:
	var parts := day_key.split("-")
	if parts.size() != 3 or not parts[1].is_valid_int() or int(parts[1]) not in range(1, 13):
		return day_key
	return "%s %d" % [MONTHS[int(parts[1]) - 1], int(parts[2])]


func _set_phase(phase: String, value: String) -> void:
	game.settings.data["day_phases"][phase] = value
	game.settings.save()


## A HH:MM field. A valid time is saved when the player presses Return or leaves the
## field; anything else goes back to what was there.
func _time_edit(value: String, on_change: Callable) -> LineEdit:
	var edit := LineEdit.new()
	edit.text = value
	edit.max_length = 5
	edit.custom_minimum_size.x = 64 * _k
	edit.set_meta("saved", value)
	var commit := func() -> void:
		var text := edit.text.strip_edges()
		if ConfigWindow.valid_time(text) and text != String(edit.get_meta("saved")):
			edit.set_meta("saved", text)
			on_change.call(text)
		edit.text = String(edit.get_meta("saved"))
	edit.text_submitted.connect(func(_text: String) -> void: commit.call())
	edit.focus_exited.connect(commit)
	return edit


static func valid_time(text: String) -> bool:
	var parts := text.split(":")
	if parts.size() != 2 or parts[0].length() != 2 or parts[1].length() != 2:
		return false
	if not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return false
	return int(parts[0]) in range(24) and int(parts[1]) in range(60)


func _heading(text: String) -> Label:
	var label := _label(text)
	label.add_theme_color_override("font_color", _colors["accent"])
	return label


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _button(text: String, call: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(call)
	return button


func _on_key(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		close_config()


func _theme(font_px: int) -> Theme:
	var t := Theme.new()
	t.default_font_size = font_px
	t.set_stylebox("panel", "Panel", _box(_colors["background"]))
	t.set_stylebox("panel", "TabContainer", _box(_colors["panel"]))
	t.set_stylebox("tab_selected", "TabContainer", _box(_colors["panel"], _colors["accent"]))
	t.set_stylebox("tab_unselected", "TabContainer", _box(_colors["background"]))
	t.set_stylebox("tab_hovered", "TabContainer", _box(_colors["hover"]))
	t.set_color("font_selected_color", "TabContainer", _colors["accent"])
	t.set_color("font_unselected_color", "TabContainer", _colors["dim_text"])
	t.set_color("font_hovered_color", "TabContainer", _colors["text"])
	for kind in ["Label", "Button", "CheckBox", "CheckButton", "LineEdit"]:
		t.set_color("font_color", kind, _colors["text"])
	t.set_stylebox("normal", "Button", _box(_colors["button"]))
	t.set_stylebox("hover", "Button", _box(_colors["hover"]))
	t.set_stylebox("pressed", "Button", _box(_colors["button"], _colors["accent"]))
	t.set_stylebox("hover_pressed", "Button", _box(_colors["hover"], _colors["accent"]))
	t.set_color("font_hover_color", "Button", _colors["text"])
	t.set_color("font_pressed_color", "Button", _colors["accent"])
	t.set_stylebox("normal", "LineEdit", _box(_colors["background"]))
	t.set_stylebox("focus", "LineEdit", _box(_colors["background"], _colors["accent"]))
	return t


func _box(fill: Color, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.set_content_margin_all(4 * _k)
	if border.a > 0.0:
		box.border_color = border
		box.set_border_width_all(2 * _k)
	return box
