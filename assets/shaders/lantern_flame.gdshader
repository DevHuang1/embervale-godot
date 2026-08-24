shader_type spatial;
render_mode blend_add, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// === Lantern Flame ===
// A volumetric-feeling flame sprite: layered value-noise tongues over a
// vertical gradient core, flicker on two clocks, and a `sway_vec` uniform
// fed every frame from EntityAnimator's lantern pendulum so the fire leans
// and trails with the hero's acceleration like real burning oil.

uniform vec3 emissive_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float emissive_intensity : hint_range(0.0, 8.0) = 2.2;
uniform float pulse_speed : hint_range(0.0, 12.0) = 4.2;
// Pendulum-driven lean (x) and swing lag (y), set from _pend_angle.
uniform vec2 sway_vec = vec2(0.0);
uniform vec3 core_color : source_color = vec3(1.0, 0.96, 0.80);

varying vec2 uv_local;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	uv_local = UV - vec2(0.5);
	// Flame leans opposite the pendulum swing; tips travel further than roots
	float height_w = clamp(UV.y, 0.0, 1.0);
	VERTEX.xy += sway_vec * height_w * height_w * 0.35;
	VERTEX.x += sin(TIME * pulse_speed * 1.7 + UV.y * 6.0) * 0.02 * height_w;
}

void fragment() {
	vec2 uv = UV;
	// Rising tongue distortion, stronger toward the tip
	float wobble = vnoise(vec2(uv.x * 3.0, uv.y * 2.2 - TIME * pulse_speed * 0.9))
		- 0.5;
	uv.x += wobble * (1.0 - uv.y) * 0.28;

	// Flame silhouette: narrow at top, round at the base, noise-eaten edges
	vec2 c = uv - vec2(0.5, 0.18);
	c.x *= 1.55;
	float shape = 1.0 - smoothstep(0.08, 0.52,
		length(c * vec2(1.0, 1.0 / max(0.25 + uv.y * 1.15, 0.25))));
	float body = shape * smoothstep(-0.02, 0.14, uv.y) * (1.0 - smoothstep(0.72, 1.0, uv.y));

	float flicker = 0.86 + 0.14 * sin(TIME * pulse_speed * 2.3)
		+ 0.07 * sin(TIME * pulse_speed * 5.1 + 1.7);

	vec3 col = mix(emissive_color, core_color, pow(clamp(body * 1.25, 0.0, 1.0), 1.6));
	ALBEDO = vec3(0.0);
	EMISSION = col * body * flicker * emissive_intensity
		* (1.0 + abs(sway_vec.y) * 2.0);
	ALPHA = clamp(body, 0.0, 1.0);
}
