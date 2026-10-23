shader_type canvas_item;
render_mode blend_mix;

// Everything in the living scene draws through this: plates, pieces, the avatar and the birds.
// One look for all of it: the bend of a piece in the wind (per column, from `sway_tex`), the
// water's motion where the kit's mask says water (larger and slower toward the viewer), moving
// cloud shadows, wet ground after rain, the time of day's tint, and fog by depth.
// Positions are in scene points (the window's units before its scale); a texture's own pixels
// are `density` to the point (the kit's art_scale; 1 for the avatar and the birds).

// Where this canvas item's texture sits in the scene (its top-left, points), its pixels per
// point, and the transparent margin (texture px) the game padded it with so a bend never clips.
uniform vec2 origin = vec2(0.0);
uniform float density = 1.0;
uniform float pad = 0.0;
// Pixel-art kits: every texel moves as one and by whole texels (bends, ripples, wobble), so the
// art stays hard-edged; the texture is sampled nearest.
uniform bool pixel_snap = false;
// Breathing for a whole-sprite figure (issue 123): texture rows above `breath_row` are drawn `breath_lift` px higher
// (the chest and shoulders rise on the in-breath; the legs stay put).
uniform float breath_lift = 0.0;
uniform float breath_row = 0.0;

// Bend: per column displacement in points (r: sideways, g: down), sampled across the piece.
uniform bool sways = false;
uniform sampler2D sway_tex : filter_linear, repeat_disable;
uniform vec2 piece_size = vec2(1.0);
uniform float sway_cols = 2.0;
uniform float pivot_y = 1.0;
uniform float bend_power = 2.0;
// Leaves catching a gust: tiny per-clump flicker in brightness and position.
uniform float flutter = 0.0;
// Far broadleaf crowns (Skypatch issue 165): leaves turning in
// the wind like aspens. A texel of the crown now and then takes the lightest colour just above or
// beside it in the piece's own art (so the light stays in the piece's ramp), more often in a gust,
// never in calm air. `shimmer` is the share of crown texels lit in a strong gust.
uniform float shimmer = 0.0;
uniform float shimmer_calm = 0.2;
uniform float shimmer_rate = 7.0;
uniform float shimmer_from = 0.35;

// Margin art that continues an old piece across the old border (kit `follows`,
// Skypatch issue 137): it takes the parent's bend where it
// stands (the parent's columns, the nearest one outside it; the parent's height curve, held at the
// parent's ends), exactly as the parent computes it, so the seam never opens. Its own sway is added
// only away from the old frame, growing over `follow_ramp` points, so at the border it is the parent.
uniform bool follows = false;
uniform sampler2D follow_tex : filter_linear, repeat_disable;
// This piece's top-left minus the parent's, in texture px; the parent's size, columns, pivot row, power.
uniform vec2 follow_delta = vec2(0.0);
uniform vec2 follow_size = vec2(1.0);
uniform float follow_cols = 2.0;
uniform float follow_pivot_y = 1.0;
uniform float follow_power = 2.0;
// The old composition in points, and how far outside it a follower's own sway is fully in.
uniform vec4 frame_rect = vec4(0.0);
uniform float follow_ramp = 1.0;
// 1 drawn, 0 gone: a dropped leaf leaves and regrows through an ordered dither (alpha stays 0 or 1).
uniform float reveal = 1.0;

// Shared state of the environment.
uniform float time = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float shadow_strength = 0.0;
uniform float cloud_cover = 0.0;
uniform vec2 cloud_offset = vec2(0.0);
// The living clouds (Skypatch issue 146): the shadows change
// with the sky's clouds, and a front reaches the upwind side first.
uniform float cloud_time = 0.0;
uniform float cloud_evolve = 1.0;
uniform float cloud_front = 0.0;
uniform float front_gain = 0.35;
// The pond mirrors the sky's low clouds (the sky's cover, its horizon row and the clouds' lit tone).
uniform float sky_cover = 0.0;
uniform float sky_horizon = 118.0;
uniform vec4 reflect_color : source_color = vec4(0.95, 0.96, 0.97, 1.0);
uniform float reflect_strength = 0.0;
uniform float reflect_stretch = 2.5;
uniform float fog = 0.0;
uniform vec4 fog_color : source_color = vec4(0.8, 0.85, 0.9, 1.0);
// 0 far .. 1 near: fog thins toward the viewer.
uniform float depth = 0.0;
uniform float wet = 0.0;
uniform float sunshine = 0.0;
uniform float moonlight = 0.0;

