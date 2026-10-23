class_name SkyOverlay
extends Node2D

## The weather over one island, in the sky above it: a sun while a sunny spell is on, the
## clouds gathered toward rain, rain falling while it rains, and a few golden sparkles during
## the golden window. Placeholders in palette colours until the bench's weather art lands
## (assets sky_sun, sky_cloud, sky_rain, golden_sparkle). Battery (§2.8): it redraws only when
## the weather changes, and animates only while it rains, on a timer at `rain_fps`.

var weather: Weather
var signals: WorldSignals
var tuning: Dictionary
var width := 0
var sky_px := 0
var island_h := 0
var _frame := 0
var _rain_timer := Timer.new()


static func attach(patch: PatchWindow, game_weather: Weather, world: WorldSignals, sky_tuning: Dictionary) -> SkyOverlay:
	var sky := SkyOverlay.new()
	sky.weather = game_weather
	sky.signals = world
	sky.tuning = sky_tuning
	sky.width = patch.def.size.x
	sky.sky_px = patch.sky_px
	sky.island_h = patch.def.size.y
	patch.overlay().add_child(sky)
	return sky


func _ready() -> void:
	_rain_timer.wait_time = 1.0 / float(tuning["rain_fps"])
	_rain_timer.timeout.connect(func() -> void:
		_frame += 1
		_refresh())
	add_child(_rain_timer)
	weather.changed.connect(_on_weather)
	signals.golden_window_changed.connect(func(_active: bool) -> void: _refresh())
	_on_weather()


func _on_weather() -> void:
	if weather.raining and _rain_timer.is_stopped():
		_rain_timer.start()
	elif not weather.raining:
		_rain_timer.stop()
	_refresh()


func _refresh() -> void:
	queue_redraw()
	if is_inside_tree():
		WindowChrome.redraw(get_viewport())


## What the sky shows now, for tests and the snapshot report.
func state() -> Dictionary:
	return {"sun": weather.is_sunny(), "clouds": cloud_count(), "rain": weather.raining, "golden": signals.is_golden()}


func cloud_count() -> int:
	return int(tuning["rain_clouds"]) if weather.raining else weather.clouds


func _draw() -> void:
	var top := float(tuning["top_px"])
	if signals.is_golden():
		_draw_sparkles(top)
	if weather.is_sunny():
		_draw_sun(Vector2(width - float(tuning["sun_inset_px"]), top + float(tuning["sun_r_px"])))
	var count := cloud_count()
	for i in count:
		var x := width * (i + 1.0) / (count + 1.0)
		_draw_cloud(Vector2(roundf(x), top + float(tuning["cloud_y_px"])), weather.raining)
	if weather.raining:
		_draw_rain(top + float(tuning["cloud_y_px"]) + float(tuning["cloud_r_px"]))


func _draw_sun(at: Vector2) -> void:
	var r := float(tuning["sun_r_px"])
	for i in 8:
		var dir := Vector2.RIGHT.rotated(i * PI / 4.0)
		draw_circle((at + dir * (r + 5.0)).round(), 2.0, Color("fbb954"))
	draw_circle(at, r, Color("f9c22b"))
	draw_circle(at + Vector2(-r * 0.25, -r * 0.25), r * 0.5, Color("fbff86"))


func _draw_cloud(at: Vector2, rain: bool) -> void:
	var body := Color("9babb2") if rain else Color("ffffff")
	var under := Color("7f708a") if rain else Color("c7dcd0")
	var r := float(tuning["cloud_r_px"]) * (1.25 if rain else 1.0)
	draw_rect(Rect2(at.x - r * 1.6, at.y, r * 3.2, r * 0.7), under)
	draw_circle(at + Vector2(-r, 0), r * 0.75, body)
	draw_circle(at + Vector2(r, 0), r * 0.75, body)
	draw_circle(at + Vector2(0, -r * 0.4), r, body)
	draw_rect(Rect2(at.x - r * 1.6, at.y - 1, r * 3.2, r * 0.5), body)


func _draw_rain(from_y: float) -> void:
	var bottom := sky_px + island_h * float(tuning["rain_reach"])
	var gap := float(tuning["rain_gap_px"])
	var drop := float(tuning["rain_drop_px"])
	var step := drop + gap
	var col := 0
	var x := 6.0
	while x < width - 6:
		var y := from_y + fmod(_frame * float(tuning["rain_fall_px"]) + col * 5.0, step)
		while y < bottom:
			draw_rect(Rect2(x, y, float(tuning["rain_width_px"]), drop), Color("4d9be6"))
			y += step
		x += float(tuning["rain_column_px"])
		col += 1


func _draw_sparkles(top: float) -> void:
	var color := Color("f9c22b")
	var spots: Array = tuning["sparkles"]
	for spot in spots:
		var at := Vector2(roundf(width * float(spot[0])), roundf(top + float(spot[1])))
		var arm := float(tuning["sparkle_arm_px"])
		draw_rect(Rect2(at.x - arm, at.y, arm * 2.0 + 1.0, 1), color)
		draw_rect(Rect2(at.x, at.y - arm, 1, arm * 2.0 + 1.0), color)
		draw_rect(Rect2(at.x - 1, at.y - 1, 3, 3), Color("fbff86"))
