class_name SceneLetterCard
extends Node2D

## The elder's letter on the scene while you read it (issue 314):
## a paper card beside you on the log, the elder's portrait in your skin, the day it came, the letter in the caption
## hand. It fades in as you unfold the letter and out as you fold it away (`LivingScene` steps it with the sitter); a
## click on it or Esc closes it early. When the window is too small for the whole letter (50%) it shows the first lines
## and "Read in the journal", which opens the journal at it. The letter stays in the journal either way.
##
## Drawn inside the scene window like the demo card, never a window of its own: it never takes focus, raises or
## activates anything, and makes no sound. While it shows it is the scene's `letter_card` hit region. Tuning
## `letter_card` in balance.json; sizes in points.
##
## The art is the bench's field kit, never drawn in code: the book kit's note card and caption hand, the config kit's
## button and the elder's portrait (`Game.elder_portrait`).

const REGION := "letter_card"

## The read button was clicked: open the journal at the letter.
signal journal_requested

var tuning: Dictionary = {}
## Window units per point (the screen's scale, whatever the scene's size).
var ui_scale := 1.0
## The letter shown ({} for none) and its elder's portrait (null while the art is missing).
var letter: Dictionary = {}
var portrait: Texture2D
## Whether the card is wanted now (he holds the letter open) and not closed early.
var open := false
var dismissed := false
var alpha := 0.0
## Whether the window fits only the first lines.
var compact := false
## Where the reader is, in window units (the card stands beside it).
var reader := Rect2()
## What it never covers, in points (the control strip): it drops below it instead.
var keep_clear := Rect2()
var hovered := ""
var regions: SceneHitRegions
var kit: SceneConfigKit
var book: SceneConfigKit
var _window: Window
var _region_on := false
## The card rect (points) the region was last set from.
var _region_pt := Rect2()


func setup(card_tuning: Dictionary, window: Window, hit: SceneHitRegions, ui: float) -> void:
	tuning = card_tuning
	_window = window
	regions = hit
	ui_scale = ui
	name = "LetterCard"
	kit = SceneConfigKit.new(ui_scale)
	book = SceneConfigKit.new(ui_scale, SceneConfigKit.book_dir())
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 3
	visible = false


## A new reading of `with_letter`: shown again at its next unfold, even if the last one was closed early.
func set_letter(with_letter: Dictionary, with_portrait: Texture2D) -> void:
	letter = with_letter
	portrait = with_portrait
	dismissed = false
	queue_redraw()


func shown() -> bool:
	return visible and alpha > 0.0


## Whether it catches the mouse now (shown and not closing).
func catches() -> bool:
	return _region_on


## Moves it on by `dt`: `holding` while he holds the letter open, beside `reader_rect` (window units).
func step(dt: float, holding: bool, reader_rect: Rect2) -> void:
	open = holding and not letter.is_empty()
	reader = reader_rect
	var target := 1.0 if open and not dismissed else 0.0
	var was := alpha
	var sec := float(tuning["fade_in_sec"]) if target > alpha else float(tuning["close_sec" if dismissed else "fade_out_sec"])
	alpha = move_toward(alpha, target, dt / maxf(0.001, sec))
	if alpha > 0.0 and not visible:
		compact = _wants_compact()
	visible = alpha > 0.0
	modulate = Color(1, 1, 1, alpha)
	if alpha != was:
		queue_redraw()
	if (alpha > 0.0 and target > 0.0) != _region_on:
		_region_on = alpha > 0.0 and target > 0.0
		_apply_region()
	elif _region_on and card_rect() != _region_pt:
		# The card moves with the reader and the strip it keeps clear of (a resize, a corner, the mirror):
		# the region follows the drawn card, never where it was when the region was set (issue 465).
		_apply_region()
		queue_redraw()


## Closes it early (a click or Esc); it fades quickly and stays closed until the next letter.
func dismiss() -> void:
	if letter.is_empty():
		return
	dismissed = true
	_region_on = false
	_apply_region()


## The scene changed size in place (issue 307): the card refits.
func resized() -> void:
	if shown():
		compact = _wants_compact()
		if _region_on:
			_apply_region()
	queue_redraw()


