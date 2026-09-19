shader_type spatial;
// Low-cost Android terrain path. It keeps the ground textured and opaque on
// older mobile GPUs while avoiding the desktop shader's POM, triplanar,
// multi-octave normal/roughness, and global wear sampler work.
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley;

uniform sampler2D grass_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D dirt_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D sand_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D rock_tex : source_color, hint_default_white, repeat_enable;

uniform vec3 grass_color : source_color = vec3(0.30, 0.48, 0.20);
uniform vec3 grass_dry : source_color = vec3(0.48, 0.46, 0.20);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.22, 0.13);
uniform vec3 sand_color : source_color = vec3(0.68, 0.54, 0.30);
uniform vec3 stone_color : source_color = vec3(0.38, 0.38, 0.35);
uniform vec3 realm_tint : source_color = vec3(1.0);
uniform float realm_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.45;
uniform float sand_amount : hint_range(0.0, 1.0) = 0.30;
uniform float uv_world_scale : hint_range(0.02, 3.0) = 0.15;
uniform float tex_gain : hint_range(0.5, 2.5) = 1.25;
uniform float terrain_brightness : hint_range(0.5, 2.0) = 1.1;

// Surface regions (Minecraft-style material zones) and shoreline beaches.
// These are scalar/vector uniforms only: the four-albedo sampler budget on
// low-end Android GPUs must stay intact.
uniform float region_scale : hint_range(0.001, 0.05) = 0.0075;
uniform float region_edge : hint_range(0.02, 0.4) = 0.13;
uniform float river_enabled = 0.0;
uniform float river_base_x = 0.0;
uniform float river_meander = 0.0;
uniform float river_wavelen = 120.0;
uniform float river_phase = 0.0;
uniform float river_detail = 0.25;
uniform float river_half_width = 6.6;
uniform float river_beach : hint_range(0.0, 12.0) = 2.6;
uniform vec4 pond_a = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 pond_b = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 pond_c = vec4(0.0, 0.0, 0.0, 0.0);

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float pond_beach(vec4 pond, vec2 wp) {
	if (pond.w < 0.5) {
		return 0.0;
	}
	float d = length(wp - pond.xy) / max(pond.z, 0.001);
	return 1.0 - smoothstep(0.82, 1.5, d);
}

float river_center_x(float z) {
	float wavelen = max(river_wavelen, 1.0);
	float primary = sin(z / wavelen * TAU + river_phase);
	float secondary = sin(z / (wavelen * 0.37) * TAU + river_phase * 1.7);
	return river_base_x + river_meander * primary
		+ river_meander * river_detail * secondary;
}

float shoreline_sand(vec2 wp) {
	float beach = 0.0;
	if (river_enabled > 0.5) {
		float d = abs(wp.x - river_center_x(wp.y));
		beach = 1.0 - smoothstep(river_half_width + 0.2,
			river_half_width + river_beach, d);
	}
	beach = max(beach, pond_beach(pond_a, wp));
	beach = max(beach, pond_beach(pond_b, wp));
	beach = max(beach, pond_beach(pond_c, wp));
	return beach;
}

vec3 textured_color(sampler2D layer, vec2 uv, vec3 tint) {
	vec3 sample_color = texture(layer, uv).rgb * tex_gain;
	return mix(tint, sample_color, 0.78);
}

// Sand and dirt carry the realm's material identity (a realm must not read as
// one green wash), so they keep more of their palette tint than the detailed
// desktop path's texture share would give them on a cheaper sampler layout.
vec3 tinted_layer(sampler2D layer, vec2 uv, vec3 tint, float texture_share) {
	vec3 sample_color = texture(layer, uv).rgb * tex_gain;
	return mix(tint, sample_color, texture_share);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float slope = 1.0 - clamp(normal.y, 0.0, 1.0);
	vec2 wp = world_pos.xz;
	vec2 uv = wp * uv_world_scale;
	float broad_noise = value_noise(wp * 0.045 + vec2(7.0, 19.0));
	float dry_noise = value_noise(wp * 0.075 + vec2(31.0, 11.0));
	// Coherent material zones: the two-octave sand field carves whole sandy
	// areas with a feathered edge instead of sub-metre speckle.
	float edge = max(region_edge, 0.02);
	float sand_field = value_noise(wp * region_scale + vec2(11.0, 37.0)) * 0.68
		+ value_noise(wp * region_scale * 2.3 + vec2(5.0, 61.0)) * 0.32;
	float dirt_field = value_noise(wp * region_scale * 0.83 + vec2(83.0, 20.0));
	float sand_cut = 0.68 - sand_amount * 0.5;
	float dirt_cut = 0.80 - dirt_amount * 0.42;
	float sand_region = smoothstep(sand_cut, sand_cut + edge, sand_field);
	float dirt_region = smoothstep(dirt_cut, dirt_cut + edge, dirt_field);
	float beach = shoreline_sand(wp);
	float sand_mask = clamp(max(sand_region, beach), 0.0, 1.0);
	float dirt_mask = max(dirt_region, smoothstep(0.48, 0.78, broad_noise) * dirt_amount);
	float rock_mask = smoothstep(0.42, 0.82, slope);
	vec3 grass = textured_color(grass_tex, uv,
		mix(grass_color, grass_dry, dry_noise * 0.6));
	vec3 dirt = tinted_layer(dirt_tex, uv * 1.05, dirt_color, 0.66);
	vec3 sand = tinted_layer(sand_tex, uv * 0.9, sand_color, 0.58);
	vec3 rock = textured_color(rock_tex, uv * 0.85, stone_color);
	vec3 color = mix(grass, dirt,
		dirt_mask * (1.0 - sand_mask * 0.85) * (1.0 - rock_mask));
	color = mix(color, sand, sand_mask * (1.0 - rock_mask) * 0.95);
	color = mix(color, rock, rock_mask);
	color *= mix(vec3(1.0), realm_tint, realm_tint_strength);
	ALBEDO = clamp(color * terrain_brightness, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.22;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
}
