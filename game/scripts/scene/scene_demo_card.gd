class_name SceneDemoCard
extends Node2D

## The demo's morning card (issue 268): once a game day, when
## the van brings you in, a note over the scene says this is the demo and offers more places, with one button that
## opens the upgrade page in the browser. It fades in, stays `show_sec` in all and fades out; the ✕ closes it early.
## The demo build only (`Edition`); when it is due is `Edition.morning_card_due`, decided by the game.
##
## Drawn inside the scene window, never a window of its own: it never takes focus, raises or activates anything. While
## it shows it is the scene's `demo_card` hit region (everything else stays click-through); the browser opens only on
## a click on the button. Tuning `demo_card` in balance.json (the words too); sizes in points.
##
## The art is the bench's field kit, never drawn in code: the book kit's taped note card, the strip's ✕
## (`scene_controls` `quit`: the kit's only ✕; the book's `act_close` is a back arrow), the config kit's button and Fraunces. @1x on a 1× screen, @2x on 2× and up, one sheet px per device px.

const REGION := "demo_card"

var tuning: Dictionary = {}
## Window units per point (the screen's scale, whatever the scene's size).
var ui_scale := 1.0
## Showing now (fading in, held, or fading out).
var shown := false
## Seconds since it was shown.
var t := 0.0
var alpha := 0.0
## "button", "close" or "" under the pointer; the one drawn pressed for `pressed_sec` after a click.
var hovered := ""
var pressed := ""
## Opens the upgrade page (`OS.shell_open`); tests replace it. Called only by a click on the button.
var opener: Callable = func(url: String) -> void: OS.shell_open(url)
## Where the pointer is (window units), or the screen's real pointer when not set: tests and snapshots set it.
var pointer_source: Callable
var regions: SceneHitRegions
var kit: SceneConfigKit
var book: SceneConfigKit
var _x_meta: Dictionary = {}
var _x_sheet: Texture2D
var _window: Window
var _pressed_left := 0.0


func setup(card_tuning: Dictionary, window: Window, hit: SceneHitRegions, ui: float) -> void:
	tuning = card_tuning
	_window = window
	regions = hit
	ui_scale = ui
	name = "DemoCard"
	kit = SceneConfigKit.new(ui_scale)
	book = SceneConfigKit.new(ui_scale, SceneConfigKit.book_dir())
	_x_meta = SceneControls.read_meta(SceneControls.BUTTONS_DIR)
	_x_sheet = load(SceneControls.BUTTONS_DIR.path_join(String(_x_meta["densities"][SceneControls.density_for(ui_scale)]["file"])))
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 2
	visible = false
	set_process(false)


func show_card() -> void:
	shown = true
	visible = true
	t = 0.0
	alpha = 0.0
	hovered = ""
	pressed = ""
	set_process(true)
	_apply_region()
	queue_redraw()


## The scene changed size in place (issue 307): the card keeps to the window's new top.
func resized() -> void:
	_apply_region()
	queue_redraw()


func hide_card() -> void:
	shown = false
	visible = false
	alpha = 0.0
	set_process(false)
	_apply_region()


## Moves it on by `dt` with the pointer at `pointer` (points), or nowhere (null).
func step(dt: float, pointer: Variant = null) -> void:
	if not shown:
		return
	t += dt
	var total := float(tuning["show_sec"])
	if t >= total:
		hide_card()
		return
	var was := [alpha, hovered, pressed]
	alpha = clampf(minf(t / maxf(0.001, float(tuning["fade_in_sec"])), (total - t) / maxf(0.001, float(tuning["fade_out_sec"]))), 0.0, 1.0)
	hovered = part_at(pointer) if pointer is Vector2 else ""
	if _pressed_left > 0.0:
		_pressed_left -= dt
		if _pressed_left <= 0.0:
			pressed = ""
	modulate = Color(1, 1, 1, alpha)
	if [alpha, hovered, pressed] != was:
		queue_redraw()


func _pad() -> float:
	return book.layout("note_pad_pt")


func _close_pt() -> Vector2:
	return Vector2(float(_x_meta["button_pt"][0]), float(_x_meta["button_pt"][1]))


func _text_width() -> float:
	return float(tuning["width_pt"]) - 2.0 * _pad()


func _text_height(text: String, font: Font, size_pt: float, width_pt: float) -> float:
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, width_pt * ui_scale, int(round(size_pt * ui_scale)))
	return size.y / ui_scale


func _heading_width() -> float:
	return _text_width() - _close_pt().x


func _button_size() -> Vector2:
	var label := kit.font("label")
	var w := label.get_string_size(String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(kit.font_size_pt("label") * ui_scale))).x / ui_scale
	return Vector2(ceilf(w) + 2.0 * kit.layout("tab_pad_pt"), kit.size_pt("button").y)


func _inset() -> Vector2:
	return Vector2(float(tuning["inset_pt"][0]), float(tuning["inset_pt"][1]))


