class_name CreatureSprite
extends Sprite2D

## Draws one layer sheet of a CreatureDef. Frames advance on a Timer at the
## animation's own fps, and each change redraws only the window the sprite is in,
## so an idle creature costs one redraw of one window per frame change.

signal finished

var def: CreatureDef
var layer := ""
var anim := ""
var _frames: Array[int] = []
var _loop := false
var _index := 0
var _timer := Timer.new()
## Frames advanced by the owner's own tick (`step`) instead of this sprite's timer: many
## creatures in one window then change frame together, one redraw per tick (the pond).
var driven := false
var _fps := 1.0
var _acc := 0.0
var _running := false


func _init(creature: CreatureDef) -> void:
	def = creature
	centered = false
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_timer.timeout.connect(_advance)
	add_child(_timer)


func set_layer(new_layer: String) -> void:
	if new_layer == layer:
		return
	layer = new_layer
	var sheet: Dictionary = def.layers[layer]
	texture = sheet["texture"]
	var frame_size: Vector2i = sheet["frame_size"]
	hframes = sheet["columns"]
	vframes = maxi(1, texture.get_height() / frame_size.y)
	offset = -Vector2(sheet["anchor"])
	anim = ""
	mark_changed()


## Draws the same layer, animation and frame from `other`, a def with the same layers and
## frame order at another size (an avatar's depth sheets). The animation keeps its timing.
func use_sheets(other: CreatureDef) -> void:
	if other == def:
		return
	def = other
	var keep_layer := layer
	var keep_anim := anim
	var keep_frame := frame
	layer = ""
	if keep_layer != "" and def.has_layer(keep_layer):
		set_layer(keep_layer)
		anim = keep_anim
		frame = clampi(keep_frame, 0, hframes * vframes - 1)
	mark_changed()


## Plays `anim_name`, or the layer's idle if this sheet does not have it (a
## placeholder, or an asset still missing an animation).
func play(anim_name: String) -> void:
	anim_name = def.animation_or_fallback(layer, anim_name)
	if anim_name == "":
		return
	var a: Dictionary = def.layers[layer]["animations"][anim_name]
	anim = anim_name
	_frames.assign(a["frames"])
	_loop = a["loop"]
	_index = 0
	frame = _frames[0]
	mark_changed()
	_timer.stop()
	_fps = float(a["fps"])
	_acc = 0.0
	_running = _frames.size() > 1
	if _frames.size() > 1:
		if not driven:
			_timer.wait_time = 1.0 / _fps
			_timer.start()
	elif not _loop:
		finished.emit.call_deferred()


## For a `driven` sprite: `dt` seconds of its animation, at most one frame per call (so it never
## outruns the tick that drives it). True if the frame changed.
func step(dt: float) -> bool:
	if not driven or not _running or _fps <= 0.0:
		return false
	_acc += dt
	if _acc < 1.0 / _fps:
		return false
	_acc = fmod(_acc, 1.0 / _fps)
	_advance()
	return true


func _advance() -> void:
	_index += 1
	if _index >= _frames.size():
		if not _loop:
			_timer.stop()
			_running = false
			_index = _frames.size() - 1
			finished.emit()
			return
		_index = 0
	frame = _frames[_index]
	mark_changed()


## Holds one frame of the sheet (growth stages are frames, not an animation).
func show_frame(index: int) -> void:
	_timer.stop()
	_running = false
	anim = ""
	frame = clampi(index, 0, hframes * vframes - 1)
	mark_changed()


func move_to(point: Vector2) -> void:
	if point != position:
		position = point
		mark_changed()


func mark_changed() -> void:
	if is_inside_tree():
		WindowChrome.redraw(get_viewport())
