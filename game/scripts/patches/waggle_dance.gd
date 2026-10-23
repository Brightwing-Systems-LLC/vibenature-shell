class_name WaggleDance
extends Node2D

## Collecting honey: a small comb appears over the hive and lights its cells one at a
## time; click them back in the same order. Getting one wrong or walking away only
## leaves the honey in the hive for another try. Runs on timers, not per frame.

signal finished(success: bool)

var patch: PatchWindow
var tuning: Dictionary
var model := DanceModel.new()
var _grid := Vector2i(3, 2)
var _cell_px := 8
var _gap_px := 2
var _lit := -1
var _showing := true
var _show_index := 0
var _done := false
var _step_timer := Timer.new()
var _timeout := Timer.new()


func start(target: PatchWindow, center: Vector2, dance_tuning: Dictionary, rng: RandomNumberGenerator) -> void:
	patch = target
	tuning = dance_tuning
	_grid = AssetLibrary.vec2i(tuning["cells"])
	_cell_px = int(tuning["cell_px"])
	_gap_px = int(tuning["gap_px"])
	model.deal(_grid.x * _grid.y, int(tuning["length"]), rng)
	var size := _comb_size()
	var offset := Vector2(AssetLibrary.vec2i(tuning["offset_px"]))
	var max_x := float(patch.art_size().x - size.x)
	position = Vector2(clampf(center.x - size.x / 2.0, 0.0, maxf(max_x, 0.0)), maxf(center.y + offset.y, 2.0)).round()
	patch.overlay().add_child(self)
	_step_timer.timeout.connect(_show_step)
	add_child(_step_timer)
	_timeout.one_shot = true
	_timeout.timeout.connect(func() -> void: _finish(false))
	add_child(_timeout)
	_timeout.start(float(tuning["timeout_sec"]))
	_step_timer.start(float(tuning["show_step_sec"]))
	_changed()


func _comb_size() -> Vector2i:
	return Vector2i(_grid.x * _cell_px + (_grid.x - 1) * _gap_px, _grid.y * _cell_px + (_grid.y - 1) * _gap_px)


func _cell_rect(cell: int) -> Rect2:
	var column := cell % _grid.x
	var row := cell / _grid.x
	return Rect2(column * (_cell_px + _gap_px), row * (_cell_px + _gap_px), _cell_px, _cell_px)


## The bee's turn: light each cell of the sequence, with a dark beat between, then
## hand over to the player.
func _show_step() -> void:
	if _lit >= 0:
		_lit = -1
	elif _show_index < model.sequence.size():
		_lit = model.sequence[_show_index]
		_show_index += 1
	else:
		_showing = false
		_step_timer.stop()
	_changed()


## A click anywhere on the patch while the dance is up; only cells count.
func press(art_point: Vector2) -> void:
	if _done or _showing:
		return
	var local := art_point - position
	for cell in _grid.x * _grid.y:
		if _cell_rect(cell).has_point(local):
			match model.press(cell):
				"done":
					_finish(true)
				"wrong":
					_finish(false)
				_:
					_lit = cell
					_changed()
			return


func _draw() -> void:
	var size := _comb_size()
	draw_rect(Rect2(-1, -1, size.x + 2, size.y + 2), Color("4c3e24"))
	for cell in _grid.x * _grid.y:
		var color := Color("f9c22b") if cell == _lit else Color("9e4539")
		draw_rect(_cell_rect(cell), color)


func _changed() -> void:
	queue_redraw()
	patch.redraw()


func _finish(success: bool) -> void:
	if _done:
		return
	_done = true
	_step_timer.stop()
	_timeout.stop()
	finished.emit(success)
	queue_free()
	patch.redraw()