## The card in points: its centre at `x_share` of the window's width, `inset_pt` down from the top (over the sky,
## clear of you on the log, the van's road and the strip).
func card_rect() -> Rect2:
	var gap := float(tuning["gap_pt"])
	var h := _pad() + _text_height(String(tuning["heading"]), kit.font("heading"), kit.font_size_pt("heading"), _heading_width()) \
			+ gap + _text_height(String(tuning["body"]), kit.font("body"), kit.font_size_pt("body"), _text_width()) \
			+ gap * 1.5 + _button_size().y + _pad()
	var w := float(tuning["width_pt"])
	var window_w := float(_window.size.x) / ui_scale if _window != null else w
	var x := roundf(clampf(window_w * float(tuning["x_share"]) - w / 2.0, _inset().x, maxf(_inset().x, window_w - w - _inset().x)))
	return Rect2(Vector2(x, _inset().y), Vector2(w, ceilf(h)))


func button_rect() -> Rect2:
	var card := card_rect()
	var size := _button_size()
	return Rect2(Vector2(card.position.x + _pad(), card.end.y - _pad() - size.y), size)


func close_rect() -> Rect2:
	var card := card_rect()
	var inset := float(tuning["close_inset_pt"])
	return Rect2(Vector2(card.end.x - _pad() - _close_pt().x + inset, card.position.y + _pad() - inset), _close_pt())


## "button", "close" or "" at `point` (points).
func part_at(point: Vector2) -> String:
	if not shown:
		return ""
	if close_rect().has_point(point):
		return "close"
	if button_rect().has_point(point):
		return "button"
	return ""


## A click at `point` (window units). True if it was on the card (the card swallows it either way).
func click(point: Vector2) -> bool:
	if not shown:
		return false
	var at := point / ui_scale
	if not card_rect().has_point(at):
		return false
	press(part_at(at))
	return true


func press(part: String) -> void:
	match part:
		"close":
			hide_card()
		"button":
			pressed = "button"
			_pressed_left = float(tuning["pressed_sec"])
			queue_redraw()
			opener.call(String(tuning["url"]))


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
		if click(button.position) and is_inside_tree():
			get_viewport().set_input_as_handled()


func _apply_region() -> void:
	if regions == null:
		return
	if shown:
		var r := card_rect()
		regions.set_region(REGION, Rect2(r.position * ui_scale, r.size * ui_scale))
	else:
		regions.clear(REGION)
	if _window != null:
		regions.apply(_window)


func _px(r: Rect2) -> Rect2:
	return Rect2((r.position * ui_scale).round(), (r.size * ui_scale).round())


func _text(text: String, font: Font, size_pt: float, at_pt: Vector2, width_pt: float, color: Color) -> void:
	var size := int(round(size_pt * ui_scale))
	draw_multiline_string(font, (at_pt * ui_scale).round() + Vector2(0, font.get_ascent(size)), text,
			HORIZONTAL_ALIGNMENT_LEFT, width_pt * ui_scale, size, -1, color)


func _draw() -> void:
	if not shown:
		return
	var card := card_rect()
	draw_style_box(book.style("note"), _px(card))
	var gap := float(tuning["gap_pt"])
	var at := card.position + Vector2(_pad(), _pad())
	var ink := book.colour("on_note")
	_text(String(tuning["heading"]), kit.font("heading"), kit.font_size_pt("heading"), at, _heading_width(), kit.colour("heading"))
	at.y += _text_height(String(tuning["heading"]), kit.font("heading"), kit.font_size_pt("heading"), _heading_width()) + gap
	_text(String(tuning["body"]), kit.font("body"), kit.font_size_pt("body"), at, _text_width(), ink)
	var b := button_rect()
	var state := "pressed" if pressed == "button" else ("hover" if hovered == "button" else "normal")
	draw_style_box(kit.style("button", state), _px(b))
	var label := kit.font("label")
	var label_size := int(round(kit.font_size_pt("label") * ui_scale))
	var colour := kit.colour("on_button_pressed" if state == "pressed" else "on_button")
	var text_w := label.get_string_size(String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var base := Vector2(b.position.x * ui_scale + (b.size.x * ui_scale - text_w) / 2.0,
			b.position.y * ui_scale + (b.size.y * ui_scale + label.get_ascent(label_size) - label.get_descent(label_size)) / 2.0)
	draw_string(label, base.round(), String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, colour)
	var d: Dictionary = _x_meta["densities"][SceneControls.density_for(ui_scale)]
	var names: Array = _x_meta["buttons"]
	var index := (_x_meta["states"] as Array).find("hover" if hovered == "close" else "normal") * int(d["columns"]) + names.find("quit")
	var fw := int(d["frame_w"])
	var fh := int(d["frame_h"])
	var src := Rect2(Vector2((index % int(d["columns"])) * fw, (index / int(d["columns"])) * fh), Vector2(fw, fh))
	draw_texture_rect_region(_x_sheet, Rect2((close_rect().position * ui_scale).round(), Vector2(fw, fh)), src)
