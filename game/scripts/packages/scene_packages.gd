class_name ScenePackages
extends RefCounted

## The packages this shell has (contract §8): finds them, opens each through the gate once per run, and
## answers for them. The forest pond (`kind` scene) and the companion are folders in `res://packages/`
## during development (P1); later, `.vnpkg` files from the mothership or a store build.
##
## A package that breaks the format is refused with its reason (`refused`), never a crash. Its code bodies
## run only as `PackageGate.code_allowed` says; a body turned away is listed in its `refused_bodies` and the
## package plays without it (its moments are not made, so the director never brings them).

const ROOT := "res://packages"
## The folder of an exported app's resources that holds its signed `.vnpkg` files (`bundled_dir`).
const BUNDLED := "packages"
## The shell's own bodies, by name and major version (§2: basic movement that is general lives in the
## shell). A package names the ones it uses in `bodies`; one the shell lacks refuses the package.
## `moment` is the slot a package's code body plays in.
const SHELL_BODIES := {
	"quadruped": 1, "songbird": 1, "fish": 1, "odonata": 1, "heron": 1, "snake": 1, "turtle": 1, "moment": 1,
}

## Whether this is a release build: code bodies then run only from a signed `.vnpkg`. Tests flip it.
static var release := not OS.is_debug_build()
## The keys an official package's signature must check against (Brightwing's; tests add their own).
static var trusted_keys: Array[CryptoKey] = IslandSigning.release_keys()
## id -> ScenePackage, opened and usable.
static var _open := {}
## [{"path", "why"}] for every package turned away.
static var refused: Array = []
## Folders passed over because a `.vnpkg` of the same id opened first (a release app's exported folder).
static var shadowed: Array = []
static var _scanned := false


## Every package this shell has, opened once per run (`reload` opens them again: a test changing `release`):
## the signed `.vnpkg` files shipped inside the app (`bundled_dir`), then `dirs` (default: `res://packages`).
## A `.vnpkg` that opened comes first, so in a release app it, not the exported folder of the same id, is the
## package. Its art is read from its own files too (`files_dir`): a release app exports no `packages/` folder.
static func load_all(reload: bool = false, dirs: Array = []) -> void:
	if _scanned and not reload:
		return
	_scanned = true
	AssetLibrary.forget()
	_open.clear()
	refused.clear()
	shadowed.clear()
	if dirs.is_empty():
		dirs = [bundled_dir(), ROOT]
	for dir in dirs:
		_load_dir(String(dir))


static func _load_dir(dir: String) -> void:
	if dir == "" or not DirAccess.dir_exists_absolute(dir):
		return
	var names: Array = Array(DirAccess.get_directories_at(dir)) + Array(DirAccess.get_files_at(dir))
	names.sort()
	for n in names:
		var path := dir.path_join(String(n))
		var is_file := path.get_extension() == "vnpkg"
		if not DirAccess.dir_exists_absolute(path) and not is_file:
			continue
		var own := String(n).get_basename() if is_file else String(n)
		if not is_file and _open.has(own) and (_open[own] as ScenePackage).from_vnpkg:
			shadowed.append(path)
			continue
		var pkg := open(path, release, trusted_keys)
		if pkg.problem != "":
			refused.append({"path": path, "why": pkg.problem})
			push_warning("VibeNature: package %s refused: %s" % [path, pkg.problem])
			continue
		if _open.has(pkg.id):
			refused.append({"path": path, "why": "a package %s is already here" % pkg.id})
			continue
		_open[pkg.id] = pkg
		for b in pkg.refused_bodies:
			push_warning("VibeNature: package %s plays without its body %s: %s" % [pkg.id, b, pkg.refused_bodies[b]])


## Where an exported app keeps its official packages: `Contents/Resources/packages/` on macOS, beside the pck
## (`tools/release_mac.py` puts the signed `.vnpkg` files there). "" when this is not an exported app.
static func bundled_dir() -> String:
	if not OS.has_feature("template"):
		return ""
	return OS.get_executable_path().get_base_dir().get_base_dir().path_join("Resources").path_join(BUNDLED)


## One line naming every package this run plays, its trust, where it came from and its code bodies, and any
## package refused; the release smoke test reads it (issue 442): `VibeNature: packages forest_pond 1.0.0
## official .vnpkg, 14 code bodies (bass_leap@1, ...); vibenature_companion 1.0.0 official .vnpkg, data only`.
static func summary() -> String:
	load_all()
	var parts: Array = []
	var ids := _open.keys()
	ids.sort()
	for id in ids:
		var pkg: ScenePackage = _open[id]
		var code := pkg.bodies.keys()
		code.sort()
		var what := "data only" if pkg.code_bodies().is_empty() else "%d code bodies (%s)" % [code.size(), ", ".join(code)]
		if not pkg.refused_bodies.is_empty():
			what += ", %d turned away" % pkg.refused_bodies.size()
		parts.append("%s %s %s %s, %s" % [id, pkg.version, pkg.trust, ".vnpkg" if pkg.from_vnpkg else "folder", what])
	for r in refused:
		parts.append("%s refused (%s)" % [String(r["path"]).get_file(), r["why"]])
	return "VibeNature: packages " + ("; ".join(parts) if not parts.is_empty() else "none")


