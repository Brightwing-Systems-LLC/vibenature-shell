class_name SceneScreenPicker
extends Control

## Config's "Show the scene on" (Skypatch issue 174): a box
## per connected screen, laid out as the screens are arranged (as macOS's Displays settings), the
## scene's screen selected with a marker in its bottom-right corner, where the scene sits. Hover
## shows which box the pointer is on; a click emits `picked`.

signal picked(index: int)

var kit: SceneConfigKit
var screens: Array = []
var selected := -1
var hovered := -1
## Points to device px (Config's scale).
var k := 1.0
var gap_pt := 6.0
var caption: Label


func setup(owner_kit: SceneConfigKit, ui_scale: float, height_pt: float, gap: float) -> void:
	kit = owner_kit
	k = ui_scale
	gap_pt = gap
	custom_minimum_size = Vector2(0, height_pt * k)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	mouse_exited.connect(func() -> void: _hover(-1))


func set_screens(new_screens: Array, new_selected: int) -> void:
	screens = new_screens
	selected = new_selected
	if hovered >= screens.size():
		hovered = -1
	_update_caption()
	queue_redraw()


## Each screen's own rect in the picker (local px); its tile is this grown by the kit's rim.
func boxes() -> Array[Rect2]:
	var rim := _rim()
	var laid := SceneScreens.layout(screens, size - Vector2(rim, rim) * 2.0, gap_pt * k + rim * 2.0)
	for i in laid.size():
		laid[i].position += Vector2(rim, rim)
	return laid


func _rim() -> float:
	return kit.layout("screen_rim_pt") * k if kit != null else 0.0


## The box under `at` (local px), or -1.
func box_at(at: Vector2) -> int:
	var all := boxes()
	for i in all.size():
		if all[i].grow(_rim()).has_point(at):
			return i
	return -1


## Picks a box as a click would: selects it and emits `picked`.
func pick(index: int) -> void:
	if index < 0 or index >= screens.size():
		return
	selected = index
	_update_caption()
	queue_redraw()
	picked.emit(index)


func _gui_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null:
		_hover(box_at(motion.position))
		return
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		var index := box_at(button.position)
		if index >= 0:
			pick(index)
			accept_event()


func _hover(index: int) -> void:
	if index == hovered:
		return
	hovered = index
	_update_caption()
	queue_redraw()


func _update_caption() -> void:
	if caption == null:
		return
	var index := hovered if hovered >= 0 else selected
	if index < 0 or index >= screens.size():
		caption.text = ""
		return
	var r: Rect2i = screens[index]["rect"]
	var words := "Screen %d · %d × %d" % [index + 1, r.size.x, r.size.y]
	if bool(screens[index].get("primary", false)):
		words += " · main"
	if index == selected:
		words += " · the scene is here"
	elif index == hovered:
		words += " · click to move the scene here"
	caption.text = words


func _draw() -> void:
	if kit == null:
		return
	var all := boxes()
	var rim := _rim()
	var m := kit.margin("screen_tile")
	for i in all.size():
		var state := "selected" if i == selected else ("hover" if i == hovered else "normal")
		var tile := Rect2(all[i].position.round(), all[i].size.round()).grow(rim)
		draw_style_box(kit.style("screen_tile", state), tile)
		if bool(screens[i].get("primary", false)):
			# The main screen carries the menu bar, as in macOS's Displays settings.
			draw_rect(Rect2(tile.position.x + m.x, tile.position.y + m.y, tile.size.x - m.x - m.z, float(kit.d) * 2.0),
					Color(kit.colour("on_screen"), 0.7))
		if i == selected:
			var marker := kit.texture("marker")
			var inset := Vector2(m.z, m.w) + Vector2.ONE * kit.layout("marker_inset_pt") * kit.d
			draw_texture(marker, (tile.end - marker.get_size() - inset).round())
