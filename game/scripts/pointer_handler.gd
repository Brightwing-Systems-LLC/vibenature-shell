class_name PointerHandler
extends RefCounted

## Tells a click from a drag on one window. Pressing and moving past a few pixels
## drags the window (moved here, so a click can mean something else); pressing and
## releasing in place is a click. Other buttons click on press.

signal clicked(button: int, window_position: Vector2)
signal held_click(window_position: Vector2, duration_sec: float)
## A left click with Option (alt) held, instead of `clicked`.
signal alt_clicked(window_position: Vector2)
## The player let go of the window after dragging it somewhere.
signal dragged

var window: Window
var threshold_px := 4.0
var draggable := true
var _pressed := false
var _dragging := false
var _press_mouse := Vector2i.ZERO
var _press_window := Vector2i.ZERO
var _press_msec := 0


func _init(target: Window, drag_threshold_px: float) -> void:
	window = target
	threshold_px = drag_threshold_px
	window.window_input.connect(_on_input)


func is_dragging() -> bool:
	return _dragging


func _on_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		if button.button_index != MOUSE_BUTTON_LEFT:
			if button.pressed:
				clicked.emit(button.button_index, button.position)
			return
		if button.pressed:
			_pressed = true
			_dragging = false
			_press_msec = Time.get_ticks_msec()
			_press_mouse = DisplayServer.mouse_get_position()
			_press_window = window.position
		else:
			if _pressed and not _dragging:
				held_click.emit(button.position, float(Time.get_ticks_msec() - _press_msec) / 1000.0)
				if button.alt_pressed:
					alt_clicked.emit(button.position)
				else:
					clicked.emit(MOUSE_BUTTON_LEFT, button.position)
			var moved := _pressed and _dragging
			_pressed = false
			_dragging = false
			if moved:
				dragged.emit()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _pressed and draggable:
		var delta := DisplayServer.mouse_get_position() - _press_mouse
		if not _dragging and Vector2(delta).length() >= threshold_px:
			_dragging = true
		if _dragging:
			window.position = _press_window + delta
