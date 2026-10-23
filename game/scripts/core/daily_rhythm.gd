class_name DailyRhythm
extends RefCounted

## When the van brings you to the scene and when it takes you away
## (issue 198, proposal 2026-10-18-daily-rhythm).
## Pure: fed the busy edges (`turn`), the Mac's day signals (`mac`: sleep, wake, lock, unlock), and
## a clock; each call returns what the scene should play, in order:
##   "arrive" (the van drives in, you step out and sit), "arrive_now" (already there: the app started),
##   "leave" (you walk to the van and it drives off), "leave_now" (gone without a show),
##   "invite" (the wrap-up time: golden light, you stand and pack, the van's lights on),
##   "stay" (you keep working: you sit back down, the lights go off).
##
## No workday: arrival is your first sign of the day (a turn, a wake, an unlock, or starting the
## app), never at night, once per game day. With a start-of-day time set (issue 431) only you at this Mac after it
## brings the van: unlocked, and the last keyboard or mouse input within `present_within_sec` (the native
## extension's idle seconds, the only thing read); agent activity alone never does. Departure is the evening after a long quiet, or a long
## lock or sleep in the evening, and always by night; a lunch break or a meeting never sends the
## van away. Nothing here is saved, shown as a number, or told to anyone: it keeps only what the
## next decision needs (today's key, the last sign of life, when the Mac went away).

var clock: GameClock
var phases: DayPhases
var tuning: Dictionary
## The wrap-up time in minutes of the day, or -1 when off (Settings.wrap_up_minutes).
var wrap_minutes := -1
## The start-of-day time in minutes of the day, or -1 when off (Settings.start_of_day_minutes; issue 431).
var start_minutes := -1
## Seconds since the last keyboard or mouse input (the native extension's one number), or -1 when unknown
## (headless, another platform): then a wake, an unlock or starting the app counts as being here.
var idle_sec := -1.0
var here := false
var busy := false
## "" (none), "invited" (the wrap-up is on now), "staying" (you kept working; it never repeats today).
var wrap := ""
var _arrived_day := ""
var _left_day := ""
var _wrap_day := ""
var _last_active := 0.0
var _invited_at := 0.0
## Why the Mac is away ("asleep", "locked") and since when (unix).
var _away := {}


func _init(game_clock: GameClock, day_phases: DayPhases, rhythm_tuning: Dictionary, wrap_up_minutes: int = -1) -> void:
	clock = game_clock
	phases = day_phases
	tuning = rhythm_tuning
	wrap_minutes = wrap_up_minutes
	_last_active = clock.now()


## The app started: you are already at the log if it is a time for it (no drive-in). With a start-of-day time,
## only if the van already came earlier this game day (`van_day`, the day it last came); otherwise it drives in now
## if you are here after the start time, or waits for you.
func launched(van_day: String = "") -> Array:
	_last_active = clock.now()
	if wrap_minutes >= 0 and _minutes_since(wrap_minutes) >= 0.0:
		_wrap_day = _day()
	if start_minutes < 0 or van_day == _day():
		return _sign(true)
	return _greet(true)


## A busy edge: the first agent getting busy (true) or the last one going idle (false).
func turn(now_busy: bool) -> Array:
	busy = now_busy
	_last_active = clock.now()
	var out: Array = []
	if now_busy and here and wrap == "invited":
		out = _stay()
	if start_minutes < 0:
		out.append_array(_sign(false))
	return out


## The Mac's day signal: "sleep", "wake", "lock" or "unlock". `since` is when it went away when
## known better than now (a sleep is only seen after the wake, so the last poll before it).
func mac(kind: String, since: float = -1.0) -> Array:
	var at := clock.now() if since < 0.0 else since
	match kind:
		"sleep", "lock":
			var why := "asleep" if kind == "sleep" else "locked"
			if not _away.has(why):
				_away[why] = at
			if here and wrap == "invited":
				return _leave(kind == "sleep")
			return []
		"wake", "unlock":
			# The stretch away counts first (it may have been a long evening), quietly after a sleep.
			var out := tick(kind == "wake")
			_away.erase("asleep" if kind == "wake" else "locked")
			_last_active = clock.now()
			out.append_array(_sign(false) if start_minutes < 0 else _greet(true))
			return out
	return []


