class_name ScenePackage
extends RefCounted

## One package (contract §8, proposal 2026-10-20-open-shell-and-scene-packages, §3): everything a place
## is (its kit, creatures, behaviour data, director, sky and weather, and for Brightwing's own packages
## its code bodies), or everything VibeNature is that is not a place (the companion). A folder
## `res://packages/<id>/` during development, or one file `<id>.vnpkg` (a stored zip of that folder) when
## distributed.
##
## `open` reads the manifest and the file list and fills `problem` with why the package cannot be used,
## or leaves it "". Data is read only as text (`read_text`, `read_json`), and art as raw files (`files_dir`);
## the shell never mounts a package and never loads a Godot resource from one. Code bodies go through
## `PackageGate` (`ScenePackages.open`).

const FORMAT := 1
const MANIFEST := "package.json"
const ID_PATTERN := "^[a-z][a-z0-9_]{1,39}$"
const KINDS: Array[String] = ["scene", "companion"]
## The only files a package may hold (§3).
const DATA_EXTENSIONS: Array[String] = ["json", "png", "ogg", "md", "txt"]
## Godot's own files beside a project folder's files (imports, uids, an export's remaps). Never read;
## allowed only in a development folder, never in a `.vnpkg`.
const SIDECARS: Array[String] = ["import", "uid", "remap", "gdc"]
const BODIES_DIR := "bodies"
const MAX_FILE_BYTES := 16 * 1024 * 1024
const MAX_PACKAGE_BYTES := 512 * 1024 * 1024
## Where a `.vnpkg`'s data files are written out for the art readers (`files_dir`); the variable overrides it.
const CACHE := "user://packages"
const CACHE_ENV := "VIBENATURE_PACKAGE_CACHE"
const UNPACKED := ".unpacked"

var id := ""
var kind := ""
var name := ""
var version := ""
var manifest: Dictionary = {}
## res://packages/<id> for a folder, the file's path for a `.vnpkg`.
var root := ""
var from_vnpkg := false
## "official" (signed by Brightwing, checked) or "community" (unsigned, or someone else's).
var trust := "community"
## Every file, relative to the package's root, sorted.
var files: PackedStringArray = PackedStringArray()
## The code bodies that passed the gate: "name@major" -> Script.
var bodies := {}
## Code bodies the gate turned away: "name@major" -> why (the package plays without them).
var refused_bodies := {}
## Why the package cannot be used at all, or "".
var problem := ""
var _zip: ZIPReader
var _files_dir := ""


## Reads the package at `path` (a folder, or a `.vnpkg` file): its file list and manifest, checked
## against the format. Code bodies are not compiled here (`ScenePackages.open` does that, through the gate).
static func read(path: String) -> ScenePackage:
	var pkg := ScenePackage.new()
	pkg.root = path.trim_suffix("/")
	pkg.from_vnpkg = path.get_extension() == "vnpkg"
	pkg.problem = pkg._read_files()
	if pkg.problem == "":
		pkg.problem = pkg._read_manifest()
	return pkg


func _read_files() -> String:
	var total := 0
	if from_vnpkg:
		_zip = ZIPReader.new()
		if _zip.open(root) != OK:
			return "not a readable package file"
		for f in _zip.get_files():
			if f.ends_with("/"):
				continue
			files.append(f)
	else:
		if not DirAccess.dir_exists_absolute(root):
			return "no package folder"
		_walk("", files)
	files.sort()
	for f in files:
		var why := path_problem(f, not from_vnpkg)
		if why != "":
			return why
		var size := _size_of(f)
		if size > MAX_FILE_BYTES:
			return "%s is over %d MB" % [f, MAX_FILE_BYTES / (1024 * 1024)]
		total += size
	if total > MAX_PACKAGE_BYTES:
		return "the package is over %d MB" % [MAX_PACKAGE_BYTES / (1024 * 1024)]
	return ""


