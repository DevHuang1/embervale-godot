shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Procedural Rock / Stone ===
// Triplanar mottling with moss pooling where the world normal points up.
// Shared by scattered rocks, the pale path stones and the altar stonework.

uniform vec3 rock_color : source_color = vec3(0.27, 0.29, 0.26);
uniform vec3 moss_color : source_color = vec3(0.115, 0.205, 0.105);
uniform float mottle_scale : hint_range(0.2, 32.0) = 3.4;
uniform float mottle_strength : hint_range(0.0, 1.0) = 0.38;
uniform float moss_amount : hint_range(0.0, 1.0) = 0.55;
uniform float moss_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.72;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.95;
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.0;

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
	// Triplanar projection weighted by axis dominance
	vec3 aw = abs(world_normal);
	aw /= max(aw.x + aw.y + aw.z, 0.0001);
	float n_x = value_noise(world_pos.zy * mottle_scale + vec2(5.3));
	float n_y = value_noise(world_pos.xz * mottle_scale + vec2(17.9));
	float n_z = value_noise(world_pos.xy * mottle_scale + vec2(41.7));
	float mottle = n_x * aw.x + n_y * aw.y + n_z * aw.z;
	float mottle2 = value_noise(world_pos.xz * mottle_scale * 2.63 + vec2(77.1));

	vec3 base = rock_color * (0.82 + (mottle - 0.5) * 2.0 * mottle_strength
		+ (mottle2 - 0.5) * 0.14);

	// Moss pools on upward faces where the noise allows it
	float moss_n = value_noise(world_pos.xz * mottle_scale * 0.8 + vec2(3.3));
	float moss_mask = moss_amount
		* smoothstep(moss_threshold, moss_threshold + 0.25, world_normal.y)
		* smoothstep(0.32, 0.62, moss_n);

	ALBEDO = clamp(mix(base, moss_color * (0.85 + 0.35 * mottle), moss_mask),
		vec3(0.0), vec3(1.0));
	ROUGHNESS = mix(mix(roughness_max, roughness_min, mottle), 0.98, moss_mask);
	SPECULAR = mix(0.28, 0.16, moss_mask);
	METALLIC = 0.0;
	AO = 1.0 - mottle2 * 0.10;

	EMISSION = emission_color * emission_energy;
}
