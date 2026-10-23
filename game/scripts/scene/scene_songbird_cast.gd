class_name SceneSongbirdCast
extends RefCounted

## Which of the bench's songbirds a party is (Skypatch issue 134):
## one species per party, from the species data's `cast`. Each member has a weight, its months (all
## year when it does not say), a `twilight` boost in a bell around first and last light, and a
## `habit` the kit must have room for (`perch`, `ground`, `trunk`, `flowers`). A hummingbird comes
## only in summer and only where there are flowers; a cardinal pair is likeliest at dawn and dusk.
## Seeded through the caller's dice. Pure.

const TWILIGHT_MIN := 70.0


## The member to send, or {} when the species has no cast (the old single sheet plays).
## `ctx`: {month (1..12), minute, dawn, dusk, habits: {habit: true}}; `force` picks by id.
static func pick(cast: Array, ctx: Dictionary, rng: RandomNumberGenerator, force: String = "") -> Dictionary:
	if cast.is_empty():
		return {}
	if force != "":
		for m in cast:
			if String(m.get("id", "")) == force:
				return m
	var options: Array = []
	var total := 0.0
	for m in cast:
		var w := weight(m, ctx)
		if w > 0.0:
			options.append([m, w])
			total += w
	if options.is_empty():
		return {}
	var roll := rng.randf() * total
	for o in options:
		roll -= float(o[1])
		if roll <= 0.0:
			return o[0]
	return options[-1][0]


## How likely `member` is now, 0 when out of season or when the kit has no place for its habit.
static func weight(member: Dictionary, ctx: Dictionary) -> float:
	var w := float(member.get("weight", 1.0))
	var months: Array = member.get("months", [])
	if not months.is_empty() and not int(ctx.get("month", 6)) in months.map(func(x) -> int: return int(x)):
		return 0.0
	var habit := String(member.get("habit", "perch"))
	var habits: Dictionary = ctx.get("habits", {})
	if habit != "perch" and not bool(habits.get(habit, false)):
		return 0.0
	var boost := float(member.get("twilight", 1.0))
	if boost != 1.0 and ctx.has("minute"):
		var m := float(ctx["minute"])
		var near := minf(_circular(m - float(ctx.get("dawn", 360.0))), _circular(m - float(ctx.get("dusk", 1140.0))))
		w *= lerpf(1.0, boost, exp(-0.5 * pow(near / TWILIGHT_MIN, 2.0)))
	return w


static func _circular(d: float) -> float:
	var x := fposmod(d, 1440.0)
	return minf(x, 1440.0 - x)


## The month (1..12) at `unix` seconds, local time.
static func month_of(unix: float) -> int:
	var bias := float(Time.get_time_zone_from_system().get("bias", 0)) * 60.0
	return int(Time.get_datetime_dict_from_unix_time(int(unix + bias)).get("month", 6))
