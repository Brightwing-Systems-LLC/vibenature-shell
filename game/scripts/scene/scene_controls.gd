class_name SceneControls
extends Node2D

## The living scene's control strip (Skypatch issue 169),
## in the scene window's top-right corner: photo · book · − · + · settings · quit. The two
## magnifiers step the scene's size (issue 222); each is greyed out (`disabled`) and does nothing at
## its end of the sizes. With
## `always_shown` (the human's choice: the hover tab was too subtle to find) the strip is always out.
## Without it, only the wooden tab shows at rest, at `tab_alpha`; the pointer over it opens the
## strip, which fades out a little after the pointer leaves (`linger_sec`, `fade_out_sec`). Timings
## are `scene.controls` in balance.json; sizes come from the bench's meta.json.
##
## Only the tab (closed) or the strip (open) catches the mouse: it is the scene's `controls`
## hit region, and everything else stays click-through. A click never takes focus: the window
## stays unfocusable and the buttons are drawn here, not Controls.
##
## The art is the field kit (Skypatch issue 170):
## `assets/ui/scene_controls` (buttons × normal/hover/pressed/disabled) and `assets/ui/scene_controls_tab`,
## each in a 1x and a 2x drawing. The density is picked by the screen's scale and drawn at one
## sheet px per device px, never resampled.

signal photo_requested
signal book_requested
## −1 for one size smaller, +1 for one larger.
signal zoom_requested(delta: int)
signal settings_requested
signal quit_requested

const IDS: Array[String] = ["photo", "book", "zoom_out", "zoom_in", "settings", "quit"]
const REGION := "controls"
const BUTTONS_DIR := "res://assets/ui/scene_controls"
const TAB_DIR := "res://assets/ui/scene_controls_tab"

var tuning: Dictionary = {}
## Window units per point (the screen's scale, whatever the scene's size).
var ui_scale := 1.0
## The window's size in window units.
var window_size := Vector2.ZERO
## The scene is at its smallest size (− greyed out) or its largest (+ greyed out).
var smallest := false
var largest := true
## The scene in the bottom-left corner (issue 422): the strip and its tab in the window's top-left, toward
## the screen's edge, as they are top-right in the bottom-right corner.
var left := false
## How far below the window's top the art starts (UI points): an open top's grown margin dissolves into the
## desktop, so the strip and its tab sit below it, on the art (issue 424).
var top_inset_pt := 0.0
## The strip is out (else only the tab).
var is_open := false
## The strip's opacity, 0..1.
var alpha := 0.0
## Seconds since the pointer left the strip while it is open.
var away := 0.0
var hovered := ""
var tab_hovered := false
## The button drawn pressed, for `pressed_sec` after a click.
var pressed := ""
## Where the pointer is from (window units), or the screen's real pointer when not set: tests and
## snapshots set it; the game reads the mouse.
var pointer_source: Callable
## The scene's hit regions, kept up to date as the strip opens and closes.
var regions: SceneHitRegions
## "1x" or "2x": which drawing of the art is used.
var density := "1x"
var buttons_meta: Dictionary = {}
var tab_meta: Dictionary = {}
var _buttons: Texture2D
var _tab: Texture2D
var _pressed_left := 0.0
var _window: Window


func setup(controls_tuning: Dictionary, window: Window, hit: SceneHitRegions, ui: float, at_smallest: bool = false, at_largest: bool = true) -> void:
	tuning = controls_tuning
	_window = window
	regions = hit
	ui_scale = ui
	smallest = at_smallest
	largest = at_largest
	window_size = Vector2(window.size)
	name = "Controls"
	density = SceneControls.density_for(ui_scale)
	buttons_meta = SceneControls.read_meta(BUTTONS_DIR)
	tab_meta = SceneControls.read_meta(TAB_DIR)
	_buttons = load(BUTTONS_DIR.path_join(String(buttons_meta["densities"][density]["file"])))
	_tab = load(TAB_DIR.path_join(String(tab_meta["densities"][density]["file"])))
	# Drawn in device px: one sheet px each, so the art is never resampled.
	scale = Vector2.ONE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 1
	if always_shown():
		open_now(true)
	else:
		_apply_region()


