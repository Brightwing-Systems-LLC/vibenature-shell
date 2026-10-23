class_name SceneShelter
extends RefCounted

## When you go to shelter in the van from the rain and when you come back
## (issue 476). Pure: fed the rain's strength each step
## (`SceneWeather.rain`, 0..1) and whether you can move now; returns "go", "back" or "".
##
## You go as the first drops show (the human, PR 484: no beat sitting in the rain): the rain at `go_rain` or more,
## just over what `SceneRain` draws any drops at, for `go_sec`, a fraction of a second; under `go_rain` the count
## starts again. Back once it has stayed under `back_rain` (no drops drawn) for `back_sec`; any rain at `back_rain` or
## more starts that wait again, so a lull between bursts never brings you out. Tuning `scene.day.shelter` in balance.json.
## The daily rhythm stays the authority on arrival and departure: the scene `reset`s this whenever the van goes.

var tuning: Dictionary
## You are in the van (or on your way to it).
var inside := false
## Seconds the rain has shown at `go_rain` or more (outside), and stayed under `back_rain` (inside).
var wet_sec := 0.0
var dry_sec := 0.0


func _init(shelter_tuning: Dictionary) -> void:
	tuning = shelter_tuning


## One step of `dt` seconds with the rain at `rain`. `can_go`: you are seated and free to get up; `can_back`: you
## are in the van and nothing keeps you there (the wrap-up). A word is returned once, as `inside` changes.
func step(dt: float, rain: float, can_go: bool, can_back: bool) -> String:
	if not inside:
		dry_sec = 0.0
		if rain >= float(tuning["go_rain"]):
			wet_sec += dt
		else:
			wet_sec = 0.0
		if wet_sec >= float(tuning["go_sec"]) and can_go:
			inside = true
			wet_sec = 0.0
			return "go"
		return ""
	wet_sec = 0.0
	if rain < float(tuning["back_rain"]):
		dry_sec += dt
	else:
		dry_sec = 0.0
	if dry_sec >= float(tuning["back_sec"]) and can_back:
		inside = false
		dry_sec = 0.0
		return "back"
	return ""


## The van came or went (the rhythm): start over, out of the van.
func reset() -> void:
	inside = false
	wet_sec = 0.0
	dry_sec = 0.0
