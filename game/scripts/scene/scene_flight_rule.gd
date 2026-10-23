class_name SceneFlightRule
extends RefCounted

## When a bird may fly out over the desktop (Skypatch issue 120).
## Rare, and never blocked by agents working
## (issue 317: with parallel sessions the pond
## is busy all day, and a rule that waited for nobody working never flew): in the calm beat after
## any session's turn ends (by a chance per turn end, a few seconds after it), now and then as a
## hand-off's moment (a chance per prompt, within seconds), or in a quiet spell with no prompt for
## a while. Never with the player's switch off, never at night or in rain, at most `max_per_hour`
## in any hour and never two within `min_gap_min`. Tuning is `rule` in
## the scene package's `behaviour/flights/desktop.json`. Each flight planned or refused is said through
## `say` with its reason (no content: only the rule's own words). Seeded and clock-free (time
## comes in through `tick`). Pure.

var tuning: Dictionary = {}
var rng := RandomNumberGenerator.new()
## The player's switch (Config, General).
var enabled := true
var t := 0.0
## Seconds since the last prompt (hand-off) or flight.
var idle_for := 0.0
## When each flight in the last hour started (`t`).
var flown: Array = []
## Told one line for every flight planned or refused (for `build/dev/godot.out`).
var say: Callable
var _due := -1.0
var _due_why := ""
## The last context `tick` saw, for a refusal decided between ticks.
var _ctx := {}


func _init(rule_tuning: Dictionary, seed: int) -> void:
	tuning = rule_tuning
	rng.seed = seed


## A session's prompt (the hand-off). A calm beat's flight still to come is let go (the hand-off
## has its own moment); by a chance, the moment is a flight a second or few from now. True when it
## is (the director then adds no moment of its own).
func turn_started() -> bool:
	idle_for = 0.0
	if _due >= 0.0:
		_note("let go: %s flight, a prompt came first" % _due_why)
		_due = -1.0
	if not enabled or rng.randf() >= float(tuning["hand_off_chance"]):
		return false
	return _plan("hand-off", tuning["hand_off_delay_sec"])


## A session's turn ended (others may still work): by a chance, a flight in the calm beat.
func turn_ended() -> void:
	if enabled and _due < 0.0 and rng.randf() < float(tuning["turn_end_chance"]):
		_plan("turn-end", tuning["turn_end_delay_sec"])


func pending() -> bool:
	return _due >= 0.0


## Advances `dt` seconds. `ctx`: daylight (0..1), rain (0..1), flying (a flight is under way).
## True when a flight should start now; the caller says `flew()` when it does.
func tick(dt: float, ctx: Dictionary) -> bool:
	t += dt
	idle_for += dt
	_ctx = ctx
	if _due >= 0.0 and t >= _due:
		var why := _due_why
		_due = -1.0
		var no := refusal(ctx)
		if no == "":
			return true
		# A beat that cannot be used (night, rain, the hour's flights spent) is let go, not kept.
		_note("refused: %s flight, %s" % [why, no])
		return false
	if _due < 0.0 and idle_for >= float(tuning["idle_after_min"]) * 60.0 and rng.randf() < float(tuning["idle_per_hour"]) / 3600.0 * dt:
		var no := refusal(ctx)
		if no == "":
			_note("planned: quiet-spell flight, now (%.0f min without a prompt)" % (idle_for / 60.0))
			return true
		_note("refused: quiet-spell flight, %s" % no)
		# Not asked again every second of a long night: the spell starts over.
		idle_for = 0.0
	return false


## Everything that must hold for any flight, whatever asked for it.
func may_fly(ctx: Dictionary) -> bool:
	return refusal(ctx) == ""


## Why no flight may start now ("" when one may): off, flying, dark, rain, hour cap, gap.
func refusal(ctx: Dictionary) -> String:
	if not enabled:
		return "switched off"
	if bool(ctx.get("flying", false)):
		return "one is under way"
	if float(ctx.get("daylight", 0.0)) < float(tuning["min_daylight"]):
		return "too dark (daylight %.2f < %s)" % [float(ctx.get("daylight", 0.0)), tuning["min_daylight"]]
	if float(ctx.get("rain", 0.0)) > float(tuning["max_rain"]):
		return "rain (%.2f > %s)" % [float(ctx.get("rain", 0.0)), tuning["max_rain"]]
	_forget_old()
	if flown.size() >= int(tuning["max_per_hour"]):
		return "the hour's %d spent" % int(tuning["max_per_hour"])
	if not flown.is_empty() and t - float(flown[-1]) < float(tuning["min_gap_min"]) * 60.0:
		return "the gap (%.0f of %s min since the last)" % [(t - float(flown[-1])) / 60.0, tuning["min_gap_min"]]
	return ""


func flew() -> void:
	flown.append(t)
	idle_for = 0.0
	_due = -1.0


## A flight `why` in `delay` [min, max] s, unless one may not fly now (then refused, said why).
func _plan(why: String, delay: Array) -> bool:
	# Before the first tick the light is not known yet: the due time decides.
	var no := refusal(_ctx) if not _ctx.is_empty() else ""
	if no != "":
		_note("refused: %s flight, %s" % [why, no])
		return false
	var in_sec := rng.randf_range(float(delay[0]), float(delay[1]))
	_due = t + in_sec
	_due_why = why
	_note("planned: %s flight in %.1f s" % [why, in_sec])
	return true


func _note(line: String) -> void:
	if say.is_valid():
		say.call(line)


func _forget_old() -> void:
	while not flown.is_empty() and t - float(flown[0]) >= 3600.0:
		flown.pop_front()