func always_shown() -> bool:
	return bool(tuning.get("always_shown", false))


## @1x on a 1x screen, @2x on a screen of scale 2 or more.
static func density_for(screen_scale: float) -> String:
	return "2x" if screen_scale >= 2.0 else "1x"


static func read_meta(dir: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("meta.json")))
	return parsed if parsed is Dictionary else {}


func _button_pt() -> Vector2:
	return Vector2(float(buttons_meta["button_pt"][0]), float(buttons_meta["button_pt"][1]))


## The strip's rect in points (inside the window, at its top-right corner).
func strip_rect() -> Rect2:
	var button := _button_pt()
	var gap := float(buttons_meta["gap_pt"])
	var w := IDS.size() * button.x + (IDS.size() - 1) * gap
	var inset := Vector2(float(tuning["inset_pt"][0]), float(tuning["inset_pt"][1]))
	if left:
		return Rect2(Vector2(inset.x, inset.y + top_inset_pt), Vector2(w, button.y))
	var right := window_size.x / ui_scale - inset.x
	return Rect2(Vector2(right - w, inset.y + top_inset_pt), Vector2(w, button.y))


## The tab's drawn rect in points: hanging from the art's top edge, flush with the strip's right end.
func tab_rect() -> Rect2:
	var size := Vector2(float(tab_meta["tab_pt"][0]), float(tab_meta["tab_pt"][1]))
	if left:
		return Rect2(Vector2(strip_rect().position.x, top_inset_pt), size)
	return Rect2(Vector2(strip_rect().end.x - size.x, top_inset_pt), size)


## The tab's hover rect in points: the drawn tab grown by `tab_hit_pad_pt`, so it is easy to find.
func tab_hit_rect() -> Rect2:
	return tab_rect().grow(float(tuning["tab_hit_pad_pt"]))


func button_rect(id: String) -> Rect2:
	var i := IDS.find(id)
	var strip := strip_rect()
	var button := _button_pt()
	return Rect2(strip.position + Vector2(i * (button.x + float(buttons_meta["gap_pt"])), 0.0), button)


## The button under `point` (points), or "". A greyed-out magnifier is not a button.
func button_at(point: Vector2) -> String:
	if not is_open:
		return ""
	for id in IDS:
		if button_rect(id).has_point(point):
			return "" if is_disabled(id) else id
	return ""


## − at the smallest size, + at the largest.
func is_disabled(id: String) -> bool:
	return (id == "zoom_out" and smallest) or (id == "zoom_in" and largest)


## What catches the mouse now, in window units: the strip while it is open, else the tab.
func hit_rect() -> Rect2:
	var r := strip_rect() if is_open else tab_hit_rect()
	return Rect2(r.position * ui_scale, r.size * ui_scale)


## The scene changed size in place (issue 307): the strip stays in the new top-right corner, at the
## screen's scale, with − or + greyed out at the ends.
func resized(new_window_size: Vector2, at_smallest: bool, at_largest: bool) -> void:
	window_size = new_window_size
	smallest = at_smallest
	largest = at_largest
	_apply_region()
	queue_redraw()


## Opens at once (the pointer reached the tab, or a snapshot wants it open).
func open_now(instant: bool = false) -> void:
	is_open = true
	away = 0.0
	if instant:
		alpha = 1.0
	_apply_region()
	queue_redraw()


func close_now() -> void:
	is_open = false
	alpha = 0.0
	away = 0.0
	hovered = ""
	pressed = ""
	_apply_region()
	queue_redraw()


