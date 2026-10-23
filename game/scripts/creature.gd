class_name Creature
extends Node

## A creature that visits patches. It belongs to no patch: each leg of its trip
## re-hosts its sprite in whichever window it is in (a patch layer, or the transit
## window). Per-frame work runs only while it is moving; perched, it costs one
## timer tick per idle frame.

signal arrived

var def: CreatureDef
var sprite: CreatureSprite
var flight: Dictionary
var transit: TransitWindow
var flight_layer_override := ""

var _pos := Vector2.ZERO
var _target := Vector2.ZERO
var _speed := 0.0
var _crossing := {}


func _init(creature: CreatureDef, flight_tuning: Dictionary, transit_window: TransitWindow) -> void:
	def = creature
	flight = flight_tuning
	transit = transit_window
	sprite = CreatureSprite.new(def)
	sprite.visible = false


## Godot turns processing on when a node with `_process` enters the tree; it stays
## off until the creature moves, so `_set_moving` and Pace keep count.
func _ready() -> void:
	set_process(false)


func transit_layer() -> String:
	var wanted := flight_layer_override if flight_layer_override != "" else String(flight["transit_layer"])
	if def.has_layer(wanted):
		return wanted
	return def.layers.keys()[0]


## Where the creature enters or leaves `patch` through the top, near `x`. Inside
## the window (fully visible) for a window crossing, just above it for the fallback.
func top_point(patch, x: float, outside: bool) -> Vector2:
	var sheet: Dictionary = def.layers[transit_layer()]
	var frame: Vector2i = sheet["frame_size"]
	var anchor: Vector2i = sheet["anchor"]
	var margin := float(flight["edge_margin_px"])
	var half := frame.x / 2.0
	var cx := clampf(x, half + margin, patch.art_size().x - half - margin)
	var y := float(anchor.y) + margin
	if outside:
		y = -float(frame.y - anchor.y)
	return Vector2(cx, y).round()


func fly_in(patch, spot_name: String, entry: Vector2) -> void:
	var spot: Vector2 = patch.spot_point(spot_name)
	var layers := def.layer_path(transit_layer(), patch.spot_layer(spot_name))
	_pos = entry
	for i in layers.size():
		_host(patch.layer_node(layers[i]), layers[i])
		sprite.play(def.flight_animation(layers[i]))
		await _move_to(entry.lerp(spot, float(i + 1) / layers.size()).round(), float(flight["patch_speed_px_per_sec"]))
	await land_at(patch, spot_name)


func land_at(patch, spot_name: String) -> void:
	var layer: String = patch.spot_layer(spot_name)
	_host(patch.layer_node(layer), layer)
	if def.has_animation(layer, "land"):
		sprite.play("land")
		await sprite.finished
	sprite.play("idle")


func fly_out(patch, exit: Vector2) -> void:
	var start := _pos
	if def.has_animation(sprite.layer, "leave"):
		sprite.play("leave")
		await sprite.finished
	var layers := def.layer_path(sprite.layer, transit_layer())
	for i in layers.size():
		_host(patch.layer_node(layers[i]), layers[i])
		sprite.play(def.flight_animation(layers[i]))
		await _move_to(start.lerp(exit, float(i + 1) / layers.size()).round(), float(flight["patch_speed_px_per_sec"]))


## Carries the creature in the transit window from `from_point` in one patch to
## `to_point` in another, following the destination if it is dragged meanwhile.
func cross_by_window(from_patch, from_point: Vector2, to_patch, to_point: Vector2) -> void:
	var start: Vector2 = from_patch.art_to_screen(from_point)
	var layer := transit_layer()
	_pos = Vector2(def.layers[layer]["anchor"])
	transit.place(start, def.layers[layer]["anchor"])
	_host(transit.host(), layer)
	sprite.play(def.flight_animation(layer))
	var end: Vector2 = to_patch.art_to_screen(to_point)
	var speed := float(flight["transit_speed_px_per_sec"]) * transit.scale_px
	_crossing = {
		"start": start, "to_patch": to_patch, "to_point": to_point, "t": 0.0,
		"duration": maxf(0.1, start.distance_to(end) / speed),
		"arc": float(flight["transit_arc_px"]) * transit.scale_px,
		"anchor": def.layers[layer]["anchor"],
	}
	_set_moving(true)
	await arrived
	_pos = to_point


