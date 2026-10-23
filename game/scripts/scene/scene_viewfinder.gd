class_name SceneViewfinder
extends Node2D

## The camera's viewfinder (Skypatch issue 176): the
## strip's 📷 puts a 3:2 frame over the scene that follows the pointer, kept inside the scene's
## composition (`LivingScene.frame_pt`). The scroll wheel (or a trackpad's scroll or pinch) resizes
## it between `min_height_pt` and the scene's full height. A click takes the photo (`shot` with the
## frame's rect in points); 📷 again, a right-click or `idle_cancel_sec` with no movement cancels.
## Not Escape: the scene never has keyboard focus.
##
## Only while it is open does the scene catch the mouse: one hit region (`REGION`) covering the
## whole window, removed the moment the shot is taken or cancelled. The window never takes focus
## (the non-activating panel does that); the pointer is only read, never moved or confined.
##
## Drawn in window units in the field-kit palette: brass corner brackets over a light dim outside
## the frame. A stand-in in code until the bench draws one. Hidden while the photo is grabbed, so
## it is never in a photo. A quiet shutter flash over the framed rect follows the shot.

signal shot(rect_pt: Rect2)
signal cancelled

const REGION := "viewfinder"
const ASPECT := 1.5

var tuning: Dictionary = {}
var scene: LivingScene
## Window units per scene point.
var scale_px := 1.0
## Where the frame may go, in points.
var bounds := Rect2()
var is_open := false
## The frame's height in points (its width is 3:2 of it).
var height_pt := 0.0
## The frame's centre as asked (the pointer), in points; `rect()` keeps it inside `bounds`.
var center_pt := Vector2.ZERO
## Seconds since the pointer last moved or the wheel last turned.
var idle := 0.0
## Where the pointer is (window units), or the real pointer when not set: tests and snapshots set it.
var pointer_source: Callable
var flash_left := 0.0
var _flash_rect := Rect2()
var _last_pointer: Variant = null


func setup(viewfinder_tuning: Dictionary, owner_scene: LivingScene) -> void:
	tuning = viewfinder_tuning
	scene = owner_scene
	scale_px = scene.scale_px
	bounds = scene.shown_rect(scene.frame_pt if scene.frame_pt.has_area() else Rect2(Vector2.ZERO, scene.size_pt))
	name = "Viewfinder"
	scale = Vector2.ONE
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX - 2
	set_process(false)


## The tallest frame that fits (points).
func max_height() -> float:
	return minf(bounds.size.y, bounds.size.x / ASPECT)


func min_height() -> float:
	return minf(float(tuning["min_height_pt"]), max_height())


## The frame's rect in points: 3:2, `height_pt` tall, centred on `center_pt` as far as it can be
## while staying inside `bounds`.
func rect() -> Rect2:
	return SceneViewfinder.fit(center_pt, height_pt, bounds)


static func fit(center: Vector2, height: float, inside: Rect2) -> Rect2:
	var h := minf(height, minf(inside.size.y, inside.size.x / ASPECT))
	var size := Vector2(h * ASPECT, h)
	var top_left := (center - size / 2.0).clamp(inside.position, inside.end - size)
	return Rect2(top_left, size)


## Opens the viewfinder centred on `at_pt` (points), or the scene's middle.
func open(at_pt: Variant = null) -> void:
	is_open = true
	idle = 0.0
	height_pt = clampf(max_height() * float(tuning["start_height_share"]), min_height(), max_height())
	center_pt = at_pt if at_pt is Vector2 else bounds.get_center()
	_last_pointer = at_pt
	visible = true
	set_process(true)
	_apply_region()
	queue_redraw()


## Closes without a photo.
func cancel() -> void:
	if not is_open:
		return
	_close()
	cancelled.emit()


## Takes the photo of what is in the frame now.
func shoot() -> void:
	if not is_open:
		return
	var r := rect()
	_close()
	shot.emit(r)
	flash_left = float(tuning["flash_sec"])
	_flash_rect = r
	set_process(true)
	queue_redraw()


func _close() -> void:
	is_open = false
	_apply_region()
	queue_redraw()


## Resizes by `notches` of the wheel (up is bigger), within the limits.
func resize(notches: float) -> void:
	if not is_open:
		return
	idle = 0.0
	height_pt = clampf(height_pt * pow(float(tuning["wheel_step"]), notches), min_height(), max_height())
	queue_redraw()


## Moves on by `dt` with the pointer at `pointer` (points), or nowhere (null).
func step(dt: float, pointer: Variant) -> void:
	if flash_left > 0.0:
		flash_left = maxf(0.0, flash_left - dt)
		queue_redraw()
	if not is_open:
		if flash_left <= 0.0:
			set_process(false)
		return
	if pointer is Vector2 and pointer != _last_pointer:
		_last_pointer = pointer
		center_pt = pointer
		idle = 0.0
		queue_redraw()
	else:
		idle += dt
	if idle >= float(tuning["idle_cancel_sec"]):
		cancel()


