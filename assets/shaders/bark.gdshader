shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Procedural Bark ===
// Vertical streak noise albedo with roughness variation and a faint
// top-facing rim emission that catches moon shafts. MultiMesh-safe:
// variation comes from world position.

uniform vec3 bark_color : source_color = vec3(0.12, 0.095, 0.075);
uniform float streak_scale : hint_range(1.0, 60.0) = 14.0;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.38;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_max : hint_range(0.0, 1.0) = 1.0;
uniform vec3 moon_rim_color : source_color = vec3(0.55, 0.62, 0.85);
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.22;

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Stretched along trunk height so noise reads as vertical furrows
	vec2 sp = vec2((world_pos.x + world_pos.z) * 0.7071 * streak_scale,
		world_pos.y * streak_scale * 0.16);
	float streak = value_noise(sp);
	float streak2 = value_noise(sp * 2.7 + vec2(9.1, 4.7));
	float grain = streak * 0.65 + streak2 * 0.35;

	ALBEDO = clamp(bark_color * (1.0 + (grain - 0.5) * 2.0 * streak_strength),
		vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(roughness_max, roughness_min, grain);
	SPECULAR = 0.18;
	METALLIC = 0.0;

	float up = clamp(world_normal.y, 0.0, 1.0);
	EMISSION = moon_rim_color * pow(up, 3.0) * rim_intensity;
}