## The clock moved on: checked every few seconds. `quietly` when the Mac has just woken, so a
## departure that came due while it slept happens without a show.
func tick(quietly: bool = false) -> Array:
	var now := clock.now()
	var day := _day()
	if here and _arrived_day != day:
		return _leave(true)
	if not here:
		if wrap_minutes >= 0 and _wrap_day != day and _minutes_since(wrap_minutes) >= float(tuning["wrap_grace_min"]):
			_wrap_day = day
		return _greet(false) if start_minutes >= 0 else []
	if _night():
		return _leave(quietly)
	if wrap == "invited":
		if away_since() >= 0.0:
			return _leave(quietly)
		if busy and now - _invited_at >= float(tuning["wrap_decide_min"]) * 60.0:
			return _stay()
		if not busy and now - maxf(_last_active, _invited_at) >= float(tuning["wrap_quiet_min"]) * 60.0:
			return _leave(quietly)
		return []
	if wrap_minutes >= 0 and _wrap_day != day:
		var since := _minutes_since(wrap_minutes)
		if since >= 0.0:
			_wrap_day = day
			if since < float(tuning["wrap_grace_min"]) and away_since() < 0.0:
				wrap = "invited"
				_invited_at = now
				return ["invite"]
	var dusk := _minutes_since(phases.start_of("dusk"))
	if dusk >= 0.0:
		var dusk_at := now - dusk * 60.0
		if not busy and now - _last_active >= float(tuning["evening_quiet_hours"]) * 3600.0:
			return _leave(quietly)
		var away := away_since()
		if away >= 0.0 and now - maxf(away, dusk_at) >= float(tuning["evening_away_min"]) * 60.0:
			return _leave(quietly)
	return []


## When the Mac went away (asleep or locked, the earlier), or -1 while it is in use.
func away_since() -> float:
	var at := -1.0
	for why in _away:
		at = float(_away[why]) if at < 0.0 else minf(at, float(_away[why]))
	return at


## Whether you are at this Mac: not asleep or locked, and the last input within `present_within_sec`. With no
## reading (`idle_sec` -1) the caller's own evidence decides (`unknown`: a wake, an unlock, starting the app).
func present(unknown: bool = false) -> bool:
	if away_since() >= 0.0:
		return false
	if idle_sec < 0.0:
		return unknown
	return idle_sec <= float(tuning["present_within_sec"])


## With a start-of-day time: the van drives in at the first moment after it that you are here (issue 431).
func _greet(unknown: bool) -> Array:
	if start_minutes < 0 or _minutes_since(start_minutes) < 0.0 or not present(unknown):
		return []
	return _sign(false)


## The debug panel's "Van arrives" and "Van leaves" (issue 431): the whole sequence now, and the rhythm agrees.
func debug_play(what: String) -> Array:
	if what == "arrive":
		var out: Array = ["leave_now"] if here else []
		here = true
		_arrived_day = _day()
		wrap = ""
		_last_active = clock.now()
		out.append("arrive")
		return out
	var before: Array = [] if here else ["arrive_now"]
	if not here:
		_arrived_day = _day()
	before.append_array(_leave(false))
	return before


## The native extension's idle seconds ("<seconds>"), or -1 when there is none or it is not a number.
static func parse_idle(value: String) -> float:
	var text := value.strip_edges()
	return float(text) if text.is_valid_int() and int(text) >= 0 else -1.0


func _sign(instant: bool) -> Array:
	var day := _day()
	if here or _night() or _left_day == day:
		return []
	here = true
	_arrived_day = day
	wrap = ""
	_last_active = clock.now()
	return ["arrive_now" if instant else "arrive"]


func _leave(quietly: bool) -> Array:
	here = false
	wrap = ""
	_left_day = _arrived_day
	return ["leave_now" if quietly else "leave"]


func _stay() -> Array:
	wrap = "staying"
	return ["stay"]


func _day() -> String:
	return clock.game_day_key(maxi(phases.start_of("dawn"), 0))


func _night() -> bool:
	return phases.is_night(clock.local_minutes())


## Minutes since `minute_of_day` today, within the game day (dawn to dawn), or -1 before it.
func _minutes_since(minute_of_day: int) -> float:
	if minute_of_day < 0:
		return -1.0
	var dawn := maxi(phases.start_of("dawn"), 0)
	var now_into := posmod(clock.local_minutes() - dawn, 1440)
	var then_into := posmod(minute_of_day - dawn, 1440)
	if now_into < then_into:
		return -1.0
	return float(now_into - then_into) + fposmod(clock.now(), 60.0) / 60.0


## The native extension's counts ("<sleeps> <wakes> <locks> <unlocks>"); zeros when there is none
## (headless, another platform). Nothing else is ever in it.
static func parse_counts(value: String) -> Array:
	var parts := value.strip_edges().split(" ", false)
	var out: Array = [0, 0, 0, 0]
	if parts.size() == 4:
		for i in 4:
			out[i] = int(parts[i]) if parts[i].is_valid_int() else 0
	return out


## The signals between two readings, in the order they must have happened: away first, then back.
static func new_edges(before: Array, after: Array) -> Array:
	var out: Array = []
	if before.size() != 4 or after.size() != 4:
		return out
	for i in [0, 2, 1, 3]:
		if int(after[i]) > int(before[i]):
			out.append(["sleep", "wake", "lock", "unlock"][i])
	return out
