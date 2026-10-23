shader_type canvas_item;

// The sky behind the trees (Skypatch issue 112): the kit
// leaves everything above the plate transparent and the game paints a whole sky there, by the time
// of day: blue with a few soft clouds by day, warm at golden hour, sunset colours, a deep blue night.
// The gradient runs from `glow_high` at the top to `glow_low` at the horizon; clouds drift with the
// wind (the same pattern whose shadows cross the ground) and are shaded in three tones with an
// ordered-dither edge, one art pixel at a time, so they sit with the pixel-art kit. `sky_alpha` 0
// gives back the old glow that dissolves upward into the desktop.
// Since Skypatch issue 146 the clouds live (`scene_clouds.gdshaderinc`):
// low cumulus that forms, splits and dissolves as it drifts, high cirrus wisps drifting slower behind it,
// and a front that builds (darker) or clears from the upwind side.

#include "res://scripts/scene/scene_clouds.gdshaderinc"

uniform vec2 size = vec2(1152.0, 200.0);
// Art px per point: every value is computed per art pixel.
uniform float px = 2.0;
uniform float horizon_y = 150.0;
uniform vec4 glow_low : source_color = vec4(1.0, 0.7, 0.5, 1.0);
uniform vec4 glow_high : source_color = vec4(0.5, 0.4, 0.7, 1.0);
uniform float glow = 0.0;
uniform float sky_alpha = 1.0;
uniform float cloud_cover = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
// Seconds of cloud time (the shapes evolve with it) and how fast they change; the high layer's drift.
uniform float cloud_time = 0.0;
uniform float cloud_evolve = 1.0;
uniform vec2 high_offset = vec2(0.0);
// How much cirrus shows (0..1) and its cut (noise level where a wisp starts).
uniform float cirrus = 0.0;
uniform float cirrus_cut = 0.6;
// A front: > 0 cloud building, < 0 clearing; it reaches the upwind side first (`wind_dir` the way the wind blows).
uniform float front = 0.0;
uniform float front_gain = 0.35;
uniform float wind_dir = 1.0;
// How much darker the low clouds get as the cover thickens toward rain.
uniform float cloud_heavy = 0.3;
uniform vec4 overcast : source_color = vec4(0.62, 0.67, 0.74, 1.0);
uniform float overcast_strength = 0.0;
uniform vec4 cloud_lit : source_color = vec4(1.0);
uniform vec4 cloud_dark : source_color = vec4(0.5, 0.5, 0.6, 1.0);
uniform float fog = 0.0;
uniform vec4 fog_color : source_color = vec4(0.8, 0.85, 0.9, 1.0);
uniform float fade_left = 0.0;
// A kit grown past its frame: the frame's top-left and size, and the margin on each side (left, top,
// right, bottom; points). `size` covers the whole window; rows and columns count from the frame.
uniform vec2 frame_origin = vec2(0.0);
uniform vec2 frame_size = vec2(1152.0, 512.0);
uniform vec4 margins = vec4(0.0);
// Where the sky ends across each margin (Skypatch issue 144):
// `edge_profile` row 0 is the top margin's (reach, thinning width) along x, row 1 the left margin's along y
// (fractions of the margin, `SceneSkyEdge`), `edge_period` points long, the top shifted by `edge_shift`;
// `edge_cover` is the margin art, blurred: the sky stays behind the canopy and the treeline.
uniform sampler2D edge_profile : filter_linear, repeat_enable;
uniform sampler2D edge_cover : filter_linear;
uniform float edge_period = 2048.0;
uniform float edge_shift = 0.0;
uniform vec2 scene_size = vec2(1200.0, 560.0);
// A small wobble on the end (features `dissolve_wobble_pt` wide), how much further a cloud carries
// the sky, and the cover that keeps it.
uniform float dissolve_wobble = 0.06;
uniform float dissolve_wobble_pt = 14.0;
uniform float dissolve_cloud_carry = 0.25;
uniform vec2 dissolve_cover = vec2(0.15, 0.55);
// How far the sky turns toward its own horizon colour as it thins (0..1); never toward white.
uniform float dissolve_pale = 0.0;
// Overcast thins out darker and greyer (a fraction toward black at the far end), so on a dark desktop its
// last pixels are not pale specks.
uniform float dissolve_dark_overcast = 0.0;
// Beside the frame the sky ends this far (points) either side of the horizon, going down.
uniform float dissolve_below_pt = 20.0;
// Only the clouds, over the sun and the moon (issue 380: they pass in front of them); the sky behind is left out.
uniform bool clouds_only = false;
// The light through those clouds (issue 472, set on the cover only): each disc is x, y, radius (points,
// the frame's) and strength (0: not up). A cloud pixel takes on the light by how thin the cloud is there
// (`glow_thin`: how far above its edge the noise must be to hide the disc completely), over the disc
// (`glow_disc`) and on its rim near it (`glow_rim`, fading over `glow_reach` radii). No ring: one smooth falloff.
uniform vec4 sun_disc = vec4(0.0);
uniform vec4 sun_light : source_color = vec4(1.0, 1.0, 0.53, 1.0);
uniform vec4 moon_disc = vec4(0.0);
uniform vec4 moon_light : source_color = vec4(0.9, 0.94, 0.92, 1.0);
uniform float glow_disc = 0.5;
uniform float glow_rim = 0.3;
uniform float glow_reach = 1.5;
uniform float glow_thin = 0.3;
// The sky's end along an open right or left edge (issue 424), a band `fade_right_pt` / `fade_left_pt` wide
// from the window's edge, by `SceneEdgeFade`'s side profiles (rows 0 and 2: reach, soft by y), the outline the
// ground's dissolve there follows too. With `fade_left_pt` the left margin's own reach gives way to it.
uniform float fade_right_pt = 0.0;
uniform float fade_left_pt = 0.0;
uniform sampler2D fade_profile : filter_linear, repeat_enable;
uniform float fade_period = 2048.0;
// The rain's cloud line (issue 477): as the cover closes in toward rain a heavier, darker deck of the same
// clouds runs along the top of the sky, and the rain falls from its underside. It builds where the cover is
// between `deck_cover` (so a front brings it from upwind and clearing thins it there first); its underside
// is `deck_base_pt` below the frame's top (`SceneSky.deck_base`), lumpy by `deck_lump_pt` over
// `deck_lump_wave_pt`, soft over `deck_soft_pt`. Inside it the cloud is denser by `deck_dense` and shaded
// toward `deck_dark` (its underside) and `deck_mid` (its upper layers) by `deck_mix`.
uniform vec2 deck_cover = vec2(2.0, 3.0);
uniform float deck_base_pt = 0.0;
uniform float deck_lump_pt = 6.0;
uniform float deck_lump_wave_pt = 60.0;
uniform float deck_soft_pt = 4.0;
uniform float deck_dense = 0.6;
uniform float deck_layers = 1.8;
uniform float deck_mix = 0.85;
uniform vec4 deck_dark : source_color = vec4(0.3, 0.33, 0.38, 1.0);
uniform vec4 deck_mid : source_color = vec4(0.42, 0.45, 0.5, 1.0);

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float bayer4(vec2 a) {
	int x = int(mod(a.x, 4.0));
	int y = int(mod(a.y, 4.0));
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

// How much of a disc's light a cloud pixel at `at` takes on, `thin` 1 at its edge to 0 deep inside.
float light_through(vec4 disc, vec2 at, float thin) {
	if (disc.w <= 0.0) {
		return 0.0;
	}
	float d = length(at - disc.xy);
	float over = 1.0 - smoothstep(disc.z - 1.0, disc.z + 1.0, d);
	float rim = 1.0 - smoothstep(disc.z * 0.6, disc.z * (1.0 + glow_reach), d);
	return disc.w * thin * (glow_disc * over + glow_rim * rim * rim);
}

// The light in a gap over a disc: the disc's share of `light_through`, fading out just past its edge.
float disc_through(vec4 disc, vec2 at, float thin) {
	if (disc.w <= 0.0) {
		return 0.0;
	}
	float over = 1.0 - smoothstep(disc.z - 1.0, disc.z + 3.0, length(at - disc.xy));
	return disc.w * thin * (glow_disc + glow_rim) * over;
}

// Where this node draws a disc (with the sun's halo), so the cover fills its gaps there and nowhere else.
bool near_disc(vec4 disc, vec2 at) {
	return disc.w > 0.0 && length(at - disc.xy) < disc.z + 5.0;
}

void fragment() {
	vec2 art = floor(UV * size * px);
	vec2 p = art / px - frame_origin;
	// The margin: how far out into it on each side (0 at the frame, 1 at the window's edge).
	vec2 out_lo = vec2(margins.x > 0.0 ? max(-p.x, 0.0) / margins.x : 0.0, margins.y > 0.0 ? max(-p.y, 0.0) / margins.y : 0.0);
	vec2 out_hi = vec2(margins.z > 0.0 ? max(p.x - frame_size.x, 0.0) / margins.z : 0.0,
			margins.w > 0.0 ? max(p.y - frame_size.y, 0.0) / margins.w : 0.0);
	vec2 out2 = max(out_lo, out_hi);
	bool in_margin = out2.x > 0.0 || out2.y > 0.0;
	float right_keep = 1.0;
	if (fade_right_pt > 0.0) {
		vec2 at_r = p + frame_origin;
		float o = (at_r.x - (scene_size.x - fade_right_pt)) / fade_right_pt;
		if (o > 0.0) {
			vec2 e = texture(fade_profile, vec2(fract(at_r.y / fade_period), 1.0 / 6.0)).rg;
			float wob_r = (fbm(p / dissolve_wobble_pt + vec2(5.1, 2.3)) - 0.5) * 2.0 * dissolve_wobble;
			right_keep = 1.0 - smoothstep(max(e.x - e.y, 0.0), e.x, o + wob_r * min(o * 4.0, 1.0));
			right_keep *= 1.0 - smoothstep(0.9, 0.99, o);
		}
	}
	if (fade_left_pt > 0.0) {
		vec2 at_l = p + frame_origin;
		float o = (fade_left_pt - at_l.x) / fade_left_pt;
		if (o > 0.0) {
			vec2 e = texture(fade_profile, vec2(fract(at_l.y / fade_period), 5.0 / 6.0)).rg;
			float wob_l = (fbm(p / dissolve_wobble_pt + vec2(1.7, 8.9)) - 0.5) * 2.0 * dissolve_wobble;
			float k_l = 1.0 - smoothstep(max(e.x - e.y, 0.0), e.x, o + wob_l * min(o * 4.0, 1.0));
			right_keep *= k_l * (1.0 - smoothstep(0.9, 0.99, o));
		}
	}
	// The clouds, here so they can carry the sky out further than the clear patches.
	vec2 q = (p + cloud_offset * 0.6) * vec2(0.0045, 0.016);
	float n = cl_cumulus(q, cloud_time, cloud_evolve);
	float cover_here = cl_front_cover(cloud_cover, front, wind_dir, p.x / frame_size.x, front_gain);
	float edge = 1.0 - cover_here * 0.95;
	// The deck: how much of it is here (0 above the cover's range or below its underside, 1 inside).
	float deck = 0.0;
	float deck_rel = 0.0;
	if (deck_base_pt > 0.0) {
		float lump = (fbm(vec2((p.x + cloud_offset.x * 0.6) / deck_lump_wave_pt, cloud_time * 0.004)) - 0.5) * 2.0 * deck_lump_pt;
		float base = deck_base_pt * smoothstep(deck_cover.x, deck_cover.y, cover_here) + lump;
		deck = (1.0 - smoothstep(base - deck_soft_pt, base + deck_soft_pt, p.y)) * step(0.5, base);
		deck_rel = clamp(p.y / max(base, 1.0), 0.0, 1.0);
	}
	n += deck * deck_dense * (0.6 + 0.4 * deck_rel);
	float keep = 1.0;
	if (in_margin) {
		// Each side ends where its profile says (lobes and bays a cloud wide), a little ragged, and
		// further where a cloud is; the corner is the two sides together, then the art's cover.
		float wob = (fbm(p / dissolve_wobble_pt + vec2(3.7, 11.3)) - 0.5) * 2.0 * dissolve_wobble;
		float carry = dissolve_cloud_carry * smoothstep(edge - 0.1, edge + 0.15, n) * (1.0 - clamp(overcast_strength * 1.5, 0.0, 1.0));
		vec2 at = p + frame_origin;
		vec2 e_top = texture(edge_profile, vec2(fract((at.x + edge_shift) / edge_period), 0.25)).rg;
		vec2 e_left = texture(edge_profile, vec2(fract(at.y / edge_period), 0.75)).rg;
		float r_top = e_top.x + carry;
		float r_left = e_left.x + carry * 0.5;
		// The wobble grows in from the frame, so nothing changes on the frame's own line.
		float k_top = out2.y > 0.0 ? 1.0 - smoothstep(max(r_top - e_top.y, 0.0), r_top, out2.y + wob * min(out2.y * 4.0, 1.0)) : 1.0;
		float k_left = out2.x > 0.0 && fade_left_pt <= 0.0 ? 1.0 - smoothstep(max(r_left - e_left.y, 0.0), r_left, out2.x + wob * min(out2.x * 4.0, 1.0)) : 1.0;
		keep = k_top * k_left;
		float cover = texture(edge_cover, at / scene_size).r;
		keep = max(keep, smoothstep(dissolve_cover.x, dissolve_cover.y, cover + wob));
		keep *= 1.0 - smoothstep(0.85, 0.98, max(out2.x, out2.y));
		// Beside the frame there is no sky below the treeline: the far forest and the bank end
		// there like a vignette, with the desktop behind them.
		float along = fbm(p / 30.0 + vec2(3.7, 11.3)) - 0.5;
		float below = smoothstep(horizon_y - dissolve_below_pt, horizon_y + dissolve_below_pt, p.y + along * dissolve_below_pt * 2.0);
		keep *= 1.0 - below * min(out_lo.x * 6.0, 1.0);
	}
	// 0 at the top of the band, 1 at the horizon and below.
	float v = clamp(p.y / horizon_y, 0.0, 1.0);
	// The sky: deep at the top, pale toward the horizon, most of the change low down.
	vec3 col = mix(glow_high.rgb, glow_low.rgb, pow(v, 1.8));
	float a = max(glow * pow(v, 1.15), sky_alpha);
	// Overcast: a grey veil over it, heaviest low.
	col = mix(col, overcast.rgb, clamp(overcast_strength * (0.55 + 0.45 * v), 0.0, 1.0));
	a = max(a, overcast_strength * pow(v, 1.6));
	// Cirrus: thin streaks high up, behind the low clouds, a sparse dither of a pale tone.
	if (cirrus > 0.0) {
		float ci = cl_cirrus((p + high_offset) * vec2(0.0024, 0.034), cloud_time, cloud_evolve);
		float wisp = smoothstep(cirrus_cut, cirrus_cut + 0.16, ci) * cirrus * (1.0 - smoothstep(0.25, 0.85, v));
		wisp *= smoothstep(0.15, 0.75, keep);
		if (wisp * 0.6 > bayer4(art + vec2(2.0, 1.0))) {
			col = mix(col, mix(cloud_lit.rgb, col, 0.35), 0.6);
			a = max(a, 0.7);
		}
	}
	// Clouds: soft long shapes, lit underneath, darker at their tops; the edge dithered.
	float body = smoothstep(edge - 0.06, edge + 0.12, n) * mix(0.35 + 0.65 * smoothstep(0.0, 0.5, v), 1.0, deck);
	// Clouds thin out as they reach the dissolve, ahead of the sky behind them.
	body *= smoothstep(0.15, 0.75, keep);
	bool is_cloud = body > bayer4(art);
	// Over the sun and the moon (the cover only, issue 472): how thick the cloud is there, 0 at its edge
	// to 1 a little inside (`glow_thin`), whatever the dither high up leaves open.
	bool lit = clouds_only && (sun_disc.w > 0.0 || moon_disc.w > 0.0);
	vec2 at = (art + 0.5) / px - frame_origin;
	float thick = smoothstep(edge - 0.06, edge + glow_thin, n) * smoothstep(0.15, 0.75, keep);
	if (is_cloud) {
		float under = smoothstep(0.35, 1.0, v);
		float shade = clamp(0.4 + under * 0.35 + (n - edge) * 2.0, 0.0, 1.0);
		shade = floor(shade * 3.0 + 0.5) / 3.0;
		vec3 cc = mix(cloud_dark.rgb, cloud_lit.rgb, shade);
		cc *= 1.0 - cloud_heavy * smoothstep(0.55, 1.0, cover_here);
		if (deck > 0.0) {
			// Layers of the same clouds, lighter on top and darkest along the underside, in three tones.
			float layer = cl_cumulus(q * deck_layers + vec2(7.3, 2.9), cloud_time * 1.3, cloud_evolve);
			float tone = clamp(0.75 - deck_rel * 0.6 + (layer - 0.5) * 1.4, 0.0, 1.0);
			// Dithered between the tones, one art px at a time, so the layers never end on a smooth line.
			tone = clamp(floor(tone * 2.0 + bayer4(art + vec2(1.0, 3.0))) / 2.0, 0.0, 1.0);
			cc = mix(cc, mix(deck_dark.rgb, deck_mid.rgb, tone), deck * deck_mix);
		}
		col = mix(col, cc, 0.9);
		a = max(a, 0.85);
	}
	if (clouds_only && !is_cloud) {
		a = 0.0;
		// The gaps the dither leaves in a cloud over a disc: the sky's own colour again once there is any
		// body to the cloud, lit by the disc as the cloud thins, so a thick body hides the disc completely
		// and looks the same as beside it, and a thin one glows (never the disc's colour through the sky's).
		if (lit && (near_disc(sun_disc, at) || near_disc(moon_disc, at))) {
			a = smoothstep(0.0, 0.35, thick);
			col = mix(col, sun_light.rgb, clamp(disc_through(sun_disc, at, 1.0 - thick), 0.0, 1.0));
			col = mix(col, moon_light.rgb, clamp(disc_through(moon_disc, at, 1.0 - thick), 0.0, 1.0));
		}
	}
	if (lit && is_cloud) {
		col = mix(col, sun_light.rgb, clamp(light_through(sun_disc, at, 1.0 - thick), 0.0, 1.0));
		col = mix(col, moon_light.rgb, clamp(light_through(moon_disc, at, 1.0 - thick), 0.0, 1.0));
	}
	col = mix(col, fog_color.rgb, clamp(fog * 0.85, 0.0, 1.0));
	a = max(a, fog * 0.9 * pow(v, 0.35));
	if (fade_left > 0.0) {
		float wander = (noise(vec2(0.0, p.y * 0.08)) - 0.5) * fade_left * 0.5;
		a *= smoothstep(0.0, fade_left, p.x + wander);
	}
	if (in_margin) {
		// Thinning by coverage, never lighter: at most a touch toward the sky's own horizon colour.
		// Then gone pixel by pixel: a blue-noise threshold (interleaved gradient noise) in whole
		// art px, so the dissolve has no pattern and no line.
		col = mix(col, glow_low.rgb, (1.0 - keep) * dissolve_pale);
		col *= 1.0 - (1.0 - keep) * dissolve_dark_overcast * clamp(overcast_strength * 1.5, 0.0, 1.0);
		float threshold = fract(52.9829189 * fract(dot(art, vec2(0.06711056, 0.00583715))));
		a *= keep > threshold ? 1.0 : 0.0;
	}
	if (right_keep < 1.0) {
		float threshold_r = fract(52.9829189 * fract(dot(art + vec2(17.0, 5.0), vec2(0.06711056, 0.00583715))));
		a *= right_keep > threshold_r ? 1.0 : 0.0;
	}
	// A whisper of noise, so a slow gradient never shows 8-bit bands.
	float grain = (hash(art) - 0.5) / 64.0;
	COLOR = vec4(col + grain, clamp(a, 0.0, 1.0));
}