## Why `rel` (a path inside a package) may not be there, or "": a path outside the package, or a file
## that is not data. A `.gd` is allowed only as a code body (`bodies/<name>@<major>.gd`; the gate decides
## whether it runs) and a `.gdshader` never in v1; Godot's sidecars only in a development folder.
static func path_problem(rel: String, folder: bool) -> String:
	if rel == "" or rel.begins_with("/") or rel.contains("\\") or rel.contains(":") or rel.contains("//"):
		return "%s is not a plain path inside the package" % rel
	for part in rel.split("/"):
		if part == ".." or part == ".":
			return "%s leads outside the package" % rel
	var ext := rel.get_extension().to_lower()
	if folder and SIDECARS.has(ext):
		return ""
	if DATA_EXTENSIONS.has(ext):
		return ""
	if ext == "gd" and is_body_path(rel):
		return ""
	return "%s is not a file a package may hold (only %s, and code bodies in bodies/)" % [rel, ", ".join(DATA_EXTENSIONS)]


## Whether `rel` is where a code body lives: `bodies/<name>@<major>.gd`.
static func is_body_path(rel: String) -> bool:
	var parts := rel.split("/")
	return parts.size() == 2 and parts[0] == BODIES_DIR and body_name_ok(parts[1].get_basename())


## "name@major" with a snake_case name and a whole major version.
static func body_name_ok(body: String) -> bool:
	var at := body.find("@")
	if at <= 0:
		return false
	var re := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	var major := body.substr(at + 1)
	return re.search(body.substr(0, at)) != null and major.is_valid_int() and int(major) >= 1


