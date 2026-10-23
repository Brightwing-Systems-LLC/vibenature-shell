class_name HookConnect
extends RefCounted

## The welcome's connect step (issue 199): the same
## installer as `just hook-install` (`game/tools/hook_install.py`), run first as a dry run whose report is said
## in plain words, then for real only when the person presses Connect.
##
## `home` is the folder whose `.claude` and `.codex` are read and written: "" is the person's own (never in
## tests or snapshots, which always pass a temporary one; `Game.hook_home`). `runner` runs the installer and
## tests may replace it. Nothing an agent sends is read here: only whether VibeNature's hook is in each file.

const SCRIPT := "res://tools/hook_install.py"
const HARNESSES: Array[String] = ["claude", "codex"]
const NAMES := {"claude": "Claude Code", "codex": "Codex"}
## The installer's own words (hook_install.py `PRIVACY`, `NEXT`), used when a report does not carry them.
const PRIVACY := "VibeNature hears only when an agent starts or stops working, never what it works on."
const CODEX_TRUST := "open codex, type /hooks and trust VibeNature's 6 hooks. Until then Codex runs none of them."

var home := ""
var python := ""
## (args: PackedStringArray) -> {"code": int, "out": String}
var runner: Callable
## The last dry run's report ({} before one), and the last install's.
var last_plan: Dictionary = {}
var last_install: Dictionary = {}


func _init(hook_home: String, python_candidates: Array) -> void:
	home = hook_home
	python = HookConnect.find_python(python_candidates)
	runner = _execute


## VIBENATURE_PYTHON, else the first candidate that exists, else `python3` on the PATH.
static func find_python(candidates: Array) -> String:
	var wanted := OS.get_environment("VIBENATURE_PYTHON")
	if wanted != "":
		return wanted
	for path in candidates:
		if FileAccess.file_exists(String(path)):
			return String(path)
	return "python3"


## The repo's installer in a dev run; in the release app the copy `just release-mac` bundles (issue 196).
static func script_path() -> String:
	var dev := ProjectSettings.globalize_path(SCRIPT)
	if FileAccess.file_exists(dev):
		return dev
	return HookConnect.bundled_script(OS.get_executable_path())


## `<app>/Contents/MacOS/<exe>` → `<app>/Contents/Resources/hook/hook_install.py`.
static func bundled_script(executable: String) -> String:
	return executable.get_base_dir().get_base_dir().path_join("Resources/hook/hook_install.py")


## The installer's arguments: install, as JSON, a dry run or not, for `home`.
func arguments(dry_run: bool) -> PackedStringArray:
	var out := PackedStringArray([HookConnect.script_path(), "install", "--json"])
	if dry_run:
		out.append("--dry-run")
	if home != "":
		out.append_array(["--home", home])
	return out


## What connecting would change, written nowhere: the installer's report, or {"error": why}.
func plan() -> Dictionary:
	last_plan = _run(true)
	return last_plan


## Connects for real (the person pressed Connect after reading the plan).
func install() -> Dictionary:
	last_install = _run(false)
	return last_install


## Where each harness keeps its hooks under `home` (Codex's moves with CODEX_HOME only for the real home).
func settings_path(harness: String) -> String:
	var base := home if home != "" else OS.get_environment("HOME")
	if harness == "codex":
		var codex_home := OS.get_environment("CODEX_HOME") if home == "" else ""
		return (codex_home if codex_home != "" else base.path_join(".codex")).path_join("hooks.json")
	return base.path_join(".claude").path_join("settings.json")


## The plan as short sentences for a person, not a programmer: what is changed where, that a copy is kept,
## and what the hook says (only that work started or stopped).
func plain(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if report.has("error"):
		out.append("The connection could not be checked: %s" % String(report["error"]))
		return out
	var any_change := false
	for h in report.get("harnesses", []):
		var name := String(h["name"])
		var where := short_path(String(h["path"]))
		if (h["added"] as Array).is_empty() and (h["removed"] as Array).is_empty():
			out.append("%s is already connected. Nothing to change." % name)
			continue
		any_change = true
		if bool(h["create"]):
			out.append("%s: a settings file is made at %s with VibeNature's hook in it." % [name, where])
		else:
			out.append("%s: VibeNature's hook is added to %s. A copy of the file is kept first, and nothing else in it changes." % [name, where])
	for h in report.get("skipped", []):
		out.append("%s is not on this Mac, so it is left alone." % String(h["name"]))
	out.append_array(refusals(report))
	if any_change:
		out.append_array(next_steps(report, "Afterwards, "))
		out.append(String(report.get("privacy", PRIVACY)))
		out.append("Nothing is written until you press Connect.")
	return out


## What the person must still do, in the installer's own words (`NEXT` in hook_install.py).
func next_steps(report: Dictionary, lead := "") -> Array[String]:
	var out: Array[String] = []
	var steps: Array = report.get("next", [])
	if steps.is_empty():
		for h in report.get("harnesses", []):
			if String(h["key"]) == "codex" and not (h["added"] as Array).is_empty():
				steps.append({"name": "Codex", "text": CODEX_TRUST})
	for step in steps:
		out.append("%s%s: %s" % [lead, String(step["name"]), String(step["text"])])
	return out


## A harness left untouched, why, and what to do (the installer's `fix`).
func refusals(report: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for h in report.get("refused", []):
		var fix := String(h.get("fix", ""))
		out.append("%s is left alone: %s." % [String(h["name"]), String(h["why"])] + (" To connect it, %s" % fix if fix != "" else ""))
	return out


## A path under `home` written from ~.
func short_path(path: String) -> String:
	var base := home if home != "" else OS.get_environment("HOME")
	if base != "" and path.begins_with(base):
		return "~" + path.substr(base.length())
	return path


func _run(dry_run: bool) -> Dictionary:
	var result: Dictionary = runner.call(arguments(dry_run))
	var parsed = JSON.parse_string(String(result.get("out", "")))
	if not (parsed is Dictionary):
		var text := String(result.get("out", "")).strip_edges()
		return {"error": "the installer did not answer (%s)" % (text.get_slice("\n", 0) if text != "" else "exit %d" % int(result.get("code", -1)))}
	return parsed


func _execute(args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := OS.execute(python, args, output, true)
	return {"code": code, "out": "".join(output)}
