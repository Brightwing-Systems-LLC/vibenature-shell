class_name HiveModel
extends RefCounted

## The Beehive's rules. Honey fills over a few hours, faster while flowers bloom in
## the player's beds. A full hive waits, however long (§2.2). Collecting it empties
## the hive; failing the dance leaves the honey where it is.

var honey := 0.0
var updated_at := 0.0


## Brings the hive up to `now`. `bloom_bonus` is the extra rate (0.2 = 20% faster)
## from flowers blooming meanwhile.
func update(now: float, honey_hours: float, bloom_bonus: float) -> void:
	if updated_at <= 0.0 or now <= updated_at:
		updated_at = maxf(updated_at, now)
		return
	var hours := (now - updated_at) / 3600.0
	honey = minf(1.0, honey + hours / honey_hours * (1.0 + bloom_bonus))
	updated_at = now


## Starts the clock the first time the hive is seen.
func start(now: float) -> void:
	if updated_at <= 0.0:
		updated_at = now


func is_full() -> bool:
	return honey >= 1.0


## 0 (empty) … levels - 1 (full), for the hive's frames.
func level(levels: int) -> int:
	if is_full():
		return levels - 1
	return clampi(int(floor(honey * (levels - 1))), 0, levels - 1)


## Seconds of game time until the next level, or INF if full.
func seconds_to_next_level(levels: int, honey_hours: float, bloom_bonus: float) -> float:
	if is_full():
		return INF
	var step := 1.0 / float(levels - 1)
	var next := minf(1.0, (floor(honey / step) + 1.0) * step)
	return (next - honey) * honey_hours * 3600.0 / (1.0 + bloom_bonus)


func collect() -> bool:
	if not is_full():
		return false
	honey = 0.0
	return true


func to_dict() -> Dictionary:
	return {"honey": honey, "updated_at": updated_at}


func from_dict(d: Dictionary) -> void:
	honey = clampf(float(d.get("honey", 0.0)), 0.0, 1.0)
	updated_at = float(d.get("updated_at", 0.0))