func _window_pt() -> Vector2:
	return Vector2(_window.size) / ui_scale if _window != null else Vector2(1200, 560)


func _inset() -> Vector2:
	return Vector2(float(tuning["inset_pt"][0]), float(tuning["inset_pt"][1]))


func _wants_compact() -> bool:
	var window := _window_pt()
	if window.y < float(tuning["full_min_height_pt"]):
		return true
	return _height(false) + 2.0 * _inset().y > window.y


func _pad() -> float:
	return book.layout("note_pad_pt")


func _text_width() -> float:
	return float(tuning["width_pt"]) - 2.0 * _pad()


func _note_font() -> Font:
	return book.caption_font("note")


func _note_size() -> int:
	return int(round(book.caption_size_pt("note") * ui_scale))


func _line_pt() -> float:
	return _note_font().get_height(_note_size()) / ui_scale


## The portrait's whole multiple of its sheet px (0: not drawn).
func _portrait_times(small: bool) -> int:
	if portrait == null:
		return 0
	var n := maxi(1, int(floor(ui_scale / (2.0 if small else 1.0))))
	if small and portrait.get_height() * n / ui_scale > float(tuning["small_portrait_max_pt"]):
		return 0
	return n


func _portrait_pt(small: bool) -> Vector2:
	var n := _portrait_times(small)
	return Vector2(portrait.get_size()) * n / ui_scale if n > 0 else Vector2.ZERO


func _came() -> String:
	return SceneBookWindow.day_text(String(letter.get("day", ""))) if String(letter.get("day", "")) != "" else ""


func _head_height(small: bool) -> float:
	return maxf(_portrait_pt(small).y, _caption_pt())


func _caption_pt() -> float:
	return book.caption_font("caption").get_height(int(round(book.caption_size_pt("caption") * ui_scale))) / ui_scale


