shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Whispergrove Procedural Terrain ===
// Noise-blended mossy/grassy ground with damp soil patches,
// micro-relief normals and rare warm ember flecks.

uniform float tile_scale : hint_range(1.0, 64.0) = 16.0;
uniform float macro_scale : hint_range(0.05, 8.0) = 0.9;
uniform float detail_scale : hint_range(1.0, 128.0) = 46.0;

uniform vec3 moss_color : source_color = vec3(0.115, 0.205, 0.105);
uniform vec3 grass_color : source_color = vec3(0.26, 0.365, 0.155);
uniform vec3 dry_grass_color : source_color = vec3(0.34, 0.31, 0.16);
uniform vec3 soil_color : source_color = vec3(0.125, 0.11, 0.085);

uniform float grass_coverage : hint_range(0.0, 1.0) = 0.5;
uniform float damp_amount : hint_range(0.0, 1.0) = 0.55;
uniform float dry_patch_amount : hint_range(0.0, 1.0) = 0.35;

uniform float roughness_min : hint_range(0.0, 1.0) = 0.68;
uniform float roughness_max : hint_range(0.0, 1.0) = 0.95;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.65;
uniform float terrain_brightness : hint_range(0.5, 2.0) = 1.15;

uniform vec3 ember_fleck_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float ember_fleck_density : hint_range(0.0, 0.5) = 0.045;
uniform float ember_fleck_intensity : hint_range(0.0, 4.0) = 0.85;

uniform vec3 rock_color : source_color = vec3(0.145, 0.135, 0.125);
uniform float rock_slope_start : hint_range(0.0, 1.0) = 0.30;
uniform float rock_slope_end : hint_range(0.0, 1.0) = 0.62;
uniform float macro_tint_scale : hint_range(0.01, 2.0) = 0.11;
uniform float macro_tint_strength : hint_range(0.0, 1.0) = 0.22;
uniform float detail_warp_amount : hint_range(0.0, 4.0) = 0.9;

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

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	vec2 q = p;
	for (int i = 0; i < 4; i++) {
		total += value_noise(q) * amplitude;
		q = q * 2.03 + vec2(19.19, 7.33);
		amplitude *= 0.5;
	}
	return total;
}

float micro_height(vec2 p) {
	return value_noise(p) * 0.62 + value_noise(p * 2.37 + vec2(53.1, 11.9)) * 0.38;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 wp = world_pos.xz;

	float macro = fbm(wp * macro_scale);
	float patch = fbm(wp * tile_scale * 0.55 + vec2(17.3, 43.7));
	float detail = value_noise(wp * detail_scale);

	float tuft = smoothstep(0.35, 0.75, detail);
	float grass_mask = smoothstep(grass_coverage - 0.22, grass_coverage + 0.22, patch * 0.72 + macro * 0.28);
	grass_mask *= mix(0.55, 1.0, tuft);

	float damp = damp_amount * smoothstep(0.58, 0.28, macro);
	float dry = dry_patch_amount * smoothstep(0.62, 0.82, fbm(wp * macro_scale * 1.7 + vec2(88.2, 5.1)));

	// Slope-driven rock/soil blend: steep ground sheds its moss
	float steep = clamp(1.0 - world_normal.y, 0.0, 1.0);
	float rock_mask = smoothstep(rock_slope_start, rock_slope_end, steep);

	// Domain-warped speckle: a second detail octave breaks up grain repetition
	vec2 warp = vec2(
		value_noise(wp * detail_scale * 0.37 + vec2(7.7, 3.1)),
		value_noise(wp * detail_scale * 0.41 + vec2(91.2, 61.9)));
	float warped_speckle = value_noise(
		wp * detail_scale * 2.13 + vec2(31.4, 61.8) + warp * detail_warp_amount);

	vec3 ground = mix(moss_color, grass_color, grass_mask);
	ground = mix(ground, dry_grass_color, clamp(dry * (0.35 + 0.65 * tuft), 0.0, 1.0));
	ground = mix(ground, soil_color, clamp(damp, 0.0, 1.0));

	// Large-scale triplanar macro tint kills visible tiling repetition
	vec3 aw = abs(world_normal);
	aw /= max(aw.x + aw.y + aw.z, 0.0001);
	float tn_x = value_noise(world_pos.zy * macro_tint_scale + vec2(3.7));
	float tn_y = value_noise(world_pos.xz * macro_tint_scale + vec2(17.9));
	float tn_z = value_noise(world_pos.xy * macro_tint_scale + vec2(51.3));
	float macro_tint = tn_x * aw.x + tn_y * aw.y + tn_z * aw.z;

	ground = mix(ground, rock_color * (0.8 + 0.4 * macro), rock_mask);

	float speckle = (warped_speckle - 0.5) * 0.16;
	ALBEDO = clamp(ground * terrain_brightness * (1.0 + speckle)
		* (1.0 + (macro_tint - 0.5) * 2.0 * macro_tint_strength),
		vec3(0.0), vec3(1.0));

	vec2 bp = wp * tile_scale;
	float e = 0.035;
	float h0 = micro_height(bp);
	float hx = micro_height(bp + vec2(e, 0.0));
	float hy = micro_height(bp + vec2(0.0, e));
	vec3 n_tangent = normalize(vec3((h0 - hx) / e * bump_strength, 1.0, (h0 - hy) / e * bump_strength));
	NORMAL_MAP = n_tangent * 0.5 + 0.5;

	ROUGHNESS = mix(mix(roughness_max, roughness_min,
		clamp(damp * 0.8 + tuft * 0.2, 0.0, 1.0)), 0.88, rock_mask);
	SPECULAR = mix(mix(0.18, 0.42, damp), 0.22, rock_mask);
	METALLIC = 0.0;

	AO = clamp(1.0 - damp * 0.22 - (1.0 - tuft) * 0.06 - rock_mask * 0.08, 0.0, 1.0);

	float fleck_n = value_noise(wp * detail_scale * 3.17 + vec2(91.7, 41.3));
	float threshold = 1.0 - ember_fleck_density;
	float fleck = smoothstep(threshold, threshold + 0.012, fleck_n);
	fleck *= step(0.45, grass_mask) * (1.0 - rock_mask);
	float twinkle = 0.75 + 0.25 * sin(TIME * 2.1 + fleck_n * 47.0);
	EMISSION = ember_fleck_color * fleck * ember_fleck_intensity * twinkle;
}
