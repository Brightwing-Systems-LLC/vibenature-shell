shader_type canvas_item;

// Mist and low cloud lying over the water and the bank: soft banks of white that drift slowly
// downwind and breathe, densest a little above the waterline. One layer behind the near cover,
// one fainter, higher layer against the far trees. Translucent and soft.

uniform vec2 size = vec2(1152.0, 512.0);
uniform float amount = 0.0;
uniform float center_y = 204.0;
uniform float above = 26.0;
uniform float below = 10.0;
uniform float time = 0.0;
uniform float drift = 4.0;
uniform vec4 color : source_color = vec4(0.92, 0.94, 0.96, 1.0);
uniform float fade_left = 0.0;
uniform float max_alpha = 0.75;
// The open right and bottom edges (issue 424): the mist thins out across the fade band (points; 0 flush).
uniform vec2 fade_band = vec2(0.0);
uniform float fade_left_band = 0.0;

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
		p = p * 2.07 + vec2(5.3, 1.7);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = floor(UV * size);
	float dy = p.y - center_y;
	float profile = dy < 0.0 ? exp(-pow(dy / above, 2.0)) : exp(-pow(dy / below, 2.0));
	vec2 q = vec2(p.x - time * drift, p.y * 2.6) * vec2(0.012, 0.03);
	float n = fbm(q + vec2(0.0, time * 0.02));
	float n2 = fbm(q * 2.3 - vec2(time * 0.03, 0.0));
	float body = smoothstep(0.32, 0.72, n * 0.75 + n2 * 0.35);
	float a = amount * profile * (0.35 + 0.65 * body) * max_alpha;
	if (fade_left > 0.0) {
		a *= smoothstep(0.0, fade_left, p.x + (noise(vec2(3.0, p.y * 0.1)) - 0.5) * fade_left * 0.6);
	}
	if (fade_band.x > 0.0) {
		a *= 1.0 - smoothstep(0.2, 0.75, (p.x - (size.x - fade_band.x)) / fade_band.x);
	}
	if (fade_left_band > 0.0) {
		a *= 1.0 - smoothstep(0.2, 0.75, (fade_left_band - p.x) / fade_left_band);
	}
	if (fade_band.y > 0.0) {
		a *= 1.0 - smoothstep(0.2, 0.75, (p.y - (size.y - fade_band.y)) / fade_band.y);
	}
	float grain = (hash(FRAGCOORD.xy) - 0.5) / 128.0;
	COLOR = vec4(color.rgb, clamp(a + grain, 0.0, 0.9));
}