## A mouse button at `point` (window units). True if the viewfinder took it.
func button(index: MouseButton, point: Vector2) -> bool:
	if not is_open:
		return false
	match index:
		MOUSE_BUTTON_LEFT:
			# A click on the strip is the strip's (📷 again cancels through it).
			if scene.controls != null and scene.controls.button_at(point / scene.controls.ui_scale) != "":
				return false
			shoot()
			return true
		MOUSE_BUTTON_RIGHT:
			cancel()
			return true
		MOUSE_BUTTON_WHEEL_UP:
			resize(1.0)
			return true
		MOUSE_BUTTON_WHEEL_DOWN:
			resize(-1.0)
			return true
	return false


func _process(delta: float) -> void:
	var pointer: Variant = null
	if pointer_source.is_valid():
		pointer = pointer_source.call()
	elif scene != null:
		# Reading where the pointer is never moves or captures it.
		pointer = Vector2(DisplayServer.mouse_get_position() - scene.position)
	if pointer is Vector2:
		pointer = (pointer as Vector2) / scale_px
	step(delta, pointer)


func _input(event: InputEvent) -> void:
	if not is_open:
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if button(mb.button_index, mb.position):
			get_viewport().set_input_as_handled()
		return
	var pan := event as InputEventPanGesture
	if pan != null:
		resize(-pan.delta.y * float(tuning["pan_notches"]))
		get_viewport().set_input_as_handled()
		return
	var pinch := event as InputEventMagnifyGesture
	if pinch != null and pinch.factor > 0.0:
		resize(log(pinch.factor) / log(float(tuning["wheel_step"])))
		get_viewport().set_input_as_handled()


func _apply_region() -> void:
	if scene == null:
		return
	if is_open:
		scene.hit.set_region(REGION, Rect2(Vector2.ZERO, Vector2(scene.size)))
	else:
		scene.hit.clear(REGION)
	scene.hit.apply(scene)


func _draw() -> void:
	if flash_left > 0.0 and not is_open:
		var a := float(tuning["flash_alpha"]) * flash_left / maxf(0.001, float(tuning["flash_sec"]))
		draw_rect(_px(_flash_rect), Color(1, 1, 1, a))
	if not is_open:
		return
	var r := _px(rect())
	var whole := Rect2(Vector2.ZERO, Vector2(scene.size))
	var dim := Color(String(tuning["dim_color"]))
	# The dim outside the frame, as four bands round it.
	draw_rect(Rect2(whole.position, Vector2(whole.size.x, r.position.y)), dim)
	draw_rect(Rect2(Vector2(0, r.end.y), Vector2(whole.size.x, whole.end.y - r.end.y)), dim)
	draw_rect(Rect2(Vector2(0, r.position.y), Vector2(r.position.x, r.size.y)), dim)
	draw_rect(Rect2(Vector2(r.end.x, r.position.y), Vector2(whole.end.x - r.end.x, r.size.y)), dim)
	var u := maxf(1.0, roundf(scale_px * float(tuning["line_pt"])))
	var arm := roundf(minf(r.size.x, r.size.y) * float(tuning["corner_share"]))
	var ink := Color(String(tuning["ink"]))
	var brass := Color(String(tuning["brass"]))
	var hairline := Color(String(tuning["hairline"]))
	draw_rect(r, hairline, false, maxf(1.0, roundf(scale_px * 0.5)))
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x == r.position.x else -1.0
		var sy := 1.0 if corner.y == r.position.y else -1.0
		_bracket(corner, sx, sy, arm, u + 2.0, ink)
		_bracket(corner + Vector2(sx, sy), sx, sy, arm - 2.0, u, brass)
	var tick := roundf(arm * 0.4)
	var c := r.get_center().round()
	draw_rect(Rect2(c - Vector2(tick, u / 2.0), Vector2(tick * 2.0, u)), Color(brass, 0.7))
	draw_rect(Rect2(c - Vector2(u / 2.0, tick), Vector2(u, tick * 2.0)), Color(brass, 0.7))


## An L of two bars from `at`, pointing into the frame along `sx`, `sy`.
func _bracket(at: Vector2, sx: float, sy: float, arm: float, w: float, color: Color) -> void:
	var h_bar := Rect2(at, Vector2(arm * sx, w * sy)).abs()
	var v_bar := Rect2(at, Vector2(w * sx, arm * sy)).abs()
	draw_rect(h_bar, color)
	draw_rect(v_bar, color)


func _px(r_pt: Rect2) -> Rect2:
	return Rect2((r_pt.position * scale_px).round(), (r_pt.size * scale_px).round())
