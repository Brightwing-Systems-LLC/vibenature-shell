class_name DayPhases
extends RefCounted

## The day's phases (dawn, morning, …, night) from "HH:MM" start times. Night wraps
## past midnight until dawn.

## Sorted [[start_minutes, name], …]
var starts: Array = []


func _init(phases: Dictionary) -> void:
	for phase_name in phases:
		starts.append([DayPhases.minutes(String(phases[phase_name])), String(phase_name)])
	starts.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


static func minutes(hh_mm: String) -> int:
	var parts := hh_mm.split(":")
	return int(parts[0]) * 60 + (int(parts[1]) if parts.size() > 1 else 0)


func phase_at(minute_of_day: int) -> String:
	if starts.is_empty():
		return ""
	var current: String = starts[-1][1]
	for entry in starts:
		if minute_of_day >= int(entry[0]):
			current = entry[1]
	return current


func start_of(phase: String) -> int:
	for entry in starts:
		if entry[1] == phase:
			return int(entry[0])
	return -1


func is_night(minute_of_day: int) -> bool:
	return phase_at(minute_of_day) == "night"
