class_name AgentEvent
extends RefCounted

## The one thing that crosses from an agent into the game (contract §2): a JSON object with
## exactly `kind`, `source`, `session_hash` and `ts`, at most 512 bytes. Anything else is
## refused whole; nothing of a refused body is kept or logged.

const KINDS: Array[String] = ["session_start", "session_end", "turn_start", "still_busy", "turn_end", "tool_fail", "needs_input"]
const SOURCES: Array[String] = ["claude_code", "cmux", "codex", "cli"]
const KEYS: Array[String] = ["kind", "source", "session_hash", "ts"]
const MAX_BYTES := 512
const HASH_CHARS := "0123456789abcdef"
## Unix seconds up to the year 5000: a bigger `ts` is not a time.
const MAX_TS := 95617584000.0


## The event as {kind, source, session_hash, ts:int}, or {} when the body breaks any rule.
static func parse(body: PackedByteArray) -> Dictionary:
	if body.is_empty() or body.size() > MAX_BYTES:
		return {}
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		return {}
	var data = json.data
	if not data is Dictionary or (data as Dictionary).size() != KEYS.size():
		return {}
	for key in data:
		if not key is String or not KEYS.has(key):
			return {}
	var kind = data["kind"]
	var source = data["source"]
	var session = data["session_hash"]
	var ts = data["ts"]
	if not kind is String or not KINDS.has(kind):
		return {}
	if not source is String or not SOURCES.has(source):
		return {}
	if not is_session_hash(session):
		return {}
	if not (ts is float or ts is int) or float(ts) != floorf(float(ts)) or float(ts) < 0.0 or float(ts) > MAX_TS:
		return {}
	return {"kind": kind, "source": source, "session_hash": session, "ts": int(ts)}


static func is_session_hash(value) -> bool:
	if not value is String or (value as String).length() != 16:
		return false
	for c in (value as String):
		if not HASH_CHARS.contains(c):
			return false
	return true