// Water. `water` 0 for things that never ripple (most pieces, the avatar), 1 for plates and lilies.
uniform float water = 0.0;
uniform sampler2D water_mask : filter_nearest, repeat_disable;
uniform sampler2D gust_tex : filter_linear, repeat_disable;
uniform vec2 scene_size = vec2(1152.0, 512.0);
// The far waterline and the nearest water (points): ripples grow toward the viewer.
uniform float water_top = 260.0;
uniform float water_bottom = 400.0;
uniform vec4 under_rect = vec4(0.0);
uniform float wind_dir = 1.0;
uniform float wind_mean = 0.2;
uniform float rain = 0.0;

// The open edges fade into the desktop (issue 424):
// the edges against the screen stay straight, the open ones dissolve, each layer on its own blue-noise
// threshold (`fade_seed`), alpha 0 or 1. `fade_band` is the width (points) of the band along the world's
// right and bottom, `fade_left` along its left (0: against the screen); `fade_profile` rows the right's (reach,
// soft) by y, the bottom's by x and the left's by y (`SceneEdgeFade`), the same outline the sky's side edges use.
uniform vec2 fade_band = vec2(0.0);
uniform float fade_left = 0.0;
uniform sampler2D fade_profile : filter_linear, repeat_enable;
uniform float fade_period = 2048.0;
uniform float fade_seed = 0.0;

#include "res://scripts/scene/scene_clouds.gdshaderinc"

// COLOR in fragment() already holds the texture at UV; the modulate alone comes from vertex().
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

float fade_side(float o, vec2 e) {
	if (o <= 0.0) {
		return 1.0;
	}
	return (1.0 - smoothstep(max(e.x - e.y, 0.0), e.x, o)) * (1.0 - smoothstep(0.85, 0.98, o));
}

// How much of the art is left at `world` (points): 1 away from the open edges, 0 past where they end.
float fade_keep(vec2 world) {
	float k = 1.0;
	if (fade_band.x > 0.0) {
		vec2 e = texture(fade_profile, vec2(fract(world.y / fade_period), 1.0 / 6.0)).rg;
		k *= fade_side((world.x - (scene_size.x - fade_band.x)) / fade_band.x, e);
	}
	if (fade_band.y > 0.0) {
		vec2 e = texture(fade_profile, vec2(fract(world.x / fade_period), 0.5)).rg;
		k *= fade_side((world.y - (scene_size.y - fade_band.y)) / fade_band.y, e);
	}
	if (fade_left > 0.0) {
		vec2 e = texture(fade_profile, vec2(fract(world.y / fade_period), 5.0 / 6.0)).rg;
		k *= fade_side((fade_left - world.x) / fade_left, e);
	}
	return k;
}

// Interleaved gradient noise: a blue-noise-like threshold per cell, no pattern and no crosshatch.
float ign(vec2 cell) {
	return fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715))));
}

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
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

float gust(float x) {
	return texture(gust_tex, vec2(clamp(x / scene_size.x, 0.0, 1.0), 0.5)).r;
}

float cloud_shadow(vec2 world) {
	// Clouds are long and soft; their shadows drift across with the sky's low clouds and change as they do.
	vec2 p = (world + cloud_offset) * vec2(0.0042, 0.0095);
	float n = cl_cumulus(p, cloud_time, cloud_evolve);
	float x01 = (world.x - frame_rect.x) / max(frame_rect.z, 1.0);
	float edge = 1.0 - cl_front_cover(cloud_cover, cloud_front, wind_dir, x01, front_gain);
	return smoothstep(edge - 0.08, edge + 0.12, n);
}

