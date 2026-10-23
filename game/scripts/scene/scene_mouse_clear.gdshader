shader_type canvas_item;
// Mouse clear (issue 428): multiplies what the window has drawn by k, colour and alpha together
// (the render is premultiplied, so cutting both keeps the edge from fringing). k is 0 in the
// middle of the circle and rises smoothly to 1 at its rim; inside a kept rect it stays 1.
render_mode blend_mul, unshaded;

uniform vec2 center;
uniform float inner;
uniform float outer;
uniform vec4 keep[8];
uniform int keep_count = 0;

varying vec2 at;

void vertex() {
	at = VERTEX;
}

void fragment() {
	float k = smoothstep(inner, outer, distance(at, center));
	for (int i = 0; i < keep_count; i++) {
		vec4 r = keep[i];
		if (at.x >= r.x && at.y >= r.y && at.x < r.x + r.z && at.y < r.y + r.w) {
			k = 1.0;
		}
	}
	COLOR = vec4(k);
}
