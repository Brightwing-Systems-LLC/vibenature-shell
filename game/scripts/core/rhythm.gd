class_name Rhythm
extends Node

## The day's weather without any agent (proposal 0003): one plan per game day,
## seeded by the date so a restart does not reroll it, spread over the daylight (no workday
## since issue 198) and empty at night. It fires on a single timer, one event at a time, and
## never backfills events that passed while the game was closed.

var clock: GameClock
var settings: Settings
var signals: WorldSignals
var tuning: Dictionary
var plan: Array = []
var _day := ""
var _next := 0
var _timer := Timer.new()


func setup(game_clock: GameClock, player: Settings, world: WorldSignals, rhythm_tuning: Dictionary) -> void:
	clock = game_clock
	settings = player
	signals = world
	tuning = rhythm_tuning
	_timer.one_shot = true
	_timer.timeout.connect(_fire_due)
	add_child(_timer)
	_replan_if_new_day()
	_schedule_next()


## A day's plan: sorted [{"at": minutes_of_day, "kind": String}, …]. Pure, for tests.
static func plan_for_day(day_key: String, _weekday: int, player: Settings, rhythm_tuning: Dictionary) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(day_key + ":rhythm")
	var phases := player.day_phases()
	var day_start := phases.start_of("dawn")
	var day_end := phases.start_of("dusk")
	if day_start < 0 or day_end <= day_start:
		return []
	var events: Array = []
	for kind in ["sunlight", "cloud"]:
		var range_: Array = rhythm_tuning["%s_per_day" % kind]
		var count := rng.randi_range(int(range_[0]), int(range_[1]))
		for i in count:
			events.append({"at": rng.randi_range(day_start, day_end - 1), "kind": kind})
	var golden: Dictionary = rhythm_tuning["golden_window"]
	var start := DayPhases.minutes(String(golden["start"]))
	events.append({"at": start, "kind": "golden_start"})
	events.append({"at": start + int(golden["minutes"]), "kind": "golden_end"})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["at"]) < int(b["at"]))
	return events


func _replan_if_new_day() -> void:
	var day := clock.game_day_key(_dawn())
	if day == _day:
		return
	_day = day
	plan = Rhythm.plan_for_day(day, clock.weekday(), settings, tuning)
	# Skip what already passed today: the rhythm never backfills.
	var now_into := _minutes_into_day(clock.local_minutes())
	_next = 0
	var golden_now := false
	while _next < plan.size() and _minutes_into_day(int(plan[_next]["at"])) <= now_into:
		var kind := String(plan[_next]["kind"])
		if kind == "golden_start":
			golden_now = true
		elif kind == "golden_end":
			golden_now = false
		_next += 1
	signals.set_golden("rhythm", golden_now)


## The clock jumped (the debug panel): plan for the new day if it is one, and
## reschedule. Events the jump skipped over fire at once.
func on_time_jump() -> void:
	_timer.stop()
	_replan_if_new_day()
	_schedule_next()


func _dawn() -> int:
	return maxi(settings.day_phases().start_of("dawn"), 0)


## Minutes into the game day, counted from dawn, so night events sort after dusk.
func _minutes_into_day(minute_of_day: int) -> int:
	return (minute_of_day - _dawn() + 1440) % 1440


func _schedule_next() -> void:
	if _next < plan.size():
		var into := _minutes_into_day(int(plan[_next]["at"]))
		var now_into := _minutes_into_day(clock.local_minutes())
		var wait := (into - now_into) * 60.0 - fmod(clock.now(), 60.0) + 0.5
		_timer.start(clock.real_seconds(maxf(wait, 0.5)))
		return
	# Nothing left today: wake just after the next dawn and plan again.
	_timer.start(clock.real_seconds(clock.next_local_time(_dawn()) - clock.now() + 1.0))


func _fire_due() -> void:
	_replan_if_new_day()
	var now_into := _minutes_into_day(clock.local_minutes())
	while _next < plan.size() and _minutes_into_day(int(plan[_next]["at"])) <= now_into:
		var kind := String(plan[_next]["kind"])
		_next += 1
		match kind:
			"golden_start":
				signals.set_golden("rhythm", true)
			"golden_end":
				signals.set_golden("rhythm", false)
			_:
				signals.send(kind, "rhythm")
	_schedule_next()
