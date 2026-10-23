class_name IslandPacker
extends RefCounted

## Builds an installable island pack from a pack folder (a built-in one under game/islands/,
## or the bench's working copy): `<id>.pck` with every file under res://islands/<id>/, and,
## given a private key, its detached signature `<id>.pck.sig`. Development and tests only;
## the game itself never signs anything.

const SKIP_SUFFIXES: Array[String] = [".uid", ".import", ".DS_Store"]


## Packs `source_dir` into `out_dir`. `overrides` are merged into the copy's island.json: an
## `id` re-ids the copy (and its mount folder), for tests and for trying a variant beside the
## original. {"pck", "id"} or {"error"}.
static func build(source_dir: String, out_dir: String, overrides: Dictionary = {}) -> Dictionary:
	var manifest_path := source_dir.path_join(IslandPack.MANIFEST)
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary:
		return {"error": "no readable %s in %s" % [IslandPack.MANIFEST, source_dir]}
	var manifest: Dictionary = parsed
	manifest.merge(overrides, true)
	var id := String(manifest.get("id", ""))
	if not RegEx.create_from_string(IslandPack.ID_PATTERN).search(id):
		return {"error": "id %s is not snake_case" % id}
	DirAccess.make_dir_recursive_absolute(out_dir)
	var files: Array[String] = []
	_walk(source_dir, "", files)
	var pck_path := out_dir.path_join(id + ".pck")
	var packer := PCKPacker.new()
	if packer.pck_start(pck_path) != OK:
		return {"error": "cannot write %s" % pck_path}
	var rewritten := ""
	for rel in files:
		var from := source_dir.path_join(rel)
		if rel == IslandPack.MANIFEST and not overrides.is_empty():
			rewritten = out_dir.path_join(".%s.island.json" % id)
			FileAccess.open(rewritten, FileAccess.WRITE).store_string(JSON.stringify(manifest, "  "))
			from = rewritten
		if packer.add_file("res://islands/%s/%s" % [id, rel], from) != OK:
			return {"error": "cannot add %s" % rel}
	var flushed := packer.flush()
	if rewritten != "":
		DirAccess.remove_absolute(ProjectSettings.globalize_path(rewritten))
	if flushed != OK:
		return {"error": "cannot finish %s" % pck_path}
	return {"pck": pck_path, "id": id}


## Writes `<pck>.sig` for `pck_path` with `private_key`; returns its path.
static func sign(pck_path: String, private_key: CryptoKey) -> String:
	var sig_path := pck_path + ".sig"
	FileAccess.open(sig_path, FileAccess.WRITE).store_string(IslandSigning.sign_file(pck_path, private_key) + "\n")
	return sig_path


static func _walk(dir: String, rel: String, out: Array[String]) -> void:
	var here := dir.path_join(rel) if rel != "" else dir
	for file in DirAccess.get_files_at(here):
		# The bench's guides are for drawing, not for playing: they stay out of the pack.
		var skip := file.get_basename().contains("_guide")
		for suffix in SKIP_SUFFIXES:
			if file.ends_with(suffix):
				skip = true
		if not skip:
			out.append(rel.path_join(file) if rel != "" else file)
	for sub in DirAccess.get_directories_at(here):
		_walk(dir, rel.path_join(sub) if rel != "" else sub, out)
