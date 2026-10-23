class_name PackagePacker
extends RefCounted

## Builds a distributable package from a development folder (contract §8, docs/package-format.md,
## issue 442): `<id>.vnpkg`, a stored zip of everything
## in `game/packages/<id>/` but Godot's sidecars, and, given Brightwing's private key, its detached signature
## `<id>.vnpkg.sig` (the island packs' scheme: `IslandSigning`). Development and release tooling only; the
## game itself never signs anything.
##
## The folder goes through the shell's own loader first (`ScenePackages.open`, as a debug build opens it:
## the format, the manifest, every code body through the gate's static check and compiled), so a package that
## packs is a package that loads. The built file is opened again the same way before it is signed.


## Packs the folder `source_dir` into `out_dir`/<id>.vnpkg. {"vnpkg", "id", "files", "bodies"} or {"error"}.
static func build(source_dir: String, out_dir: String) -> Dictionary:
	source_dir = source_dir.trim_suffix("/")
	var folder := ScenePackages.open(source_dir, false, [])
	if folder.problem != "":
		return {"error": "%s does not load: %s" % [source_dir, folder.problem]}
	if not folder.refused_bodies.is_empty():
		return {"error": "%s: the gate turned bodies away: %s" % [source_dir, folder.refused_bodies]}
	var files := packed_files(folder.files)
	DirAccess.make_dir_recursive_absolute(out_dir)
	var path := out_dir.path_join(folder.id + ".vnpkg")
	for stale in [path, path + ".sig"]:
		if FileAccess.file_exists(stale):
			DirAccess.remove_absolute(stale)
	var zip := ZIPPacker.new()
	if zip.open(path) != OK:
		return {"error": "cannot write %s" % path}
	# Stored, not deflated (package-format.md): PNG and OGG are compressed already, and a stored file reads
	# straight out of the zip.
	zip.compression_level = ZIPPacker.COMPRESSION_NONE
	for rel in files:
		var data := FileAccess.get_file_as_bytes(source_dir.path_join(rel))
		if zip.start_file(rel) != OK or zip.write_file(data) != OK or zip.close_file() != OK:
			zip.close()
			return {"error": "cannot add %s to %s" % [rel, path]}
	if zip.close() != OK:
		return {"error": "cannot finish %s" % path}
	var built := ScenePackages.open(path, false, [])
	if built.problem != "":
		return {"error": "the built %s does not load: %s" % [path.get_file(), built.problem]}
	if built.files != files:
		return {"error": "the built %s does not hold the folder's files" % path.get_file()}
	var code := Array(folder.code_bodies())
	code.sort()
	return {"vnpkg": path, "id": folder.id, "files": files.size(), "bodies": code}


## The files of a folder package that go into its `.vnpkg`: all of them but Godot's sidecars, sorted.
static func packed_files(folder_files: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for rel in folder_files:
		if not ScenePackage.SIDECARS.has(rel.get_extension().to_lower()):
			out.append(rel)
	out.sort()
	return out


## Signs `vnpkg_path` with `private_key`, writing `<vnpkg>.sig`, then checks the signature against `keys`
## (Brightwing's public key in a release) so a key that is not the pair of the shipped one fails here, not in
## the player's hands. The signature's path, or {"error"} as a String starting "error: ".
static func sign(vnpkg_path: String, private_key: CryptoKey, keys: Array[CryptoKey]) -> String:
	var sig_path := vnpkg_path + ".sig"
	var f := FileAccess.open(sig_path, FileAccess.WRITE)
	if f == null:
		return "error: cannot write %s" % sig_path
	f.store_string(IslandSigning.sign_file(vnpkg_path, private_key) + "\n")
	f.close()
	var opened := ScenePackages.open(vnpkg_path, true, keys)
	if opened.problem != "" or opened.trust != "official" or not opened.refused_bodies.is_empty():
		DirAccess.remove_absolute(sig_path)
		return "error: %s does not open as official with the shipped key (%s)" % [vnpkg_path.get_file(),
				opened.problem if opened.problem != "" else "trust %s" % opened.trust]
	return sig_path