func _walk(rel: String, out: PackedStringArray) -> void:
	var dir := root if rel == "" else root.path_join(rel)
	for f in DirAccess.get_files_at(dir):
		out.append(f if rel == "" else rel.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_walk(d if rel == "" else rel.path_join(d), out)


func _size_of(rel: String) -> int:
	if from_vnpkg:
		return _zip.read_file(rel).size()
	var f := FileAccess.open(root.path_join(rel), FileAccess.READ)
	return 0 if f == null else int(f.get_length())


func _read_manifest() -> String:
	if not files.has(MANIFEST):
		return "no %s" % MANIFEST
	var parsed = JSON.parse_string(read_text(MANIFEST))
	if not parsed is Dictionary:
		return "%s does not parse" % MANIFEST
	manifest = parsed
	if int(manifest.get("format", 0)) != FORMAT:
		return "format %s; this shell reads format %d" % [manifest.get("format", "none"), FORMAT]
	id = String(manifest.get("id", ""))
	if RegEx.create_from_string(ID_PATTERN).search(id) == null:
		return "id %s is not snake_case" % id
	var own := root.get_file().get_basename() if from_vnpkg else root.get_file()
	if own != id:
		return "id %s is not its %s name (%s)" % [id, "file" if from_vnpkg else "folder", own]
	kind = String(manifest.get("kind", ""))
	if not KINDS.has(kind):
		return "kind %s is not one of %s" % [kind, ", ".join(KINDS)]
	name = String(manifest.get("name", ""))
	version = String(manifest.get("version", ""))
	for key in ["name", "author", "license"]:
		if String(manifest.get(key, "")) == "":
			return "no %s" % key
	if IslandPack.parse_version(version).is_empty():
		return "version %s is not x.y.z" % version
	var min_shell := String(manifest.get("min_shell", "0.0.0"))
	if IslandPack.parse_version(min_shell).is_empty():
		return "min_shell %s is not x.y.z" % min_shell
	if IslandPack.compare_versions(min_shell, IslandPack.game_version()) > 0:
		return "needs shell %s or later; this is %s" % [min_shell, IslandPack.game_version()]
	if kind == "scene" and String(manifest.get("entry", "")) == "":
		return "a scene names its kit (entry)"
	if manifest.has("signature"):
		return "a signature belongs beside the package file, never in its manifest"
	for body in manifest.get("bodies", []):
		if not body_name_ok(String(body)):
			return "body %s is not name@major" % body
	var tuning: Dictionary = manifest.get("tuning", {})
	for at in tuning:
		var file := String(tuning[at])
		if path_problem(file, false) != "" or file.get_extension() != "json":
			return "tuning %s is not a JSON file in the package" % file
		if not files.has(file):
			return "tuning file %s is missing" % file
	return ""


## The code bodies the package carries: "name@major" for every `bodies/<name>@<major>.gd`.
func code_bodies() -> PackedStringArray:
	var out := PackedStringArray()
	for f in files:
		if is_body_path(f):
			out.append(f.get_file().get_basename())
	return out


func has_file(rel: String) -> bool:
	return files.has(rel)


## The text of `rel`, or "" (never a resource: a package is read, not mounted).
func read_text(rel: String) -> String:
	if not files.has(rel):
		return ""
	if from_vnpkg:
		return _zip.read_file(rel).get_string_from_utf8()
	return FileAccess.get_file_as_string(root.path_join(rel))


## The bytes of `rel` (an OGG, decoded by the shell from the buffer), or empty.
func read_bytes(rel: String) -> PackedByteArray:
	if not files.has(rel):
		return PackedByteArray()
	if from_vnpkg:
		return _zip.read_file(rel)
	return FileAccess.get_file_as_bytes(root.path_join(rel))


## `rel` parsed as JSON, or null.
func read_json(rel: String) -> Variant:
	var text := read_text(rel)
	return null if text == "" else JSON.parse_string(text)


## The files directly in the folder `rel_dir` (names only, sorted).
func list(rel_dir: String) -> PackedStringArray:
	var out := PackedStringArray()
	var prefix := rel_dir.trim_suffix("/") + "/"
	for f in files:
		if f.begins_with(prefix) and not f.substr(prefix.length()).contains("/"):
			out.append(f.substr(prefix.length()))
	return out


## `rel` as a res:// path inside a folder package ("" for a `.vnpkg`, whose files have no path).
func path(rel: String) -> String:
	return "" if from_vnpkg else root.path_join(rel)


## A folder holding the package's data files, for the shell's art readers (`AssetLibrary.package_file`): the
## folder itself, or for a `.vnpkg` its files written out once (never its code bodies) under `user://packages/`
## (`VIBENATURE_PACKAGE_CACHE` instead), in a folder named for the file's hash, so an update unpacks afresh and
## the old one is removed. A release app carries its packages only as `.vnpkg` files (issue 452). "" if it
## cannot be written. Images are decoded from the raw files (`AssetLibrary.cached_texture`), never imported.
func files_dir() -> String:
	if not from_vnpkg or _files_dir != "":
		return root if not from_vnpkg else _files_dir
	var base := OS.get_environment(CACHE_ENV)
	base = (base if base != "" else CACHE).path_join(id)
	var hash := FileAccess.get_sha256(root).left(16)
	var dir := base.path_join(hash)
	if not FileAccess.file_exists(dir.path_join(UNPACKED)):
		_remove(dir)
		var part := base.path_join(hash + ".part")
		_remove(part)
		for rel in files:
			if is_body_path(rel):
				continue
			var to := part.path_join(rel)
			DirAccess.make_dir_recursive_absolute(to.get_base_dir())
			var f := FileAccess.open(to, FileAccess.WRITE)
			if f == null:
				return ""
			f.store_buffer(_zip.read_file(rel))
			f.close()
		var done := FileAccess.open(part.path_join(UNPACKED), FileAccess.WRITE)
		if done == null:
			return ""
		done.store_string(root.get_file() + "\n")
		done.close()
		if DirAccess.rename_absolute(part, dir) != OK:
			return ""
	for old in DirAccess.get_directories_at(base):
		if String(old) != hash:
			_remove(base.path_join(String(old)))
	_files_dir = dir
	return dir


static func _remove(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		_remove(dir.path_join(d))
	DirAccess.remove_absolute(dir)


## The body `name` ("otters@1"), compiled, or null when the package has none or the gate refused it.
func body(body_name: String) -> Script:
	return bodies.get(body_name)
