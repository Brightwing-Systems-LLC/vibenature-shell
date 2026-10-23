class_name Weather
extends Node

## Clouds gather from `cloud` signals; enough of them bring a short, gentle rain that
## waters every flower bed. Each `sunlight` signal brings a sunny spell of `sun_minutes`
## (a new one restarts it, never stacks), and is counted for the day.

signal rain_started
signal rain_stopped
## The sky changed: clouds, rain or sun. The sky overlay redraws on it.
signal changed

var clouds := 0
var sunlight_today := 0
var raining := false
var clock: GameClock
var _threshold := 3
var _rain_minutes := 10.0
var _sun_minutes := 20.0
var _sunny_until := 0.0
var _rain_timer := Timer.new()
var _sun_timer := Timer.new()


func setup(game_clock: GameClock, signals: WorldSignals, threshold: int, rain_minutes: float, sun_minutes: float = 20.0) -> void:
	clock = game_clock
	_threshold = threshold
	_rain_minutes = rain_minutes
	_sun_minutes = sun_minutes
	_rain_timer.one_shot = true
	_rain_timer.timeout.connect(_stop_rain)
	add_child(_rain_timer)
	_sun_timer.one_shot = true
	_sun_timer.timeout.connect(func() -> void: changed.emit())
	add_child(_sun_timer)
	signals.world_signal.connect(_on_signal)


func _on_signal(kind: String, _source: String) -> void:
	if kind == "sunlight":
		sunlight_today += 1
		_sunny_until = clock.now() + _sun_minutes * 60.0
		_sun_timer.start(clock.real_seconds(_sun_minutes * 60.0))
		changed.emit()
	elif kind == "cloud" and not raining:
		clouds += 1
		if clouds >= _threshold:
			clouds = 0
			raining = true
			print("VibeNature: rain")
			rain_started.emit()
			_rain_timer.start(clock.real_seconds(_rain_minutes * 60.0))
		changed.emit()


## The sun shows when a sunny spell is on and it is not raining.
func is_sunny() -> bool:
	return not raining and clock != null and clock.now() < _sunny_until


## The rain stops now (debug, snapshots); otherwise it stops on its own after `rain_minutes`.
func stop_rain() -> void:
	if raining:
		_rain_timer.stop()
		_stop_rain()


func _stop_rain() -> void:
	raining = false
	rain_stopped.emit()
	changed.emit()


func new_day() -> void:
	sunlight_today = 0


func to_dict() -> Dictionary:
	return {"clouds": clouds}


func from_dict(d: Dictionary) -> void:
	clouds = int(d.get("clouds", 0))
