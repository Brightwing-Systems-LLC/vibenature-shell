class_name PackageGate
extends RefCounted

## The signature gate for code bodies (contract §8, proposal 2026-10-20-open-shell-and-scene-packages §3a).
## Only Brightwing's own packages may carry code; every other package is data only. In order, refusing at
## the first failure:
##
## 1. **Where it may run** (`code_allowed`): a debug build runs a development folder's bodies unsigned; a
##    release build runs code only from a `.vnpkg` whose signature (`<id>.vnpkg.sig`, the island packs'
##    scheme: RSA over the file's SHA-256, `IslandSigning`) checks against Brightwing's key. Anything else
##    plays with the shell's bodies only. A signature that does not check refuses the package everywhere.
## 2. **The source is plain text** in the package (never inside an encrypted part), so what runs can be read.
## 3. **A static check** (`scan`) refuses a body that names a file, OS, network or engine class, loads
##    anything, or calls by a name built at run time. Defence in depth: the published source is the guarantee.
## 4. **Compiled from source** (`compile`: `GDScript.new()`, `source_code`, `reload()`), never mounted into
##    res:// and never loaded as a resource. A body must extend `PackageBody`.

## Classes a body may never name: files, the OS, the network, the engine's own registries, threads.
const FORBIDDEN_CLASSES: Array[String] = [
	"FileAccess", "DirAccess", "OS", "Engine", "ClassDB", "ProjectSettings", "ResourceLoader", "ResourceSaver",
	"HTTPRequest", "HTTPClient", "TCPServer", "UDPServer", "JavaScriptBridge", "Expression", "DisplayServer",
	"Thread", "Mutex", "Semaphore", "WorkerThreadPool", "IP", "GDScript", "Script", "ConfigFile", "ZIPReader",
	"ZIPPacker", "PCKPacker", "XMLParser", "Crypto", "CryptoKey", "X509Certificate", "TLSOptions", "UPNP",
	"UPNPDevice", "EditorInterface", "Marshalls", "JNISingleton", "JavaClassWrapper", "GDExtensionManager",
	"ResourceUID", "IslandSigning", "ScenePackages", "PackageGate", "ScenePackage",
	"AudioServer", "SceneSound", "SceneSoundscape", "SoundBuses", "SoundRender",
]
## Class name prefixes a body may never name: the families of network peers, and audio (proposal
## 2026-10-21-sound-in-packages §6: a body says `sound_event` and nothing else; no player, stream, effect,
## capture or microphone).
const FORBIDDEN_PREFIXES: Array[String] = ["AudioStream", "AudioEffect", "StreamPeer", "PacketPeer", "WebSocket", "WebRTC", "ENet", "MultiplayerPeer", "MultiplayerAPI", "HTTP"]
## Functions a body may never call by name: loading anything, building objects from text.
const FORBIDDEN_CALLS: Array[String] = [
	"load", "preload", "str_to_var", "bytes_to_var_with_objects", "dict_to_inst", "instance_from_id", "set_script",
	"load_from_file", "load_from_buffer_with_objects", "open", "open_encrypted", "open_encrypted_with_pass", "open_compressed",
	"save", "save_png", "save_jpg", "save_webp", "save_exr", "save_png_to_buffer", "store_string", "store_buffer",
	"shell_open", "execute", "create_process", "get_singleton",
]
## Calls whose first argument names a method or property: allowed only with a literal name.
const NAMED_CALLS: Array[String] = ["call", "callv", "call_deferred", "set", "set_deferred", "set_indexed", "get_indexed"]
## The `PackageBody` API majors this shell provides (`body_api` in package.json).
const BODY_APIS: Array[int] = [1]


## Whether code bodies may run from a package: a development folder in a debug build, or an official
## (signed by Brightwing, checked) `.vnpkg` anywhere. Never an unsigned folder in a release build.
static func code_allowed(release: bool, from_vnpkg: bool, trust: String) -> bool:
	if from_vnpkg:
		return trust == "official"
	return not release


## The trust of a `.vnpkg` at `path`: "official" when `<path>.sig` checks against one of `keys`,
## "community" when there is no signature, "bad" when there is one and it does not check.
static func trust_of(path: String, keys: Array[CryptoKey]) -> String:
	var sig_path := path + ".sig"
	if not FileAccess.file_exists(sig_path):
		return "community"
	if keys.is_empty():
		return "bad"
	return "official" if IslandSigning.verify_file(path, FileAccess.get_file_as_string(sig_path), keys) else "bad"


