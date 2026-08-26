shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Procedural Rock / Stone v2 ===
// Scanned PBR rock set (albedo + roughness) projected triplanarly under
// the realm tint, with noise mottling, moss pooling where the world
// normal points up, derivative-bumped relief from BOTH the mottle field
// and the scan's micro heights, crevice shading, and rare mineral glints
// in the specular. Shared by scattered rocks, the pale path stones and
// the altar stonework.

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

// Surface relief: bump normals + cavity occlusion from the mottle field.
uniform float bump_strength : hint_range(0.0, 2.0) = 0.85;

// --- Scanned PBR rock set (CC0, assets/textures/pbr/rock) ---
uniform sampler2D rock_albedo_tex : source_color, hint_default_white;
uniform sampler2D rock_normal_tex : hint_default_white;   // lum as micro height
uniform sampler2D rock_rough_tex : hint_default_white;
// World units per texture tile
uniform float tex_world_scale : hint_range(0.05, 4.0) = 0.45;
// How strongly the scan drives albedo / roughness / micro relief
uniform float scan_albedo_mix : hint_range(0.0, 1.0) = 0.72;
uniform float scan_rough_mix : hint_range(0.0, 1.0) = 0.6;
uniform float scan_bump_strength : hint_range(0.0, 2.0) = 0.9;

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

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

// Triplanar mottle field (the same one that shades the albedo)
float mottle_field(vec3 wp, float s) {
	vec3 aw = abs(wp);
	aw /= max(aw.x + aw.y + aw.z, 0.0001);
	float n_x = value_noise(wp.zy * s + vec2(5.3));
	float n_y = value_noise(wp.xz * s + vec2(17.9));
	float n_z = value_noise(wp.xy * s + vec2(41.7));
	return n_x * aw.x + n_y * aw.y + n_z * aw.z;
}

// Triplanar sample weighted by axis dominance
vec3 triplanar_rgb(sampler2D tex, vec3 wp, float s, vec3 aw) {
	return texture(tex, wp.zy * s).rgb * aw.x
		+ texture(tex, wp.xz * s).rgb * aw.y
		+ texture(tex, wp.xy * s).rgb * aw.z;
}

void fragment() {
	vec3 n = normalize(world_normal);

	// Triplanar projection weighted by axis dominance
	vec3 aw = abs(world_normal);
	aw /= max(aw.x + aw.y + aw.z, 0.0001);
	float s = mottle_scale;
	float ts = tex_world_scale > 0.001 ? 1.0 / tex_world_scale : 0.0;
	float mottle = value_noise(world_pos.zy * s + vec2(5.3)) * aw.x
		+ value_noise(world_pos.xz * s + vec2(17.9)) * aw.y
		+ value_noise(world_pos.xy * s + vec2(41.7)) * aw.z;
	float mottle2 = value_noise(world_pos.xz * s * 2.63 + vec2(77.1));

	// Scanned surface detail, projected triplanarly
	vec3 scan_col = triplanar_rgb(rock_albedo_tex, world_pos, ts, aw);

	vec3 base = rock_color * (0.82 + (mottle - 0.5) * 2.0 * mottle_strength
		+ (mottle2 - 0.5) * 0.14);
	base *= mix(vec3(1.0), scan_col, scan_albedo_mix);

	// Moss pools on upward faces where the noise allows it
	float moss_n = value_noise(world_pos.xz * s * 0.8 + vec2(3.3));
	float moss_mask = moss_amount
		* smoothstep(moss_threshold, moss_threshold + 0.25, world_normal.y)
		* smoothstep(0.32, 0.62, moss_n);

	ALBEDO = clamp(mix(base, moss_color * (0.85 + 0.35 * mottle), moss_mask),
		vec3(0.0), vec3(1.0));

	// --- Bump normals: finite differences of the mottle field plus the
	// scan's micro heights along a tangent frame off the surface normal ---
	float e = max(0.35 / s, 0.02);
	float h0 = mottle_field(world_pos, s);
	vec3 t = normalize(cross(n, vec3(0.0, 1.0, 0.001)));
	vec3 b = cross(n, t);
	float ht = mottle_field(world_pos + t * e, s);
	float hb = mottle_field(world_pos + b * e, s);
	if (scan_bump_strength > 0.001 && ts > 0.0) {
		h0 += lum(triplanar_rgb(rock_normal_tex, world_pos, ts, aw))
			* scan_bump_strength;
		ht += lum(triplanar_rgb(rock_normal_tex, world_pos + t * e, ts, aw))
			* scan_bump_strength;
		hb += lum(triplanar_rgb(rock_normal_tex, world_pos + b * e, ts, aw))
			* scan_bump_strength;
	}
	float k = bump_strength * 2.2 / e;
	vec3 n_bump = normalize(n - t * (ht - h0) * k - b * (hb - h0) * k);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_bump, 0.0)).xyz);

	// Crevices (low second-octave mottle) collect shade and roughness
	float crevice = smoothstep(0.55, 0.15, mottle2);
	AO = (1.0 - crevice * 0.30) * mix(1.0, 0.88, moss_mask);

	float scan_r = lum(triplanar_rgb(rock_rough_tex, world_pos, ts, aw));
	float r_base = mix(mix(roughness_max, roughness_min, mottle),
		0.98, moss_mask) + crevice * 0.06;
	r_base *= mix(1.0, scan_r * 1.15, scan_rough_mix);
	ROUGHNESS = clamp(r_base, 0.0, 1.0);

	// Mineral glints: rare bright facets catch the light in the specular
	float facet = hash21(floor(world_pos.zy * 31.0) + floor(world_pos.x * 23.0));
	float glint = step(0.986, facet) * (1.0 - moss_mask) * (1.0 - crevice);
	SPECULAR = mix(mix(0.28, 0.16, moss_mask), 0.95, glint);
	ROUGHNESS = mix(ROUGHNESS, 0.22, glint);
	METALLIC = 0.0;

	EMISSION = emission_color * emission_energy;
}
