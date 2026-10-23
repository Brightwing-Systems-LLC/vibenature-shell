class_name SceneEdgeFade
extends RefCounted

## Where the scene's open right and bottom edges end in the desktop
## (issue 424, the human's pick: the dissolve).
## The two edges against the screen stay straight; an open side or bottom dissolves across a band (`band`,
## `left`, points; 0 against the screen). An open top is the sky's own (`SceneSkyEdge`). Like `SceneSkyEdge`, each edge has a profile seeded by the kit: how
## far into the band the art reaches and over how much of it it thins out, lobes and bays rather than
## an even band. `scene_lit.gdshader` reads the profiles as a texture and dissolves each layer on its
## own blue-noise threshold; the sky's right edge reads the same row, so sky and ground end on one
## outline. `keep` is the smooth answer for rain, the water's rings and the animals. Pure apart from
## building the texture.

## Right and bottom band widths (points); 0 where that edge sits against the screen.
var band := Vector2.ZERO
## The same along the left (from the world's left edge, over its grown margin and into the art).
var left := 0.0
var size := Vector2.ZERO
## (reach, soft) along the right by y, and along the bottom by x (fractions of the band).
var right := PackedFloat32Array()
var right_soft := PackedFloat32Array()
var bottom := PackedFloat32Array()
var bottom_soft := PackedFloat32Array()
var left_reach := PackedFloat32Array()
var left_soft := PackedFloat32Array()
var _texture: ImageTexture


## `fade` is `scene.edges.fade` in balance.json: `reach`, `soft` (ranges, fractions of the band) and
## `wavelengths_pt` (the lobes' sizes).
func setup(scene_size: Vector2, fade: Dictionary, kit_id: String) -> void:
	size = scene_size
	var waves: Array = fade.get("wavelengths_pt", [220, 90, 35])
	var reach := SceneSkyEdge._pair(fade.get("reach", [0.4, 0.97]))
	var soft := SceneSkyEdge._pair(fade.get("soft", [0.12, 0.35]))
	var seed := hash(kit_id + "/edge_fade")
	right = SceneSkyEdge._profile(seed, waves, reach)
	bottom = SceneSkyEdge._profile(seed + 7919, waves, reach)
	right_soft = SceneSkyEdge._profile(seed + 104729, waves, soft)
	bottom_soft = SceneSkyEdge._profile(seed + 1299709, waves, soft)
	left_reach = SceneSkyEdge._profile(seed + 15485863, waves, reach)
	left_soft = SceneSkyEdge._profile(seed + 49979687, waves, soft)
	_texture = null


func _at(profile: PackedFloat32Array, along: float) -> float:
	var f := fposmod(along, float(SceneSkyEdge.PERIOD))
	var i := int(f)
	return lerpf(profile[i % SceneSkyEdge.PERIOD], profile[(i + 1) % SceneSkyEdge.PERIOD], f - i)


## How much of the art is left at `at` (points): 1 away from the open edges, falling to 0 where they end
## (the shader's outline, before its dither).
func keep(at: Vector2) -> float:
	var k := 1.0
	if band.x > 0.0:
		k *= side(maxf(at.x - (size.x - band.x), 0.0) / band.x, _at(right, at.y), _at(right_soft, at.y))
	if band.y > 0.0:
		k *= side(maxf(at.y - (size.y - band.y), 0.0) / band.y, _at(bottom, at.x), _at(bottom_soft, at.x))
	if left > 0.0:
		k *= side(maxf(left - at.x, 0.0) / left, _at(left_reach, at.y), _at(left_soft, at.y))
	return k


static func side(out: float, r: float, soft: float) -> float:
	if out <= 0.0:
		return 1.0
	return (1.0 - smoothstep(maxf(r - soft, 0.0), r, out)) * (1.0 - smoothstep(0.85, 0.98, out))


## Row 0 the right's (reach, soft) by y, row 1 the bottom's by x, row 2 the left's by y, for the shaders.
func profile_texture() -> ImageTexture:
	if _texture != null:
		return _texture
	var img := Image.create(SceneSkyEdge.PERIOD, 3, false, Image.FORMAT_RGF)
	for x in SceneSkyEdge.PERIOD:
		img.set_pixel(x, 0, Color(right[x], right_soft[x], 0))
		img.set_pixel(x, 1, Color(bottom[x], bottom_soft[x], 0))
		img.set_pixel(x, 2, Color(left_reach[x], left_soft[x], 0))
	_texture = ImageTexture.create_from_image(img)
	return _texture
