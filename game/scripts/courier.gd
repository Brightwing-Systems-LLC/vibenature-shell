class_name Courier
extends Node

## Flies items (polaroids, fish, bouquets) across the desktop to the bin. The item is
## already in the bin when it sets off; the flight is only the picture of it, so
## quitting mid-flight loses nothing.

var scale_px := 2
var tuning: Dictionary = {}
var _flights: Array = []


func setup(scale: int, courier_tuning: Dictionary) -> void:
	scale_px = scale
	tuning = courier_tuning


func _ready() -> void:
	set_process(false)


## `target` returns the current screen point to fly to (the bin may be dragged).
func send(texture: Texture2D, from_screen: Vector2, target: Callable, on_arrive: Callable = Callable()) -> void:
	var size := Vector2i(texture.get_width(), texture.get_height())
	var window := TransitWindow.new()
	window.setup(size, scale_px)
	window.place(from_screen, size / 2)
	add_child(window)
	WindowChrome.draw_on_demand(window)
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	window.host().add_child(sprite)
	var end: Vector2 = target.call()
	var speed := float(tuning["speed_px_per_sec"]) * scale_px
	_flights.append({
		"window": window, "from": from_screen, "target": target, "on_arrive": on_arrive,
		"anchor": size / 2, "t": 0.0, "duration": maxf(0.2, from_screen.distance_to(end) / speed),
	})
	if not is_processing():
		set_process(true)
		Pace.start_moving()


func _process(delta: float) -> void:
	var arc := float(tuning["arc_px"]) * scale_px
	for flight in _flights.duplicate():
		var t := minf(1.0, float(flight["t"]) + delta / float(flight["duration"]))
		flight["t"] = t
		var end: Vector2 = flight["target"].call()
		var from: Vector2 = flight["from"]
		var point := from.lerp(end, t) - Vector2(0, arc * 4.0 * t * (1.0 - t))
		var window: TransitWindow = flight["window"]
		window.place(point, flight["anchor"])
		if t >= 1.0:
			_flights.erase(flight)
			window.queue_free()
			var on_arrive: Callable = flight["on_arrive"]
			if on_arrive.is_valid():
				on_arrive.call()
	if _flights.is_empty():
		set_process(false)
		Pace.stop_moving()