## Where each package's files are read from and how many are there, for the release's smoke check (issue 452: a
## release exports no `packages/` folder, so its art and sounds come only out of the `.vnpkg`):
## `forest_pond 760/760 files, 93 sounds, unpacked; vibenature_companion 4/4 files, 0 sounds, folder`.
static func files_summary() -> String:
	load_all()
	var parts: Array = []
	var ids := _open.keys()
	ids.sort()
	for id in ids:
		var pkg: ScenePackage = _open[id]
		var dir := files_dir(id)
		var wanted := 0
		var there := 0
		var sounds := 0
		for rel in pkg.files:
			if ScenePackage.is_body_path(rel) or ScenePackage.SIDECARS.has(rel.get_extension()):
				continue
			wanted += 1
			if FileAccess.file_exists(dir.path_join(rel)):
				there += 1
				if rel.begins_with("sounds/") and rel.get_extension() == "ogg":
					sounds += 1
		parts.append("%s %d/%d files, %d sounds, %s" % [id, there, wanted, sounds, "unpacked" if pkg.from_vnpkg else "folder"])
	return "; ".join(parts) if not parts.is_empty() else "none"


## Opens the package at `path` (a folder or a `.vnpkg`) and passes its code bodies through the gate:
## a release build, a signature and its keys as given. `problem` says why it cannot be used at all.
static func open(path: String, is_release: bool, keys: Array[CryptoKey]) -> ScenePackage:
	var pkg := ScenePackage.read(path)
	if pkg.problem != "":
		return pkg
	if pkg.from_vnpkg:
		pkg.trust = PackageGate.trust_of(path, keys)
		if pkg.trust == "bad":
			pkg.problem = "its signature does not check (altered, or not signed by Brightwing)"
			return pkg
	var named: Array = pkg.manifest.get("bodies", [])
	var code := pkg.code_bodies()
	for b in named:
		var body := String(b)
		var nm := body.get_slice("@", 0)
		if code.has(body):
			continue
		if not SHELL_BODIES.has(nm) or int(SHELL_BODIES[nm]) != int(body.get_slice("@", 1)):
			pkg.problem = "it needs the body %s, which this shell lacks" % body
			return pkg
	for body in code:
		if not named.has(body):
			pkg.problem = "bodies/%s.gd is not named in bodies" % body
			return pkg
	if code.is_empty():
		return pkg
	if not PackageGate.BODY_APIS.has(int(pkg.manifest.get("body_api", 0))):
		pkg.problem = "its bodies need body_api %s; this shell has %s" % [pkg.manifest.get("body_api", "none"), PackageGate.BODY_APIS]
		return pkg
	if not PackageGate.code_allowed(is_release, pkg.from_vnpkg, pkg.trust):
		var why := "release builds run code only from a .vnpkg signed by Brightwing" if not pkg.from_vnpkg else "unsigned or not signed by Brightwing: a package that is not Brightwing's is data only"
		for body in code:
			pkg.refused_bodies[body] = why
		return pkg
	for body in code:
		var rel := ScenePackage.BODIES_DIR.path_join(body + ".gd")
		var src := pkg.read_text(rel)
		var scanned := PackageGate.scan(src)
		if scanned != "":
			pkg.problem = "bodies/%s.gd: %s" % [body, scanned]
			return pkg
		var why: Array = []
		var script := PackageGate.compile(src, "%s/%s" % [pkg.id, rel], why)
		if script == null:
			pkg.problem = String(why[0])
			return pkg
		pkg.bodies[body] = script
	return pkg


## The package `id` (null when it is not here or was refused).
static func get_package(id: String) -> ScenePackage:
	load_all()
	return _open.get(id)


## The folder package `id`'s files lie in: its own folder, or for a `.vnpkg` the files written out of it
## (`ScenePackage.files_dir`, issue 452); `res://packages/<id>` when no such package is open.
static func files_dir(id: String) -> String:
	var pkg := get_package(id)
	var dir := pkg.files_dir() if pkg != null else ""
	return dir if dir != "" else ROOT.path_join(id)


## The scene package whose kit is `kit_id` (`entry`), or the first scene there is when "" (null if none).
static func scene(kit_id: String = "") -> ScenePackage:
	load_all()
	var ids := _open.keys()
	ids.sort()
	for id in ids:
		var pkg: ScenePackage = _open[id]
		if pkg.kind == "scene" and (kit_id == "" or String(pkg.manifest.get("entry", "")) == kit_id):
			return pkg
	return null


## The companion package (the avatar, van, elder and journal), or null.
static func companion() -> ScenePackage:
	load_all()
	for id in _open:
		if (_open[id] as ScenePackage).kind == "companion":
			return _open[id]
	return null


## A code body by name ("otters@1") from the scene package (or the package `package_id`), or null.
static func body(body_name: String, package_id: String = "") -> Script:
	var pkg := get_package(package_id) if package_id != "" else scene()
	return pkg.body(body_name) if pkg != null else null


## Puts each package's tuning (`tuning` in package.json: a dotted path in the balance data -> a JSON file
## in the package) into `data`, so the shell reads it where it always has. The scene's is the one whose
## kit `data.scene.scene_id` names.
static func apply_tuning(data: Dictionary) -> void:
	var pkgs: Array = []
	var sc := scene(String((data.get("scene", {}) as Dictionary).get("scene_id", "")))
	if sc != null:
		pkgs.append(sc)
	if companion() != null:
		pkgs.append(companion())
	for pkg in pkgs:
		var tuning: Dictionary = (pkg as ScenePackage).manifest.get("tuning", {})
		for at in tuning:
			var value = (pkg as ScenePackage).read_json(String(tuning[at]))
			if value == null:
				push_warning("VibeNature: package %s tuning %s does not parse" % [pkg.id, tuning[at]])
				continue
			var keys := String(at).split(".")
			var node: Dictionary = data
			for i in keys.size() - 1:
				if not node.has(keys[i]) or not node[keys[i]] is Dictionary:
					node[keys[i]] = {}
				node = node[keys[i]]
			node[keys[-1]] = value
