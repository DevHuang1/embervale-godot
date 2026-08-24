shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Procedural Canopy ===
// Noise-broken two-tone foliage with gentle wind sway. Phase comes from
// MODEL_MATRIX origin so MultiMesh batches stay safe; sway grows toward
// the canopy top so the underside stays calm.

uniform vec3 canopy_color : source_color = vec3(0.075, 0.15, 0.10);
uniform vec3 highlight_color : source_color = vec3(0.16, 0.30, 0.17);
uniform float tone_scale : hint_range(0.2, 16.0) = 1.6;
uniform float tone_strength : hint_range(0.0, 1.0) = 0.45;
uniform float canopy_height : hint_range(0.2, 6.0) = 2.2;
uniform float wind_strength : hint_range(0.0, 0.6) = 0.12;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.2;

varying vec3 world_pos;
varying vec3 world_normal;
varying float v_h;

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
	v_h = clamp((VERTEX.y + canopy_height * 0.5) / canopy_height, 0.0, 1.0);
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Same phase-from-MODEL_MATRIX trick as grass_blade.gdshader
	float phase = TIME * wind_speed
		+ (MODEL_MATRIX[3][0] + MODEL_MATRIX[3][2]) * 0.31;
	float gust = 0.75 + 0.25 * sin(TIME * 0.37 + MODEL_MATRIX[3][2] * 0.13);
	float bend = sin(phase) * wind_strength * gust * v_h;
	VERTEX.x += bend;
	VERTEX.z += cos(phase * 0.83) * wind_strength * 0.55 * gust * v_h;
}

void fragment() {
	float n = value_noise(world_pos.xz * tone_scale + world_pos.yy * 0.7);
	vec3 albedo = mix(canopy_color, highlight_color,
		smoothstep(0.35, 0.78, n) * tone_strength);
	// Underside shading gives the blobby canopies some volume
	albedo *= mix(0.78, 1.12, clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.14;
	METALLIC = 0.0;
}
