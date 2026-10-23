class_name IslandSigning
extends RefCounted

## Detached signatures for island packs (contract §5): `<id>.pck.sig` beside `<id>.pck` holds
## the RSA signature of the pack file's SHA-256, in base64 on one line. Release builds load
## only packs whose signature checks against a key compiled into the game (BrightwingKey).

const CHUNK := 1 << 20


## The SHA-256 of a file, read in chunks.
static func digest(path: String) -> PackedByteArray:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return PackedByteArray()
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	while file.get_position() < file.get_length():
		hashing.update(file.get_buffer(CHUNK))
	return hashing.finish()


## A public key from PEM text, or null (a placeholder or unreadable text is no key).
static func public_key(pem: String) -> CryptoKey:
	if not pem.contains("-----BEGIN PUBLIC KEY-----"):
		return null
	var key := CryptoKey.new()
	if key.load_from_string(pem, true) != OK:
		return null
	return key


## The keys a release build trusts: Brightwing's, unless this build still has the placeholder.
static func release_keys() -> Array[CryptoKey]:
	var keys: Array[CryptoKey] = []
	var key := public_key(BrightwingKey.PEM)
	if key != null:
		keys.append(key)
	return keys


## Signs `path` with `private_key` and returns the signature file's text.
static func sign_file(path: String, private_key: CryptoKey) -> String:
	var signature := Crypto.new().sign(HashingContext.HASH_SHA256, digest(path), private_key)
	return Marshalls.raw_to_base64(signature)


## Whether the signature text `signature` is `path`'s, made by one of `keys`.
static func verify_file(path: String, signature: String, keys: Array[CryptoKey]) -> bool:
	var raw := Marshalls.base64_to_raw(signature.strip_edges())
	if raw.is_empty():
		return false
	var hashed := digest(path)
	if hashed.is_empty():
		return false
	var crypto := Crypto.new()
	for key in keys:
		if crypto.verify(HashingContext.HASH_SHA256, hashed, raw, key):
			return true
	return false


## The first private key PEM block in `text` (a key file, or the signer's private key file), or null.
static func private_key_from_text(text: String) -> CryptoKey:
	for kind in ["PRIVATE KEY", "RSA PRIVATE KEY"]:
		var begin := text.find("-----BEGIN %s-----" % kind)
		var end_marker := "-----END %s-----" % kind
		var end := text.find(end_marker, begin)
		if begin >= 0 and end > begin:
			var key := CryptoKey.new()
			if key.load_from_string(text.substr(begin, end + end_marker.length() - begin), false) == OK:
				return key
	return null
