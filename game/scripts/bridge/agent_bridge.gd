class_name AgentBridge
extends Node

## Claude Code (and later cmux, Codex) to the world (SPEC §5, G3): the event server takes
## contract §2 events, AgentSessions turns them into world signals and the golden window, and
## WorldSignals' daily ceilings bound what any amount of activity can do. Nothing from an event
## is saved, printed or passed on beyond its kind.

signal long_stretch_changed(active: bool)
## Some agent is working, or none is (the day's rhythm: the van, the wrap-up). Only the edge: a
## second busy session sends nothing. The scene's moments come from `hand_off` and `turn_finished`.
signal busy_changed(busy: bool)
## A coarse lifecycle pulse; no session id or work content reaches listeners.
signal turn_started
## A hand-off (issue 308): a real turn start from a
## session that was not busy, whatever the others are doing. `edge`: it also made the pond busy (sent
## after `busy_changed`). Keep-alives (`still_busy`, or `turn_start` for a busy session) send nothing.
signal hand_off(edge: bool)
## A session's turn ended; `others_busy`: some other session is still working (sent after `busy_changed`).
signal turn_finished(others_busy: bool)

var server := EventServer.new()
var sessions: AgentSessions
var clock: GameClock
var signals: WorldSignals
var _check_timer := Timer.new()
var _long_stretch := false
var _any_busy := false
## When an accepted event last arrived this run (unix seconds; 0 = none yet), for Config's
## Connections tab. Only the time: nothing of what the event said.
var last_heard := 0.0
## The same per contract §2 source (`claude_code`, `codex`, ...), for each harness's card.
var last_heard_from := {}


## `port` 0 takes any free port (tests, snapshots); the real game uses `bridge.port`.
func setup(game_clock: GameClock, world: WorldSignals, bridge_tuning: Dictionary, long_stretch_hours: float, port: int) -> void:
	clock = game_clock
	signals = world
	sessions = AgentSessions.new(bridge_tuning, long_stretch_hours)
	add_child(server)
	server.event_received.connect(receive)
	if server.start(port, bridge_tuning):
		print("VibeNature: listening for agents on 127.0.0.1:%d" % server.port())
	_check_timer.wait_time = float(bridge_tuning["check_sec"])
	_check_timer.timeout.connect(_check)
	add_child(_check_timer)


## One accepted event (from the server, or the debug panel).
func receive(event: Dictionary) -> void:
	last_heard = clock.now()
	last_heard_from[String(event.get("source", ""))] = last_heard
	for kind in sessions.apply(event, clock.now()):
		signals.send(kind, "agent")
	var beat := sessions.beat
	_update()
	if event["kind"] == "turn_start":
		turn_started.emit()
	if beat == "hand_off":
		hand_off.emit(sessions.busy_count() == 1)
	elif beat == "turn_done":
		turn_finished.emit(sessions.busy_count() > 0)


func long_stretch() -> bool:
	return _long_stretch


func any_busy() -> bool:
	return _any_busy


## Minutes of agent work without a break so far (0 while no agent is busy).
func busy_minutes() -> float:
	return sessions.busy_minutes(clock.now())


## The slow check runs only while a session is open or a long stretch is on: stale sessions
## go, a busy one silent for `busy_timeout_minutes` goes idle (the last one sends the idle edge),
## and the long stretch can begin or end without an event.
func _check() -> void:
	sessions.expire(clock.now())
	_update()


func _update() -> void:
	signals.set_golden("agents", sessions.golden())
	var busy := sessions.busy_count() > 0
	if busy != _any_busy:
		_any_busy = busy
		busy_changed.emit(busy)
	var stretch := sessions.long_stretch(clock.now())
	if stretch != _long_stretch:
		_long_stretch = stretch
		long_stretch_changed.emit(stretch)
	if sessions.sessions.is_empty() and not _long_stretch:
		_check_timer.stop()
	elif _check_timer.is_stopped() and is_inside_tree():
		_check_timer.start()


## The light's phase: the clock's, or one step toward dusk after a long stretch of agent work
## (SPEC §5.2). Never past dusk, and never at night or dawn.
static func light_phase(phases: DayPhases, local_minutes: int, long_stretch: bool) -> String:
	var phase := phases.phase_at(local_minutes)
	if not long_stretch:
		return phase
	var order := ["morning", "midday", "golden_hour", "dusk"]
	var at := order.find(phase)
	if at < 0 or at == order.size() - 1:
		return phase
	return String(order[at + 1])