## The body's lines in the caption hand, wrapped to the card; at most `max_lines` (an ellipsis on the last) when > 0.
func lines(max_lines: int = 0) -> Array[String]:
	var out: Array[String] = []
	var font := _note_font()
	var size := _note_size()
	var width := _text_width() * ui_scale
	for paragraph in String(letter.get("body", "")).split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var next := word if line == "" else line + " " + word
			if line != "" and font.get_string_size(next, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
				out.append(line)
				line = word
			else:
				line = next
		out.append(line)
	if max_lines > 0 and out.size() > max_lines:
		out.resize(max_lines)
		var last := out[max_lines - 1]
		while last.contains(" ") and font.get_string_size(last + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width:
			last = last.substr(0, last.rfind(" "))
		out[max_lines - 1] = last.rstrip(" ,;:.") + "…"
	return out


func _signed() -> Array[String]:
	var out: Array[String] = []
	for key in ["sign_off", "name"]:
		if String(letter.get(key, "")) != "":
			out.append(String(letter[key]))
	return out


func _button_size() -> Vector2:
	var label := kit.font("label")
	var w := label.get_string_size(String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(round(kit.font_size_pt("label") * ui_scale))).x / ui_scale
	return Vector2(ceilf(w) + 2.0 * kit.layout("tab_pad_pt"), kit.size_pt("button").y)


func _height(small: bool) -> float:
	var gap := float(tuning["gap_pt"])
	var h := _pad() + _head_height(small) + gap
	if small:
		h += lines(int(tuning["small_lines"])).size() * _line_pt() + gap * 1.5 + _button_size().y
	else:
		h += lines().size() * _line_pt() + gap + _signed().size() * _line_pt()
	return ceilf(h + _pad())


## The card in points: `gap_pt` to the right of the reader, `inset_pt` from the window's top, kept inside the window.
func card_rect() -> Rect2:
	var w := float(tuning["width_pt"])
	var h := _height(compact)
	var window := _window_pt()
	var inset := _inset()
	var beside := (reader.end.x / ui_scale) + float(tuning["gap_pt"]) if reader.has_area() else window.x * 0.5 - w * 0.5
	# The scene mirrored in the bottom-left (issue 422) puts the reader near the right: then the card goes left of him.
	var before := (reader.position.x / ui_scale) - float(tuning["gap_pt"]) - w
	if reader.has_area() and beside + w > window.x - inset.x and before >= inset.x:
		beside = before
	var x := roundf(clampf(beside, inset.x, maxf(inset.x, window.x - w - inset.x)))
	var y := inset.y
	if keep_clear.has_area() and Rect2(Vector2(x, y), Vector2(w, h)).intersects(keep_clear.grow(float(tuning["gap_pt"]))):
		y = keep_clear.end.y + float(tuning["gap_pt"])
	y = roundf(clampf(y, 0.0, maxf(0.0, window.y - h - inset.y)))
	return Rect2(Vector2(x, y), Vector2(w, h))


func button_rect() -> Rect2:
	if not compact:
		return Rect2()
	var card := card_rect()
	var size := _button_size()
	return Rect2(Vector2(card.position.x + _pad(), card.end.y - _pad() - size.y), size)


## A click at `point` (window units). True if it was on the card: the button opens the journal, anywhere else closes it.
func click(point: Vector2) -> bool:
	if not _region_on:
		return false
	var at := point / ui_scale
	if not card_rect().has_point(at):
		return false
	if compact and button_rect().has_point(at):
		dismiss()
		journal_requested.emit()
	else:
		dismiss()
	return true


func _input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null and button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
		if click(button.position) and is_inside_tree():
			get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE and _region_on:
		dismiss()
		if is_inside_tree():
			get_viewport().set_input_as_handled()
	var motion := event as InputEventMouseMotion
	if motion != null and compact:
		var over := "button" if _region_on and button_rect().has_point(motion.position / ui_scale) else ""
		if over != hovered:
			hovered = over
			queue_redraw()


func _apply_region() -> void:
	if regions == null:
		return
	if _region_on:
		_region_pt = card_rect()
		regions.set_region(REGION, Rect2(_region_pt.position * ui_scale, _region_pt.size * ui_scale))
	else:
		_region_pt = Rect2()
		regions.clear(REGION)
	if _window != null:
		regions.apply(_window)


func _px(r: Rect2) -> Rect2:
	return Rect2((r.position * ui_scale).round(), (r.size * ui_scale).round())


func _line(text: String, font: Font, size: int, at_pt: Vector2, color: Color) -> void:
	draw_string(font, (at_pt * ui_scale).round() + Vector2(0, roundf(font.get_ascent(size))), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _draw() -> void:
	if letter.is_empty() or alpha <= 0.0:
		return
	var card := card_rect()
	draw_style_box(book.style("note"), _px(card))
	var gap := float(tuning["gap_pt"])
	var at := card.position + Vector2(_pad(), _pad())
	var head := _head_height(compact)
	var face := _portrait_pt(compact)
	if face != Vector2.ZERO:
		draw_texture_rect(portrait, Rect2((at * ui_scale).round(), (face * ui_scale).round()), false)
	var caption_size := int(round(book.caption_size_pt("caption") * ui_scale))
	var came_at := Vector2(at.x + (face.x + 8.0 if face.x > 0.0 else 0.0), at.y + head - _caption_pt())
	_line(_came(), book.caption_font("caption"), caption_size, came_at, book.colour("caption"))
	at.y += head + gap
	var ink := book.colour("on_note")
	var font := _note_font()
	var size := _note_size()
	for line in lines(int(tuning["small_lines"]) if compact else 0):
		_line(line, font, size, at, ink)
		at.y += _line_pt()
	if not compact:
		at.y += gap
		for line in _signed():
			_line(line, font, size, at, ink)
			at.y += _line_pt()
		return
	var b := button_rect()
	var state := "hover" if hovered == "button" else "normal"
	draw_style_box(kit.style("button", state), _px(b))
	var label := kit.font("label")
	var label_size := int(round(kit.font_size_pt("label") * ui_scale))
	var text_w := label.get_string_size(String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size).x
	var base := Vector2(b.position.x * ui_scale + (b.size.x * ui_scale - text_w) / 2.0,
			b.position.y * ui_scale + (b.size.y * ui_scale + label.get_ascent(label_size) - label.get_descent(label_size)) / 2.0)
	draw_string(label, base.round(), String(tuning["button"]), HORIZONTAL_ALIGNMENT_LEFT, -1, label_size, kit.colour("on_button"))
