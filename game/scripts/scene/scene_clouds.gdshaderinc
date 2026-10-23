// The living clouds (Skypatch issue 146), shared by the sky
// (`scene_sky.gdshader`), and the ground's shadows and the pond's reflection (`scene_lit.gdshader`), so
// all three show the same clouds. A cloud field is fbm noise whose domain is warped by a second, slower
// noise that itself moves with `t` (seconds of cloud time), and whose octaves slide at their own rates:
// shapes swell, split, merge and thin out while the whole pattern drifts with the wind. A slow coverage
// field on top lets whole patches form and dissolve. A front (`front` > 0: building, < 0: clearing) moves
// the cover across the scene from the upwind side (`wind_dir`, +1: wind blowing toward +x).

float cl_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float cl_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(cl_hash(i), cl_hash(i + vec2(1.0, 0.0)), f.x), mix(cl_hash(i + vec2(0.0, 1.0)), cl_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// fbm whose octaves each slide a little differently with `t`, so the fine detail changes against the
// coarse shapes rather than gliding with them.
float cl_fbm(vec2 p, float t, int octaves) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < octaves; i++) {
		float k = float(i);
		v += a * cl_noise(p + t * vec2(0.010 + 0.006 * k, -0.004 + 0.005 * mod(k, 2.0)));
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v;
}

// The low, puffy layer at `q` (noise units: the caller scales points to its own cloud size).
float cl_cumulus(vec2 q, float t, float evolve) {
	float te = t * evolve;
	vec2 w = vec2(cl_fbm(q * 0.7 + vec2(0.0, te * 0.012), te * 0.5, 3), cl_fbm(q * 0.7 + vec2(5.2 - te * 0.010, 1.3), te * 0.5, 3));
	float n = cl_fbm(q + (w - 0.5) * 1.1, te, 5);
	// Whole patches grow and fade over several minutes.
	float grow = cl_noise(q * 0.3 + vec2(te * 0.0045, 31.7 - te * 0.003)) - 0.5;
	return n + grow * 0.16;
}

// The high, thin layer: long streaks along the wind, slowly combed and thinned.
float cl_cirrus(vec2 q, float t, float evolve) {
	float te = t * evolve;
	float bend = cl_noise(vec2(q.x * 0.35, te * 0.004)) - 0.5;
	vec2 s = vec2(q.x, q.y + bend * 1.6);
	float n = cl_fbm(s * vec2(1.0, 1.0) + vec2(te * 0.003, 0.0), te * 0.4, 4);
	float comb = cl_noise(vec2(s.x * 6.0 + te * 0.01, s.y * 0.6));
	return n * (0.75 + 0.25 * comb);
}

// The cover where a front has reached: `x01` 0..1 across the scene, more cloud upwind while it builds,
// less upwind while it clears.
float cl_front_cover(float cover, float trend, float dir, float x01, float gain) {
	float upwind = (0.5 - x01) * (dir < 0.0 ? -1.0 : 1.0);
	return clamp(cover + trend * gain * upwind * 2.0, 0.0, 1.0);
}
