shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Procedural Bark v2 ===
// Scanned pine-bark PBR set sampled in trunk streak space (albedo +
// roughness), layered over vertical streak noise with derivative-bumped
// furrow relief driven by BOTH fields, groove shading, and a faint
// top-facing rim emission that catches moon shafts. MultiMesh-safe:
// variation comes from world pos.

uniform vec3 bark_color : source_color = vec3(0.12, 0.095, 0.075);
uniform float streak_scale : hint_range(1.0, 60.0) = 14.0;
uniform float streak_strength : hint_range(0.0, 1.0) = 0.38;
uniform float roughness_min : hint_range(0.0, 1.0) = 0.8;
uniform float roughness_max : hint_range(0.0, 1.0) = 1.0;
uniform vec3 moon_rim_color : source_color = vec3(0.55, 0.62, 0.85);
uniform float rim_intensity : hint_range(0.0, 2.0) = 0.22;

// Surface relief: furrow bump strength for the streak field.
uniform float bump_strength : hint_range(0.0, 2.0) = 0.75;

// --- Scanned bark set (CC0, assets/textures/pbr/bark) ---
uniform sampler2D bark_albedo_tex : source_color, hint_default_white;
uniform sampler2D bark_normal_tex : hint_default_white;   // lum as micro height
uniform sampler2D bark_rough_tex : hint_default_white;
// World units per texture tile (circumferential span)
uniform float tex_world_scale : hint_range(0.05, 4.0) = 0.6;
// How strongly the scan drives albedo / roughness / micro relief
uniform float scan_albedo_mix : hint_range(0.0, 1.0) = 0.68;
uniform float scan_rough_mix : hint_range(0.0, 1.0) = 0.55;
uniform float scan_bump_strength : hint_range(0.0, 2.0) = 0.8;

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

// Streak-space coordinates (circumference, height) shared by albedo + bump
vec2 streak_coords(vec3 wp) {
	return vec2((wp.x + wp.z) * 0.7071 * streak_scale,
		wp.y * streak_scale * 0.16);
}

// Scan texture uv: one tile per tex_world_scale around the trunk; the
// vertical axis compresses so plates stretch like real bark.
vec2 scan_uv(vec3 wp) {
	float ts = max(tex_world_scale, 0.001);
	return vec2((wp.x + wp.z) * 0.7071 / ts, wp.y / (ts * 2.2));
}

float grain_at(vec2 sp) {
	float streak = value_noise(sp);
	float streak2 = value_noise(sp * 2.7 + vec2(9.1, 4.7));
	return streak * 0.65 + streak2 * 0.35;
}

void fragment() {
	vec2 sp = streak_coords(world_pos);
	float grain = grain_at(sp);
	vec2 suv = scan_uv(world_pos);

	vec3 scan_col = texture(bark_albedo_tex, suv).rgb;
	ALBEDO = clamp(bark_color * (1.0 + (grain - 0.5) * 2.0 * streak_strength)
		* mix(vec3(1.0), scan_col, scan_albedo_mix),
		vec3(0.0), vec3(1.0));

	// --- Bump normals: finite differences in streak space from the streak
	// field plus the scan's micro heights, projected onto the tangent frame
	// (circumferential + vertical along the trunk) ---
	float e = 0.35;
	float micro0 = lum(texture(bark_normal_tex, suv).rgb);
	float gx = grain_at(sp + vec2(e, 0.0)) - grain;
	float gy = grain_at(sp + vec2(0.0, e)) - grain;
	if (scan_bump_strength > 0.001) {
		gx += (lum(texture(bark_normal_tex, suv + vec2(e * 0.02, 0.0)).rgb) - micro0)
			* scan_bump_strength * 2.4;
		gy += (lum(texture(bark_normal_tex, suv + vec2(0.0, e * 0.02)).rgb) - micro0)
			* scan_bump_strength * 2.4;
	}
	vec3 n = normalize(world_normal);
	vec3 t_circ = normalize(cross(vec3(0.0, 1.0, 0.0), n + vec3(0.001)));
	vec3 t_up = normalize(cross(t_circ, n));
	float k = bump_strength * 1.6 / e;
	vec3 n_bump = normalize(n - t_circ * gx * k - t_up * gy * k);
	NORMAL = normalize((VIEW_MATRIX * vec4(n_bump, 0.0)).xyz);

	// Furrow bottoms read deeper: shade + roughen where grain dips
	float furrow = smoothstep(0.42, 0.12, grain);
	ALBEDO *= mix(1.06, 0.68, furrow);

	float r_base = mix(roughness_max, roughness_min, grain) + furrow * 0.08;
	r_base *= mix(1.0, lum(texture(bark_rough_tex, suv).rgb) * 1.15,
		scan_rough_mix);
	ROUGHNESS = clamp(r_base, 0.0, 1.0);
	SPECULAR = 0.18;
	METALLIC = 0.0;

	float up = clamp(world_normal.y, 0.0, 1.0);
	EMISSION = moon_rim_color * pow(up, 3.0) * rim_intensity;
}
