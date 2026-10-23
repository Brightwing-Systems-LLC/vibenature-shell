extends SceneTree

## Opens every package as the shell does and prints what it found: each package's kind, version, files,
## the code bodies that passed the gate and any turned away, and every package refused with its reason.
## `godot --headless --path game --script res://tools/package_check.gd [-- release]` (release: as a
## release build would, so an unsigned folder's bodies are turned away). Exits 1 if anything was refused.


func _init() -> void:
	ScenePackages.release = OS.get_cmdline_user_args().has("release")
	ScenePackages.load_all(true)
	var bad := not ScenePackages.refused.is_empty()
	var ids := ScenePackages._open.keys()
	ids.sort()
	for id in ids:
		var pkg: ScenePackage = ScenePackages._open[id]
		var code := pkg.bodies.keys()
		code.sort()
		print("%s %s (%s): %d files, bodies %s" % [pkg.id, pkg.version, pkg.kind, pkg.files.size(), ", ".join(code) if not code.is_empty() else "none"])
		for b in pkg.refused_bodies:
			print("  turned away %s: %s" % [b, pkg.refused_bodies[b]])
			bad = true
	for r in ScenePackages.refused:
		print("REFUSED %s: %s" % [r["path"], r["why"]])
	quit(1 if bad else 0)
