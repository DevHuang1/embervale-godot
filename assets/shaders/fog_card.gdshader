shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never, shadows_disabled;

// === Fog Card ===
// Soft horizontal mist sheets for the atmospheric fog banks. Slow FBM drift,
// sky-palette tint, and distance fade so banks dissolve before popping.
// Tint is meant to track the realm palette (Bramblewood gold -> Mistfen blue).

uniform vec3 fog_tint : source_color = vec3(0.62, 0.70, 0.68);
uniform float fog_alpha : hint_range(0.0, 0.6) = 0.14;
uniform float drift_speed : hint_range(0.0, 1.0) = 0.06;
uniform float noise_scale : hint_range(0.5, 12.0) = 2.6;
uniform float fade_near : hint_range(0.0, 10.0) = 3.0;
uniform float fade_far : hint_range(10.0, 120.0) = 46.0;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float n = 0.0;
	n += value_noise(p) * 0.55;
	n += value_noise(p * 2.1 + 4.7) * 0.28;
	n += value_noise(p * 4.3 + 9.1) * 0.17;
	return n;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz * noise_scale + vec2(
		TIME * drift_speed, TIME * drift_speed * 0.6);
	float d = fbm(p);
	// Soft circular card edge so stacked sheets never show seams
	vec2 local = UV - vec2(0.5);
	float edge = smoothstep(0.5, 0.18, length(local));
	float cam_dist = length(world_pos - CAMERA_POSITION_WORLD);
	float dist_fade = smoothstep(fade_far, fade_far * 0.55, cam_dist)
		* smoothstep(fade_near * 0.4, fade_near, cam_dist);
	float a = fog_alpha * d * edge * dist_fade;
	ALBEDO = fog_tint * (0.7 + 0.5 * d);
	EMISSION = fog_tint * 0.04;
	ALPHA = clamp(a, 0.0, 1.0);
}
