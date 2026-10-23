class_name GameClock
extends RefCounted

## The one place the game reads the time. Real local clock by default; tests and
## play-tests can pin it (`speed = 0`), move it (`advance`) or run it faster.

var speed := 1.0
## Minutes east of UTC. Defaults to the system's; tests pin it.
var tz_bias_min := 0
var _origin_real := 0.0
var _origin_game := 0.0


func _init(clock_speed: float = 1.0, start_unix: float = -1.0) -> void:
	speed = clock_speed
	tz_bias_min = int(Time.get_time_zone_from_system().get("bias", 0))
	_origin_real = Time.get_unix_time_from_system()
	_origin_game = _origin_real if start_unix < 0.0 else start_unix


## Unix seconds, game time.
func now() -> float:
	return _origin_game + (Time.get_unix_time_from_system() - _origin_real) * speed


func set_now(unix: float) -> void:
	_origin_game = unix
	_origin_real = Time.get_unix_time_from_system()


func advance(seconds: float) -> void:
	_origin_game += seconds


## Real seconds a timer must wait for `game_seconds` of game time to pass.
func real_seconds(game_seconds: float) -> float:
	if speed <= 0.0:
		return 1.0e9
	return maxf(0.05, game_seconds / speed)


func local(unix: float = -1.0) -> Dictionary:
	var t := now() if unix < 0.0 else unix
	return Time.get_datetime_dict_from_unix_time(int(t) + tz_bias_min * 60)


## Minutes since local midnight.
func local_minutes(unix: float = -1.0) -> int:
	var d := local(unix)
	return int(d["hour"]) * 60 + int(d["minute"])


## 0 = Sunday … 6 = Saturday.
func weekday(unix: float = -1.0) -> int:
	return int(local(unix)["weekday"])


func month(unix: float = -1.0) -> int:
	return int(local(unix)["month"])


func date_key(unix: float = -1.0) -> String:
	var d := local(unix)
	return "%04d-%02d-%02d" % [int(d["year"]), int(d["month"]), int(d["day"])]


## The game's day starts at dawn, not midnight: 03:00 still belongs to yesterday.
func game_day_key(dawn_minutes: int, unix: float = -1.0) -> String:
	var t := now() if unix < 0.0 else unix
	return date_key(t - dawn_minutes * 60.0)


## Unix time of the next local `minutes` (today if still ahead, else tomorrow).
func next_local_time(minutes: int, unix: float = -1.0) -> float:
	var t := now() if unix < 0.0 else unix
	var delta := (minutes - local_minutes(t)) * 60.0 - fmod(t, 60.0)
	if delta <= 0.0:
		delta += 86400.0
	return t + delta


## Whole local days between two game day keys ("2026-10-15").
static func days_between(from_key: String, to_key: String) -> int:
	if from_key == "" or to_key == "":
		return 0
	var a := Time.get_unix_time_from_datetime_string(from_key + "T12:00:00")
	var b := Time.get_unix_time_from_datetime_string(to_key + "T12:00:00")
	return int(round((b - a) / 86400.0))
