class_name IslandMigration
extends RefCounted

## Islands that became packs got new ids (`flower_bed_base` is now `flower_bed`; each pack
## lists its old ids under `formerly`). Saves and settings written before carry over: their
## states, places, ownership, dismissals and roster choices move to the new id. Where both
## ids are present the new one wins.


## Renames old ids in `saved` (in place) and in `settings` (saved to disk if anything moved).
static func rename(renames: Dictionary, saved: Dictionary, settings: Settings) -> void:
	if renames.is_empty():
		return
	for key in ["patches", "layout"]:
		if saved.get(key) is Dictionary:
			_rename_keys(saved[key], renames)
	if saved.get("collection") is Dictionary and saved["collection"].get("owned") is Dictionary:
		_rename_keys(saved["collection"]["owned"], renames)
	if saved.get("patch_ids") is Array:
		saved["patch_ids"] = _rename_list(saved["patch_ids"], renames)
	if settings == null:
		return
	var before := JSON.stringify(settings.data)
	settings.data["dismissed"] = _rename_list(settings.data.get("dismissed", []), renames)
	var roster: Dictionary = settings.data.get("roster", {})
	for key in ["chosen", "seasonal_off"]:
		if roster.get(key) is Array:
			roster[key] = _rename_list(roster[key], renames)
	if JSON.stringify(settings.data) != before:
		settings.save()


static func _rename_keys(d: Dictionary, renames: Dictionary) -> void:
	for old in renames:
		if d.has(old):
			if not d.has(renames[old]):
				d[renames[old]] = d[old]
			d.erase(old)


static func _rename_list(ids: Array, renames: Dictionary) -> Array:
	var out: Array = []
	for id in ids:
		var renamed := String(renames.get(String(id), String(id)))
		if not out.has(renamed):
			out.append(renamed)
	return out