## A quiet desktop crossing into the pond from open screen space. No window title or
## content is inspected; only the pond's screen position sets the flight destination.
func fly_from_desktop(to_patch, to_point: Vector2, start_screen: Vector2) -> void:
	var layer := transit_layer()
	var anchor: Vector2i = def.layers[layer]["anchor"]
	_pos = Vector2(anchor)
	transit.place(start_screen, anchor)
	_host(transit.host(), layer)
	sprite.play(def.flight_animation(layer))
	var end: Vector2 = to_patch.art_to_screen(to_point)
	var speed := float(flight["transit_speed_px_per_sec"]) * transit.scale_px
	_crossing = {
		"start": start_screen, "to_patch": to_patch, "to_point": to_point, "t": 0.0,
		"duration": maxf(0.1, start_screen.distance_to(end) / speed),
		"arc": float(flight["transit_arc_px"]) * transit.scale_px,
		"anchor": anchor,
	}
	_set_moving(true)
	await arrived
	_pos = to_point


## The focused pond's bird leaves in one continuous flight, ending beyond the
## visible desktop edge before its transit window is emptied.
func fly_to_desktop(from_patch, exit_screen: Vector2) -> void:
	var layer := transit_layer()
	var anchor: Vector2i = def.layers[layer]["anchor"]
	var start: Vector2 = from_patch.art_to_screen(_pos)
	transit.place(start, anchor)
	_pos = Vector2(anchor)
	_host(transit.host(), layer)
	sprite.play(def.flight_animation(layer))
	var speed := float(flight["transit_speed_px_per_sec"]) * transit.scale_px
	_crossing = {
		"start": start, "end_screen": exit_screen, "t": 0.0,
		"duration": maxf(0.1, start.distance_to(exit_screen) / speed),
		"arc": float(flight["transit_arc_px"]) * transit.scale_px,
		"anchor": anchor,
	}
	_set_moving(true)
	await arrived
	vanish()


## Fallback: leave through the top of one patch and arrive through the top of the
## other after the time the trip would take.
func cross_by_top(from_patch, to_patch) -> void:
	sprite.visible = false
	sprite.mark_changed()
	var distance: float = from_patch.art_to_screen(Vector2.ZERO).distance_to(to_patch.art_to_screen(Vector2.ZERO))
	var seconds: float = distance / (float(flight["transit_speed_px_per_sec"]) * from_patch.scale_px)
	await get_tree().create_timer(seconds).timeout


## The window the creature is drawn in right now, or null.
func host_window() -> Window:
	return sprite.get_window() if sprite.is_inside_tree() and sprite.visible else null


## Whether `art_point` (in the host window's art pixels) is on the creature's frame.
func hit(art_point: Vector2) -> bool:
	if host_window() == null or sprite.layer == "":
		return false
	var sheet: Dictionary = def.layers[sprite.layer]
	var rect := Rect2(_pos - Vector2(sheet["anchor"]), Vector2(sheet["frame_size"]))
	return rect.has_point(art_point)


func art_position() -> Vector2:
	return _pos


## Off stage: out of every window.
func vanish() -> void:
	_set_moving(false)
	_crossing = {}
	if sprite.get_parent() != null:
		sprite.mark_changed()
		sprite.get_parent().remove_child(sprite)


func _host(parent: Node2D, layer: String) -> void:
	if sprite.get_parent() != parent:
		if sprite.get_parent() != null:
			sprite.mark_changed()
			sprite.get_parent().remove_child(sprite)
		parent.add_child(sprite)
	sprite.set_layer(layer)
	sprite.visible = true
	sprite.position = _pos
	sprite.mark_changed()


func _move_to(target: Vector2, speed: float) -> void:
	_target = target
	_speed = speed
	_set_moving(true)
	await arrived


func _process(delta: float) -> void:
	if not _crossing.is_empty():
		_step_crossing(delta)
		return
	_pos = _pos.move_toward(_target, _speed * delta)
	sprite.move_to(_pos.round())
	if _pos == _target:
		_set_moving(false)
		arrived.emit()


func _step_crossing(delta: float) -> void:
	var c := _crossing
	c["t"] = minf(1.0, c["t"] + delta / c["duration"])
	var t: float = c["t"]
	var end: Vector2 = c["end_screen"] if c.has("end_screen") else c["to_patch"].art_to_screen(c["to_point"])
	var point: Vector2 = c["start"].lerp(end, t) - Vector2(0, c["arc"] * 4.0 * t * (1.0 - t))
	transit.place(point, c["anchor"])
	if t >= 1.0:
		_crossing = {}
		_set_moving(false)
		arrived.emit()


func _set_moving(moving: bool) -> void:
	if moving == is_processing():
		return
	set_process(moving)
	if moving:
		Pace.start_moving()
	else:
		Pace.stop_moving()
