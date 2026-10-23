class_name Pace
extends RefCounted

## The engine loop's sleep between iterations (low processor mode): long while
## everything is still, short while anything is moving so flight stays smooth.

static var idle_usec := OS.low_processor_usage_mode_sleep_usec
static var moving_usec := OS.low_processor_usage_mode_sleep_usec
static var _moving := 0


## Also clears the count: a rebuilt scene (a scale change) starts with nothing moving.
static func configure(idle: int, moving: int) -> void:
	idle_usec = idle
	moving_usec = moving
	_moving = 0
	_apply()


static func start_moving() -> void:
	_moving += 1
	_apply()


static func stop_moving() -> void:
	_moving = maxi(0, _moving - 1)
	_apply()


static func is_moving() -> bool:
	return _moving > 0


static func _apply() -> void:
	OS.low_processor_usage_mode_sleep_usec = moving_usec if _moving > 0 else idle_usec
