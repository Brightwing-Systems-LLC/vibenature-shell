class_name PckDirectory
extends RefCounted

## Reads a Godot `.pck` without mounting it: its file list (so the loader can refuse a pack
## that would put files outside its own folder) and one file's bytes (its island.json, to
## check the version before anything is mounted). Reads the formats PCKPacker writes (3 and
## 4, with a directory offset); anything else, or an encrypted pack, is refused.

const MAGIC := 0x43504447  # "GDPC"
const FLAG_ENCRYPTED_DIR := 1
const FLAG_RELATIVE_BASE := 2
const FILE_ENCRYPTED := 1


## {"paths": [String] (without res://), "entries": {path: [offset, size]}} or {"error": String}.
static func list(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "cannot open %s" % path.get_file()}
	if file.get_length() < 32 or file.get_32() != MAGIC:
		return {"error": "not a Godot pack"}
	var format := file.get_32()
	if format < 3 or format > 4:
		return {"error": "pack format %d is not one this game reads" % format}
	file.get_32()  # engine major, minor, patch
	file.get_32()
	file.get_32()
	var flags := file.get_32()
	if flags & FLAG_ENCRYPTED_DIR:
		return {"error": "an encrypted pack"}
	var base := file.get_64() if flags & FLAG_RELATIVE_BASE else 0
	if not flags & FLAG_RELATIVE_BASE:
		file.get_64()
	var dir_offset := file.get_64()
	if dir_offset <= 0 or dir_offset >= file.get_length():
		return {"error": "the pack's directory is out of range"}
	file.seek(dir_offset)
	var count := file.get_32()
	var paths: Array[String] = []
	var entries := {}
	for i in count:
		var length := file.get_32()
		if length <= 0 or length > 4096 or file.get_position() + length > file.get_length():
			return {"error": "a damaged directory entry"}
		var raw := file.get_buffer(length)
		var end := raw.find(0)
		var name := (raw.slice(0, end) if end >= 0 else raw).get_string_from_utf8().trim_prefix("res://")
		var offset := file.get_64()
		var size := file.get_64()
		file.get_buffer(16)  # md5
		if file.get_32() & FILE_ENCRYPTED:
			return {"error": "an encrypted file in the pack"}
		paths.append(name)
		entries[name] = [base + offset, size]
	return {"paths": paths, "entries": entries}


## The bytes of `inner` (a path without res://) in the pack, or empty.
static func read(path: String, inner: String) -> PackedByteArray:
	var listing := list(path)
	if listing.has("error") or not listing["entries"].has(inner):
		return PackedByteArray()
	var at: Array = listing["entries"][inner]
	var file := FileAccess.open(path, FileAccess.READ)
	if int(at[0]) + int(at[1]) > file.get_length():
		return PackedByteArray()
	file.seek(int(at[0]))
	return file.get_buffer(int(at[1]))
