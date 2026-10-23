class_name AgentSessions
extends RefCounted

## The player's agents as the world sees them (SPEC §5.2), in memory only: which sessions are
## open and whether each is busy, keyed by a hash nobody can turn back into a session. Never
## saved. Pure (time comes in as an argument), for tests.
##
## turn_end  -> sunlight, a bird roll, a fish roll
## tool_fail -> a cloud (enough clouds rain, and rain waters the flower beds)
## needs_input -> nothing in the world; the session is waiting on the player, so not busy
## still_busy -> nothing; the session's turn is still running (a keep-alive), so busy again
## The scene's two beats, per session (issue 308):
## `beat` is "hand_off" after a `turn_start` from a session that was not busy (a `turn_start` for a
## busy one, as old installs send for each tool, is a keep-alive), "turn_done" after a `turn_end`
## that ends a turn this session had open, else "".
## Golden window: at least `golden_min_sessions` open and every one of them busy.
## Long stretch: some agent busy, with no break of `break_minutes`, for `long_stretch_hours`.
## A busy session with no event for `busy_timeout_minutes` counts as idle (a turn interrupted,
## crashed or killed never sends its end); any later event from it counts again as usual.

const TURN_END_SIGNALS: Array[String] = ["sunlight", "bird_roll", "fish_roll"]

## session_hash -> {"busy": bool, "seen": float, "turn": bool (a turn is open: started, not ended)}
var sessions: Dictionary = {}
## What the last `apply` means for the scene: "hand_off", "turn_done" or "".
var beat := ""
var tuning: Dictionary = {}
var _stretch_start := -1.0
var _last_active := -1.0
var _was_busy := false


func _init(bridge_tuning: Dictionary, long_stretch_hours: float) -> void:
	tuning = bridge_tuning.duplicate()
	tuning["long_stretch_hours"] = long_stretch_hours


## Applies one accepted event at `now`; returns the world signals it sends.
func apply(event: Dictionary, now: float) -> Array[String]:
	var session := String(event["session_hash"])
	var kind := String(event["kind"])
	var out: Array[String] = []
	beat = ""
	_note_activity(now)
	if kind == "session_end":
		sessions.erase(session)
	else:
		# A session the game has not seen start (it opened before the game did) joins on its first event.
		if not sessions.has(session):
			sessions[session] = {"busy": false, "seen": now, "turn": false}
		var entry: Dictionary = sessions[session]
		entry["seen"] = now
		match kind:
			"turn_start":
				if not bool(entry["busy"]):
					beat = "hand_off"
				entry["busy"] = true
				entry["turn"] = true
			"still_busy":
				entry["busy"] = true
			"turn_end":
				if bool(entry["busy"]) or bool(entry.get("turn", false)):
					beat = "turn_done"
				entry["busy"] = false
				entry["turn"] = false
				out.append_array(TURN_END_SIGNALS)
			"tool_fail":
				out.append("cloud")
			"needs_input":
				entry["busy"] = false
	_note_activity(now)
	return out


## Forgets sessions silent for `session_stale_hours` (an agent that crashed without ending), and
## lets a busy one silent for `busy_timeout_minutes` go idle. True if any went or went idle.
func expire(now: float) -> bool:
	var stale := float(tuning["session_stale_hours"]) * 3600.0
	var silent := float(tuning["busy_timeout_minutes"]) * 60.0
	var gone := false
	for session in sessions.keys():
		var entry: Dictionary = sessions[session]
		var quiet := now - float(entry["seen"])
		if quiet > stale:
			sessions.erase(session)
			gone = true
		elif bool(entry["busy"]) and quiet > silent:
			entry["busy"] = false
			gone = true
	_note_activity(now)
	return gone


func busy_count() -> int:
	var count := 0
	for session in sessions:
		if bool(sessions[session]["busy"]):
			count += 1
	return count


## Minutes since the current stretch of work began, while some agent is busy; else 0.
func busy_minutes(now: float) -> float:
	if busy_count() == 0 or _stretch_start < 0.0:
		return 0.0
	return maxf(0.0, now - _stretch_start) / 60.0


func golden() -> bool:
	return sessions.size() >= int(tuning["golden_min_sessions"]) and busy_count() == sessions.size()


func long_stretch(now: float) -> bool:
	_note_activity(now)
	if _stretch_start < 0.0:
		return false
	if not _was_busy and now - _last_active > float(tuning["break_minutes"]) * 60.0:
		return false
	return now - _stretch_start >= float(tuning["long_stretch_hours"]) * 3600.0


## A stretch starts with the first busy moment after a break of `break_minutes` with no agent
## busy, and goes on while some agent is busy (a long turn sends no events, and is no break).
func _note_activity(now: float) -> void:
	var busy := busy_count() > 0
	if busy and not _was_busy and (_stretch_start < 0.0 or now - _last_active > float(tuning["break_minutes"]) * 60.0):
		_stretch_start = now
	if busy or _was_busy:
		_last_active = now
	_was_busy = busy
