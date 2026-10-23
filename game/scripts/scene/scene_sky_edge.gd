class_name SceneSkyEdge
extends RefCounted

## Where the sky ends in a kit's margin (Skypatch issue 144).
## Not a band of even width: along each edge the sky reaches out by a profile of low-frequency
## noise in a few octaves (cloud-sized lobes and bays), and thins out over a width that varies the
## same way (a long wisp in one place, a cloud's crisper edge in another). Both are seeded by the
## kit's id, so a kit always has the same skyline, and drift very slowly with the clouds. Where the
## margin has art (the canopy, the far treeline) the sky stays behind it, so the art and not a
## rounded rectangle decides the corner. The shader reads the same profiles and cover as textures,
## adds clouds carrying the sky further and dithers the end; `keep` is the smooth answer for the
## stars and the rain. Pure apart from building the textures.

## Profile samples per point along an edge, and the profile's length (points) before it repeats.
const PERIOD := 2048

## How far the sky reaches (fractions of the margin) along the top (by x) and the left (by y)...
var top := PackedFloat32Array()
var left := PackedFloat32Array()
## ...and over how much of the margin it thins out before that.
var top_soft := PackedFloat32Array()
var left_soft := PackedFloat32Array()
## Margin art cover (0..1), blurred, one value per point of the whole scene.
var cover: Image
var size := Vector2.ZERO
var frame := Rect2()
var cover_band := Vector2(0.4, 0.8)
var drift := 0.15


## `size` is the whole scene and `frame` the old composition (points); `art` the kit's art composed
## at any scale (or null: no cover).
func setup(scene_size: Vector2, frame_rect: Rect2, dissolve: Dictionary, kit_id: String, art: Image = null) -> void:
	size = scene_size
	frame = frame_rect
	drift = float(dissolve.get("drift", 0.15))
	cover_band = _pair(dissolve.get("cover", [0.4, 0.8]))
	var reach := _pair(dissolve.get("reach", [0.3, 1.0]))
	var soft := _pair(dissolve.get("soft", [0.25, 0.6]))
	var waves: Array = dissolve.get("wavelengths_pt", [300, 120, 45])
	var seed := hash(kit_id)
	top = _profile(seed, waves, reach)
	left = _profile(seed + 7919, waves, _pair(dissolve.get("reach_left", [0.1, 0.55])))
	top_soft = _profile(seed + 104729, waves, soft)
	left_soft = _profile(seed + 1299709, waves, soft)
	cover = _cover(art, float(dissolve.get("cover_blur_pt", 6.0)))


static func _pair(raw) -> Vector2:
	return Vector2(float(raw[0]), float(raw[1]))


## A periodic 1-D noise profile over PERIOD points, stretched to fill `range`.
static func _profile(seed: int, waves: Array, range: Vector2) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out := PackedFloat32Array()
	out.resize(PERIOD)
	var amp := 1.0
	for wave in waves:
		var count := maxi(int(round(float(PERIOD) / float(wave))), 1)
		var lattice := PackedFloat32Array()
		for i in count:
			lattice.append(rng.randf())
		var step := float(PERIOD) / count
		for x in PERIOD:
			var f := x / step
			var i := int(f)
			var t := f - i
			t = t * t * (3.0 - 2.0 * t)
			out[x] += amp * lerpf(lattice[i % count], lattice[(i + 1) % count], t)
		amp *= 0.5
	var lo := INF
	var hi := -INF
	for v in out:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	for x in PERIOD:
		out[x] = lerpf(range.x, range.y, (out[x] - lo) / maxf(hi - lo, 0.0001))
	return out


func _cover(art: Image, blur_pt: float) -> Image:
	var w := maxi(int(size.x), 1)
	var h := maxi(int(size.y), 1)
	if art == null:
		return Image.create(w, h, false, Image.FORMAT_L8)
	var a := art.duplicate() as Image
	a.convert(Image.FORMAT_RGBA8)
	# A blur: down to one sample every `blur_pt` and back up with cubic filtering.
	var small := Vector2i(maxi(int(size.x / maxf(blur_pt, 1.0)), 1), maxi(int(size.y / maxf(blur_pt, 1.0)), 1))
	a.resize(small.x, small.y, Image.INTERPOLATE_BILINEAR)
	var lum := Image.create(small.x, small.y, false, Image.FORMAT_L8)
	for y in small.y:
		for x in small.x:
			lum.set_pixel(x, y, Color(a.get_pixel(x, y).a, 0, 0))
	lum.resize(w, h, Image.INTERPOLATE_CUBIC)
	return lum


## A profile at `along` points, shifted by `shift` (points, before the drift factor).
func sample(profile: PackedFloat32Array, along: float, shift: float = 0.0) -> float:
	var f := fposmod(along + shift * drift, float(PERIOD))
	var i := int(f)
	return lerpf(profile[i % PERIOD], profile[(i + 1) % PERIOD], f - i)


func cover_at(at: Vector2) -> float:
	var x := clampi(int(at.x), 0, cover.get_width() - 1)
	var y := clampi(int(at.y), 0, cover.get_height() - 1)
	return cover.get_pixel(x, y).r


## How much sky is left at `at` (points): 1 in the frame, falling to 0 across the margin.
## `shift` is the clouds' offset along x, which the top's skyline drifts with.
func keep(at: Vector2, shift: float = 0.0) -> float:
	var margin := Vector4(frame.position.x, frame.position.y, size.x - frame.end.x, size.y - frame.end.y)
	var out_x := maxf(maxf(frame.position.x - at.x, 0.0) / margin.x if margin.x > 0.0 else 0.0,
			maxf(at.x - frame.end.x, 0.0) / margin.z if margin.z > 0.0 else 0.0)
	var out_y := maxf(maxf(frame.position.y - at.y, 0.0) / margin.y if margin.y > 0.0 else 0.0,
			maxf(at.y - frame.end.y, 0.0) / margin.w if margin.w > 0.0 else 0.0)
	if out_x <= 0.0 and out_y <= 0.0:
		return 1.0
	var k := side_keep(out_y, sample(top, at.x, shift), sample(top_soft, at.x, shift)) \
			* side_keep(out_x, sample(left, at.y), sample(left_soft, at.y))
	k = maxf(k, smoothstep(cover_band.x, cover_band.y, cover_at(at)))
	return k * (1.0 - smoothstep(0.85, 0.98, maxf(out_x, out_y)))


## Keep across one margin: `out` 0 at the frame to 1 at the window's edge, the sky thinning over
## `soft` and gone at `r`, never before the frame.
static func side_keep(out: float, r: float, soft: float) -> float:
	if out <= 0.0:
		return 1.0
	return 1.0 - smoothstep(maxf(r - soft, 0.0), r, out)


## Row 0 the top's (reach, soft) by x, row 1 the left's by y, for the shader.
func profile_texture() -> ImageTexture:
	var img := Image.create(PERIOD, 2, false, Image.FORMAT_RGF)
	for x in PERIOD:
		img.set_pixel(x, 0, Color(top[x], top_soft[x], 0))
		img.set_pixel(x, 1, Color(left[x], left_soft[x], 0))
	return ImageTexture.create_from_image(img)


func cover_texture() -> ImageTexture:
	return ImageTexture.create_from_image(cover)