## Moves the strip on by `dt` with the pointer at `pointer` (points), or nowhere (null).
func step(dt: float, pointer: Variant) -> void:
	var at: Vector2 = pointer if pointer is Vector2 else Vector2(-1e9, -1e9)
	var was := [hovered, alpha, pressed, tab_hovered]
	if _pressed_left > 0.0:
		_pressed_left -= dt
		if _pressed_left <= 0.0:
			pressed = ""
	tab_hovered = not is_open and tab_hit_rect().has_point(at)
	if tab_hovered:
		open_now()
	elif is_open:
		if strip_rect().has_point(at):
			away = 0.0
		else:
			away += dt
	if is_open:
		hovered = button_at(at)
		var linger := float(tuning["linger_sec"])
		if away <= linger or always_shown():
			alpha = minf(1.0, alpha + dt / maxf(0.001, float(tuning["fade_in_sec"])))
		else:
			# Only the part of this step past the linger counts toward the fade.
			alpha = maxf(0.0, alpha - minf(dt, away - linger) / maxf(0.001, float(tuning["fade_out_sec"])))
			if alpha <= 0.0:
				close_now()
	if [hovered, alpha, pressed, tab_hovered] != was:
		queue_redraw()


## A click at `point` (window units). True if it was on a button.
func click(point: Vector2) -> bool:
	var id := button_at(point / ui_scale)
	if id == "":
		return false
	press(id)
	return true


func press(id: String) -> void:
	if is_disabled(id):
		return
	away = 0.0
	pressed = id
	_pressed_left = float(tuning["pressed_sec"])
	queue_redraw()
	match id:
		"photo":
			photo_requested.emit()
		"book":
			book_requested.emit()
		"zoom_out":
			zoom_requested.emit(-1)
		"zoom_in":
			zoom_requested.emit(1)
		"settings":
			settings_requested.emit()
		"quit":
			quit_requested.emit()


func state_of(id: String) -> String:
	if is_disabled(id):
		return "disabled"
	if id == pressed:
		return "pressed"
	if id == hovered:
		return "hover"
	return "normal"


func _process(delta: float) -> void:
	var pointer: Variant = null
	if pointer_source.is_valid():
		pointer = pointer_source.call()
	elif _window != null:
		# Reading where the pointer is never moves or captures it.
		pointer = Vector2(DisplayServer.mouse_get_position() - _window.position)
	if pointer is Vector2:
		pointer = (pointer as Vector2) / ui_scale
	step(delta, pointer)


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		# A click can take the scene out of the tree (quit); never touch a viewport it has left.
		if click(button.position) and is_inside_tree():
			get_viewport().set_input_as_handled()


func _apply_region() -> void:
	if regions == null:
		return
	regions.set_region(REGION, hit_rect())
	if _window != null:
		regions.apply(_window)


## A frame of a sheet whose density is `d`, with its top-left at `at_pt` (points), one sheet px per
## device px (snapped to whole device px).
func _frame(texture: Texture2D, d: Dictionary, index: int, at_pt: Vector2, color: Color) -> void:
	var w := int(d["frame_w"])
	var h := int(d["frame_h"])
	var columns := int(d["columns"])
	var src := Rect2(Vector2((index % columns) * w, (index / columns) * h), Vector2(w, h))
	var dst := Rect2((at_pt * ui_scale).round(), Vector2(w, h))
	draw_texture_rect_region(texture, dst, src, color)


func _draw() -> void:
	if not is_open or alpha < 1.0:
		var tab_d: Dictionary = tab_meta["densities"][density]
		var tab_a := float(tuning["tab_alpha"]) * (1.0 - alpha)
		_frame(_tab, tab_d, 1 if tab_hovered else 0, tab_rect().position, Color(1, 1, 1, tab_a))
	if not is_open or alpha <= 0.0:
		return
	var d: Dictionary = buttons_meta["densities"][density]
	var names: Array = buttons_meta["buttons"]
	var states: Array = buttons_meta["states"]
	for id in IDS:
		var index := states.find(state_of(id)) * names.size() + names.find(id)
		_frame(_buttons, d, index, button_rect(id).position, Color(1, 1, 1, alpha))