// How much of a low cloud the water at `world` mirrors: the sky row as far above the horizon as this
// row is below the far waterline (stretched: the pond is seen at a low angle), in the sky's coordinates.
float cloud_reflection(vec2 world) {
	vec2 sky = vec2(world.x - frame_rect.x, sky_horizon - (world.y - water_top) * reflect_stretch);
	if (sky.y < 0.0) {
		return 0.0;
	}
	vec2 q = (sky + cloud_offset * 0.6) * vec2(0.0045, 0.016);
	float n = cl_cumulus(q, cloud_time, cloud_evolve);
	float edge = 1.0 - cl_front_cover(sky_cover, cloud_front, wind_dir, sky.x / max(frame_rect.z, 1.0), front_gain) * 0.95;
	return smoothstep(edge - 0.06, edge + 0.12, n);
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 px = UV * tex_size;
	if (pixel_snap) {
		px = floor(px) + 0.5;
	}
	vec2 world = origin + (px - vec2(pad)) / density;
	vec2 src = px;
	float lift = 0.0;
	float crown_h = 0.0;

	if (sways || follows) {
		vec2 local = px - vec2(pad);
		vec2 offset = vec2(0.0);
		float h = 0.0;
		if (sways) {
			// The pivot may be at the foot (a reed) or at the top (leaves hanging from a branch).
			float far_end = pivot_y > piece_size.y * 0.5 ? pivot_y : piece_size.y - pivot_y;
			h = clamp(abs(pivot_y - local.y) / max(far_end, 1.0), 0.0, 1.0);
			float bend = pow(h, bend_power);
			float u = clamp(local.x / piece_size.x, 0.0, 1.0);
			vec2 d = texture(sway_tex, vec2((u * (sway_cols - 1.0) + 0.5) / sway_cols, 0.5)).rg;
			// A bent stem also shortens a little: its end dips as it leans.
			offset = vec2(d.x * bend, d.y * bend + abs(d.x) * bend * bend * 0.12);
		}
		if (follows) {
			vec2 out_lo = frame_rect.xy - world;
			vec2 out_hi = world - (frame_rect.xy + frame_rect.zw);
			float outside = max(max(max(out_lo.x, out_lo.y), max(out_hi.x, out_hi.y)), 0.0);
			offset *= smoothstep(0.0, follow_ramp, outside);
			vec2 plocal = local + follow_delta;
			float pfar = follow_pivot_y > follow_size.y * 0.5 ? follow_pivot_y : follow_size.y - follow_pivot_y;
			float ph = clamp(abs(follow_pivot_y - plocal.y) / max(pfar, 1.0), 0.0, 1.0);
			float pb = pow(ph, follow_power);
			float pu = clamp(plocal.x / follow_size.x, 0.0, 1.0);
			vec2 pd = texture(follow_tex, vec2((pu * (follow_cols - 1.0) + 0.5) / follow_cols, 0.5)).rg;
			offset += vec2(pd.x * pb, pd.y * pb + abs(pd.x) * pb * pb * 0.12);
			// The flutter is the parent's where they meet, then this piece's own further out.
			h = mix(ph, max(ph, h), smoothstep(0.0, follow_ramp, outside));
		}
		if (flutter > 0.0) {
			vec2 clump = floor(world / 3.0);
			float g = gust(world.x);
			float k = flutter * (0.25 + g) * h;
			offset.x += k * 0.55 * sin(time * 9.0 + hash(clump) * 6.283);
			lift = k * pow(max(0.0, sin(time * 6.0 + hash(clump + 7.0) * 6.283)), 6.0);
		}
		crown_h = h;
		vec2 shift = offset * density;
		src = px - (pixel_snap ? round(shift) : shift);
	}

	if (breath_lift > 0.0 && px.y < breath_row) {
		src.y += breath_lift;
	}

	bool in_water = false;
	bool under = false;
	float persp = 1.0;
	if (water > 0.5) {
		vec2 muv = world / scene_size;
		vec4 m = texture(water_mask, muv);
		in_water = muv.x >= 0.0 && muv.y >= 0.0 && muv.x <= 1.0 && muv.y <= 1.0 && m.a * max(m.r, max(m.g, m.b)) > 0.5;
		under = !in_water && under_rect.z > 0.0 && world.y > water_top && world.x >= under_rect.x
				&& world.x <= under_rect.x + under_rect.z && world.y <= under_rect.y + under_rect.w;
		if (in_water) {
			// Seen at a low angle: far water is fine and quick, near water broad and slow.
			persp = mix(0.35, 1.6, clamp((world.y - water_top) / max(water_bottom - water_top, 1.0), 0.0, 1.0));
			float g = gust(world.x);
			float row = floor(world.y * density / max(persp, 0.5));
			float lap = sin(row * 1.37 + time * 1.15 / sqrt(persp) + world.x * 0.018 / persp) * 0.55
					+ sin(row * 2.71 - time * 1.9 / sqrt(persp) + world.x * 0.041 / persp) * 0.35;
			src.x += lap * (0.3 + wind_mean * 0.8 + g * 1.4) * persp * density;
		} else if (under) {
			float wobble = sin(world.y * 0.23 + time * 1.05 + world.x * 0.012) + 0.5 * sin(world.y * 0.61 - time * 1.6);
			src.x += wobble * (0.28 + 0.25 * gust(world.x)) * density;
		}
	}

	if (pixel_snap) {
		src = floor(src) + 0.5;
	}
	vec4 c = texture(TEXTURE, src / tex_size);
	if (shimmer > 0.0 && c.a > 0.0 && crown_h > shimmer_from) {
		float stir = clamp((gust(world.x) + max(wind_mean - shimmer_calm, 0.0) * 0.5) / 1.2, 0.0, 1.0);
		vec2 cell = floor(src);
		float tick = floor(time * shimmer_rate + hash(cell + 3.1) * 4.0);
		float chance = shimmer * stir * smoothstep(shimmer_from, 1.0, crown_h);
		if (hash(cell + vec2(tick * 0.37, tick * 0.91)) < chance) {
			float own = dot(c.rgb, vec3(0.3, 0.59, 0.11));
			vec4 best = c;
			float lightest = own;
			for (int i = 0; i < 3; i++) {
				vec4 n = texture(TEXTURE, (src + vec2(float(i - 1), -1.0)) / tex_size);
				float l = dot(n.rgb, vec3(0.3, 0.59, 0.11));
				if (n.a > 0.0 && l > lightest) {
					best = n;
					lightest = l;
				}
			}
			c = vec4(best.rgb, c.a);
		}
	}
	if (reveal < 1.0) {
		vec2 cell = mod(floor(px), 4.0);
		int bayer[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
		if ((float(bayer[int(cell.y) * 4 + int(cell.x)]) + 0.5) / 16.0 >= reveal) {
			c.a = 0.0;
		}
	}
	if (c.a > 0.0 && (fade_band.x > 0.0 || fade_band.y > 0.0 || fade_left > 0.0)) {
		if (ign(floor(world * density) + vec2(fade_seed * 131.0, fade_seed * 71.0)) >= fade_keep(world)) {
			c.a = 0.0;
		}
	}
	if (c.a <= 0.0) {
		COLOR = vec4(0.0);
	} else {
		vec3 rgb = c.rgb;
		if (in_water) {
			vec2 w = world;
			float g = gust(w.x);
			// Cat's paws: patches of darker, rougher water running downwind with the gusts.
			vec2 q = vec2(w.x - wind_dir * time * (18.0 + 40.0 * wind_mean), w.y * 3.0 / persp) * vec2(0.035 / persp, 0.09);
			float paw = smoothstep(0.5, 0.78, fbm(q));
			rgb *= 1.0 - (0.08 + 0.2 * g) * paw * clamp(wind_mean * 1.5 + g, 0.0, 1.0);
			// Sun glints: single bright points that come and go, more when the water is rough.
			vec2 cell = floor(px / vec2(2.0, 1.0));
			float flick = hash(cell + floor(time * (5.0 + 6.0 * g)));
			float chance = (0.0008 + 0.012 * g + 0.002 * wind_mean) * (0.6 + persp * 0.4);
			// The clouds overhead, mirrored: a dithered pale tone, strongest on the far water.
			if (reflect_strength > 0.0) {
				vec2 rw = vec2(world.x + (src.x - px.x) / density, world.y);
				float near = clamp((world.y - water_top) / max(water_bottom - water_top, 1.0), 0.0, 1.0);
				float r = cloud_reflection(rw) * (1.0 - 0.6 * near);
				vec2 cellb = mod(floor(px), 4.0);
				int bayerb[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
				if (r > (float(bayerb[int(cellb.y) * 4 + int(cellb.x)]) + 0.5) / 16.0) {
					rgb = mix(rgb, reflect_color.rgb, reflect_strength);
				}
			}
			if (flick > 1.0 - chance) {
				rgb = mix(rgb, vec3(1.0, 0.98, 0.88), 0.7 * max(sunshine, moonlight * 0.6) * (1.0 - rain * 0.6));
			}
		} else if (under) {
			float depth_k = clamp((world.y - water_top) / 150.0, 0.0, 1.0);
			vec2 p = world * vec2(0.06, 0.09) + vec2(time * 0.35, -time * 0.22);
			float caustic = pow(abs(sin(fbm(p) * 9.0 + time * 0.8)), 4.0);
			float light = sunshine * (1.0 - cloud_cover * 0.6) * (1.0 - rain * 0.7);
			rgb += vec3(0.55, 0.85, 0.75) * caustic * 0.08 * light * (1.0 - depth_k);
		}
		if (lift > 0.0) {
			rgb = mix(rgb, rgb * vec3(1.18, 1.22, 1.05) + 0.03, clamp(lift, 0.0, 1.0));
		}
		// Wet ground and leaves: darker and a touch richer.
		rgb = mix(rgb, rgb * rgb * 1.35, wet * 0.28);
		float shade = shadow_strength > 0.0 ? cloud_shadow(world) * shadow_strength : 0.0;
		rgb *= 1.0 - shade;
		rgb *= tint.rgb;
		float f = fog * (1.0 - depth * 0.65);
		rgb = mix(rgb, fog_color.rgb, clamp(f, 0.0, 0.92));
		COLOR = vec4(rgb, c.a) * modulate;
	}
}
