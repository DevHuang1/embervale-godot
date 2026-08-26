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

// Leafy relief: bump normals + roughness variation from the tone field.
uniform float leaf_bump : hint_range(0.0, 2.0) = 0.55;

// Shared gust field from WorldState (storms bend the treetops with grass)
global uniform vec2 world_wind;

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
	// Storm gusts push whole canopies downwind (tips furthest)
	VERTEX.xz += world_wind * v_h * 0.6;
}

void fragment() {
	float n = value_noise(world_pos.xz * tone_scale + world_pos.yy * 0.7);
	vec3 albedo = mix(canopy_color, highlight_color,
		smoothstep(0.35, 0.78, n) * tone_strength);
	// Underside shading gives the blobby canopies some volume
	albedo *= mix(0.78, 1.12, clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0));
	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// --- Leafy bump: finite differences of the tone field along the
	// surface tangent frame, so clusters catch light like leaf clumps ---
	float e = 0.22;
	vec3 nn = normalize(world_normal);
	vec3 t = normalize(cross(nn, vec3(0.0, 1.0, 0.001)));
	vec3 b = cross(nn, t);
	float h0 = value_noise((world_pos + nn * 0.0).xz * tone_scale + world_pos.yy * 0.7);
	float ht = value_noise((world_pos + t * e).xz * tone_scale + (world_pos.y + t.y * e) * 0.7);
	float hb = value_noise((world_pos + b * e).xz * tone_scale + (world_pos.y + b.y * e) * 0.7);
	float k = leaf_bump / e;
	vec3 n_bump = normalize(nn - t * (ht - h0) * k - b * (hb - h0) * k);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_bump, 0.0)).xyz);

	// Leaf clusters vary from waxy to matte; sun-facing tops get a faint
	// backscatter lift so canopies read translucent at their rims
	ROUGHNESS = clamp(0.86 + (n - 0.5) * 0.16, 0.0, 1.0);
	SPECULAR = 0.2;
	METALLIC = 0.0;
	AO = mix(0.88, 1.0, smoothstep(0.25, 0.75, n));

	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	EMISSION += highlight_color * pow(1.0 - facing, 2.4) * 0.10;
}
