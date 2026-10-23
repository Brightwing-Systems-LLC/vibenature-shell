class_name SceneMouseClear
extends CanvasLayer

## Mouse clear (issue 428): while the scene is on
## top, a soft see-through circle follows the cursor over it, so whatever is under the scene can be seen
## to aim at (clicks already pass through, `SceneHitRegions`). Visual only.
##
## On exactly when the scene is on top (`set_on`). Off, it costs nothing: no processing, no polling, no
## drawing. On, it polls the global cursor (the window is click-through, so it gets no motion) every
## `slow_poll_sec` while the cursor is outside the window, and every frame while inside. The hole is
## the last pass in the window, after any `SharpShrink`, in window units; it multiplies colour and
## alpha together. Over the parts that take the mouse (whatever `SceneHitRegions` holds) nothing is cut.
## Only the cursor position is read: nothing about the windows or apps under it.

const SHADER := preload("res://scripts/scene/scene_mouse_clear.gdshader")
const MAX_KEEP := 8

var tuning: Dictionary = {}
## Window units per point (the screen's scale).
var ui_scale := 1.0
## The cursor in screen units (Vector2), or null for none. Unset: the real cursor.
var cursor_source: Callable
var on := false
## The chosen size, points across (one of `diameters_pt`, Config's "Mouse clear"; issue 438). 0: the default.
var diameter_pt := 0.0
## Whether the cursor is inside the window, and the hole's centre there (window units).
var inside := false
var center := Vector2.ZERO
## Cursor reads and hole draws so far (tests: none while off).
var polls := 0
var draws := 0
var _scene: LivingScene
var _hit: SceneHitRegions
var _wait := 0.0
var _hole := _Hole.new()
var _material := ShaderMaterial.new()


func setup(mouse_tuning: Dictionary, scene: LivingScene, hit: SceneHitRegions, scale: float) -> void:
	tuning = mouse_tuning
	_scene = scene
	_hit = hit
	ui_scale = scale
	name = "MouseClear"
	layer = 100
	_material.shader = SHADER
	_hole.material = _material
	_hole.owner_clear = self
	_hole.visible = false
	add_child(_hole)


func _ready() -> void:
	# A node with `_process` starts processing on entering the tree: off until on top.
	set_process(on)


## The hole's radius and the width of its feathered rim, in window units. The rim keeps its share of the
## circle at every size (`feather_pt` is the default size's).
func radius() -> float:
	return size_pt() * ui_scale / 2.0


func feather() -> float:
	return float(tuning["feather_pt"]) * size_pt() / float(tuning["diameter_pt"]) * ui_scale


func size_pt() -> float:
	return diameter_pt if diameter_pt > 0.0 else float(tuning["diameter_pt"])


## Config's size (issue 438): applies at once, the hole redrawn where it is.
func set_size(points: float) -> void:
	diameter_pt = points
	if inside:
		_hole.queue_redraw()
		_redraw()


func set_on(value: bool) -> void:
	on = value
	_wait = 0.0
	set_process(on)
	if not on:
		_leave()


func _process(delta: float) -> void:
	if not inside:
		_wait -= delta
		if _wait > 0.0:
			return
	poll()


## Reads the cursor once and moves, shows or hides the hole.
func poll() -> void:
	polls += 1
	var at: Variant = null
	if cursor_source.is_valid():
		at = cursor_source.call()
	elif _scene != null:
		# Reading where the pointer is never moves or captures it.
		at = Vector2(DisplayServer.mouse_get_position())
	if at is Vector2 and _scene != null and _scene.visible:
		var local: Vector2 = at - Vector2(_scene.position)
		if Rect2(Vector2.ZERO, Vector2(_scene.size)).has_point(local):
			inside = true
			center = local
			_hole.visible = true
			_hole.queue_redraw()
			_redraw()
			return
	_wait = float(tuning["slow_poll_sec"])
	_leave()


func _leave() -> void:
	if not inside:
		return
	inside = false
	_hole.visible = false
	_redraw()


func _redraw() -> void:
	if _scene != null and not _scene.draws_always:
		WindowChrome.redraw(_scene)


func _keep_rects() -> PackedVector4Array:
	var out := PackedVector4Array()
	if _hit != null:
		for region_name in _hit.regions:
			if out.size() >= MAX_KEEP:
				break
			var r: Rect2 = _hit.regions[region_name]
			out.append(Vector4(r.position.x, r.position.y, r.size.x, r.size.y))
	return out


func _draw_hole(item: Node2D) -> void:
	draws += 1
	var outer := radius()
	var keep := _keep_rects()
	var count := keep.size()
	keep.resize(MAX_KEEP)
	_material.set_shader_parameter("center", center)
	_material.set_shader_parameter("outer", outer)
	_material.set_shader_parameter("inner", maxf(0.0, outer - feather()))
	_material.set_shader_parameter("keep", keep)
	_material.set_shader_parameter("keep_count", count)
	item.draw_rect(Rect2(center - Vector2(outer, outer), Vector2(outer, outer) * 2.0), Color.WHITE)


class _Hole extends Node2D:
	var owner_clear: SceneMouseClear

	func _draw() -> void:
		owner_clear._draw_hole(self)
