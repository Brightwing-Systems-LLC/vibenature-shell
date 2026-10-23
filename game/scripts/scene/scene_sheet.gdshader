shader_type canvas_item;

// A creature sheet cut at the waterline (Skypatch issue 112):
// a wading heron's legs, a swimming turtle's shell below the surface. `waterline` is in the
// sprite's own px (feet at 0, up negative); below it the drawing shows only `below_alpha`.
// `haze` mixes the drawing toward `haze_color` (already lit): a fish toward the back of the
// cut-away, seen through the water (Skypatch issue 156).

uniform float waterline = 1.0e6;
uniform float below_alpha = 0.0;
uniform float haze = 0.0;
uniform vec4 haze_color : source_color = vec4(0.2, 0.35, 0.35, 1.0);
// The open edges (issue 424): an animal at the scene's faded ground dissolves with it rather than
// standing cut off in the air. `fade_x`, `fade_y`, `fade_o` take the sprite's own px to scene points;
// `fade_edges` the open bands (left margin, right, bottom; points) and the scene's width; `fade_h` its
// height; `fade_soft` where across a band it starts and ends.
uniform bool fade_on = false;
uniform vec2 fade_x = vec2(1.0, 0.0);
uniform vec2 fade_y = vec2(0.0, 1.0);
uniform vec2 fade_o = vec2(0.0);
uniform vec4 fade_edges = vec4(0.0);
uniform float fade_h = 0.0;
uniform vec2 fade_soft = vec2(0.3, 0.85);
varying float local_y;
varying vec2 scene_at;

void vertex() {
	local_y = VERTEX.y;
	scene_at = fade_o + fade_x * VERTEX.x + fade_y * VERTEX.y;
}

void fragment() {
	COLOR.rgb = mix(COLOR.rgb, haze_color.rgb, haze);
	if (fade_on) {
		float k = 1.0;
		if (fade_edges.x > 0.0) {
			k *= 1.0 - smoothstep(fade_soft.x, fade_soft.y, (fade_edges.x - scene_at.x) / fade_edges.x);
		}
		if (fade_edges.y > 0.0) {
			k *= 1.0 - smoothstep(fade_soft.x, fade_soft.y, (scene_at.x - (fade_edges.w - fade_edges.y)) / fade_edges.y);
		}
		if (fade_edges.z > 0.0) {
			k *= 1.0 - smoothstep(fade_soft.x, fade_soft.y, (scene_at.y - (fade_h - fade_edges.z)) / fade_edges.z);
		}
		vec2 cell = floor(scene_at * 2.0);
		if (fract(52.9829189 * fract(dot(cell, vec2(0.06711056, 0.00583715)))) >= k) {
			COLOR.a = 0.0;
		}
	}
	if (local_y > waterline) {
		COLOR.a *= below_alpha;
	}
}
