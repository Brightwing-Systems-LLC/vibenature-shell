class_name SceneVariety
extends RefCounted

## Natural variation (issue 272): places are areas,
## not points, and never the same spot twice running; a path is one of a family, never the same line.
## Pure helpers, seeded by the caller's generator so a seed still gives the same day.


## A point from `sample` (a Callable returning a Vector2, or null when it found none) at least
## `min_gap` points from every point in `recent`; after `tries` draws, the one furthest from them.
static func apart(sample: Callable, recent: Array, min_gap: float, tries: int = 12) -> Variant:
	var best: Variant = null
	var best_d := -1.0
	for i in tries:
		var q: Variant = sample.call()
		if q == null:
			continue
		var d := nearest(q, recent)
		if d >= min_gap:
			return q
		if d > best_d:
			best_d = d
			best = q
	return best


## The distance from `q` to the nearest point of `recent` (INF when none is a point).
static func nearest(q: Vector2, recent: Array) -> float:
	var d := INF
	for r in recent:
		if r is Vector2:
			d = minf(d, q.distance_to(r))
	return d


## A name from `weights` ({name: weight}), the names in `recent` made `penalty` times as likely
## (the last one squared), so the same choice seldom comes twice running.
static func pick_fresh(rng: RandomNumberGenerator, weights: Dictionary, recent: Array, penalty: float = 0.2) -> String:
	var w := {}
	var total := 0.0
	for k in weights:
		var v := float(weights[k])
		if not recent.is_empty() and String(recent[-1]) == String(k):
			v *= penalty * penalty
		elif recent.has(k):
			v *= penalty
		w[k] = v
		total += v
	if total <= 0.0:
		return String(weights.keys()[0]) if not weights.is_empty() else ""
	var roll := rng.randf() * total
	for k in w:
		roll -= float(w[k])
		if roll <= 0.0:
			return String(k)
	return String(w.keys()[-1])


## `x` in [lo, hi]: a value past an end folds back in (by as much as it overshot) rather than piling
## up on the end, so a range's ends are no likelier than its middle.
static func fold(x: float, lo: float, hi: float) -> float:
	if hi <= lo:
		return lo
	var span := hi - lo
	var u := fposmod(x - lo, 2.0 * span)
	return lo + (u if u <= span else 2.0 * span - u)


## This animal's own pace, a few percent either side of its kind's (`share`, e.g. 0.06): fixed for
## its visit, so two of a kind never walk, beat or swim in lockstep.
static func pace(rng: RandomNumberGenerator, share: float) -> float:
	return 1.0 + rng.randf_range(-share, share)