## Why the source `src` may not run as a code body, or "". Comments and string contents are ignored, so
## a doc comment may say "FileAccess"; a call by name must name it in a literal.
static func scan(src: String) -> String:
	var code := strip(src)
	if not RegEx.create_from_string("(?m)^extends\\s+PackageBody\\s*$").search(code):
		return "it does not extend PackageBody"
	if RegEx.create_from_string("(?m)^class_name\\b").search(code):
		return "it declares a class_name (a package adds no global class)"
	var words := RegEx.create_from_string("\\b[A-Za-z_][A-Za-z0-9_]*\\b")
	for m in words.search_all(code):
		var w := m.get_string()
		if FORBIDDEN_CLASSES.has(w):
			return "it names %s" % w
		for prefix in FORBIDDEN_PREFIXES:
			if w.begins_with(prefix):
				return "it names %s" % w
	var calls := RegEx.create_from_string("(?<![A-Za-z0-9_])([A-Za-z_][A-Za-z0-9_]*)\\s*\\(")
	var callables := _callables(code)
	for m in calls.search_all(code):
		var fn := m.get_string(1)
		if FORBIDDEN_CALLS.has(fn):
			return "it calls %s()" % fn
		if fn == "Callable":
			var rest := code.substr(m.get_end())
			var comma := _top_comma(rest)
			if comma < 0 or not _literal_at(rest, comma + 1):
				return "it makes a Callable from a name built at run time"
			continue
		if fn == "get" and not _has_receiver(code, m.get_start()):
			if not _literal_at(code, m.get_end()):
				return "it calls get() by a name built at run time"
			continue
		if not NAMED_CALLS.has(fn):
			continue
		if fn == "call" or fn == "callv" or fn == "call_deferred":
			var receiver := _receiver(code, m.get_start())
			if receiver != "" and (callables.has(receiver) or receiver.ends_with("as Callable)")):
				continue
		if not _literal_at(code, m.get_end()):
			return "it calls %s() by a name built at run time" % fn
	return ""


## `src` with comments removed and every string literal's contents replaced by "_", so only code is left.
static func strip(src: String) -> String:
	var out := PackedStringArray()
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "#":
			while i < n and src[i] != "\n":
				i += 1
			continue
		if c == "\"" or c == "'":
			var triple := i + 2 < n and src[i + 1] == c and src[i + 2] == c
			var quote := c.repeat(3) if triple else c
			i += quote.length()
			while i < n and src.substr(i, quote.length()) != quote:
				if src[i] == "\\":
					i += 1
				i += 1
			i += quote.length()
			out.append("\"_\"")
			continue
		out.append(c)
		i += 1
	return "".join(out)


## The names that hold a Callable: lambdas assigned to a variable, and variables or parameters typed Callable.
static func _callables(code: String) -> Dictionary:
	var out := {}
	for pattern in ["\\bvar\\s+([A-Za-z_][A-Za-z0-9_]*)\\s*(?::\\s*Callable\\s*)?:?=\\s*func\\b", "([A-Za-z_][A-Za-z0-9_]*)\\s*:\\s*Callable\\b"]:
		for m in RegEx.create_from_string(pattern).search_all(code):
			out[m.get_string(1)] = true
	return out


## What `.call(` at `at` is called on: the identifier or the parenthesised expression before the dot ("" if none).
static func _receiver(code: String, at: int) -> String:
	var i := at - 1
	while i >= 0 and code[i] == " ":
		i -= 1
	if i < 0 or code[i] != ".":
		return ""
	var end := i
	i -= 1
	if i >= 0 and code[i] == ")":
		var depth := 0
		while i >= 0:
			if code[i] == ")":
				depth += 1
			elif code[i] == "(":
				depth -= 1
				if depth == 0:
					break
			i -= 1
		return code.substr(i, end - i)
	var j := i
	while j >= 0 and (code[j] == "_" or code[j].is_valid_identifier() or code[j].is_valid_int()):
		j -= 1
	return code.substr(j + 1, i - j)


static func _has_receiver(code: String, at: int) -> bool:
	var i := at - 1
	while i >= 0 and code[i] == " ":
		i -= 1
	return i >= 0 and code[i] == "."


## Whether the argument starting at `from` is a string literal ("_", &"_" or ^"_" once stripped).
static func _literal_at(code: String, from: int) -> bool:
	var i := from
	while i < code.length() and (code[i] == " " or code[i] == "\t" or code[i] == "\n"):
		i += 1
	if i < code.length() and (code[i] == "&" or code[i] == "^"):
		i += 1
	return i < code.length() and code[i] == "\""


## The index in `rest` of the first comma at the call's own depth (-1 if the call ends first).
static func _top_comma(rest: String) -> int:
	var depth := 0
	for i in rest.length():
		var c := rest[i]
		if c == "(" or c == "[" or c == "{":
			depth += 1
		elif c == ")" or c == "]" or c == "}":
			if depth == 0:
				return -1
			depth -= 1
		elif c == "," and depth == 0:
			return i
	return -1


## The body's source compiled as a script that extends `PackageBody`, or null (with `why` filled).
## `origin` names it in errors (the package path); the script is never registered at a res:// path.
static func compile(src: String, origin: String, why: Array) -> Script:
	var script := GDScript.new()
	script.source_code = src
	if script.reload() != OK:
		why.append("%s does not compile" % origin)
		return null
	if not script.can_instantiate():
		why.append("%s cannot be made" % origin)
		return null
	var base: Script = script.get_base_script()
	while base != null and base.get_global_name() != &"PackageBody":
		base = base.get_base_script()
	if base == null:
		why.append("%s does not extend PackageBody" % origin)
		return null
	return script
