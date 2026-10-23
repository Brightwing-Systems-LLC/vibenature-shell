class_name DanceModel
extends RefCounted

## The waggle dance: a bee lights comb cells in order; the player repeats them.

var sequence: Array[int] = []
var progress := 0


## A sequence of `length` cells out of `cell_count`, no cell twice in a row.
func deal(cell_count: int, length: int, rng: RandomNumberGenerator) -> void:
	sequence.clear()
	progress = 0
	var last := -1
	for i in length:
		var cell := rng.randi() % cell_count
		if cell == last and cell_count > 1:
			cell = (cell + 1 + rng.randi() % (cell_count - 1)) % cell_count
		sequence.append(cell)
		last = cell


## "next" (right, keep going), "done" (the whole dance repeated) or "wrong".
func press(cell: int) -> String:
	if progress >= sequence.size():
		return "done"
	if sequence[progress] != cell:
		return "wrong"
	progress += 1
	return "done" if progress >= sequence.size() else "next"
