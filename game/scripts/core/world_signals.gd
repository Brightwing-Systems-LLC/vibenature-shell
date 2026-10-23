class_name WorldSignals
extends Node

## What the world reacts to (proposal 0003): sunlight, cloud, bird_roll, fish_roll.
## Agents (G3) and the rhythm both feed it; per-day ceilings apply to the total so
## a busy day is livelier but never limitless. Nothing here knows about sessions.

signal world_signal(kind: String, source: String)
signal golden_window_changed(active: bool)

var clock: GameClock
var dawn_minutes := 300
var ceilings: Dictionary = {}
var _day := ""
var _counts: Dictionary = {}
var _golden_sources: Dictionary = {}


func setup(game_clock: GameClock, day_dawn_minutes: int, daily_ceilings: Dictionary) -> void:
	clock = game_clock
	dawn_minutes = day_dawn_minutes
	ceilings = daily_ceilings


## Returns false when today's ceiling for `kind` is already reached.
func send(kind: String, source: String) -> bool:
	var day := clock.game_day_key(dawn_minutes)
	if day != _day:
		_day = day
		_counts.clear()
	var count := int(_counts.get(kind, 0))
	if ceilings.has(kind) and count >= int(ceilings[kind]):
		return false
	_counts[kind] = count + 1
	world_signal.emit(kind, source)
	return true


func count_today(kind: String) -> int:
	if clock.game_day_key(dawn_minutes) != _day:
		return 0
	return int(_counts.get(kind, 0))


func set_golden(source: String, active: bool) -> void:
	var was := is_golden()
	if active:
		_golden_sources[source] = true
	else:
		_golden_sources.erase(source)
	if is_golden() != was:
		golden_window_changed.emit(is_golden())


func is_golden() -> bool:
	return not _golden_sources.is_empty()
