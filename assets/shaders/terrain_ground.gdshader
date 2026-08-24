shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// === Terrain Ground ===
// Triplanar-blended layers so the runtime heightmap ArrayMesh needs no
// UVs: grass base, dirt patches (noise-driven), rocky slopes and stone
// crests, plus pebble speckle detail.

uniform vec3 grass_color : source_color = vec3(0.16, 0.26, 0.11);
uniform vec3 grass_dry : source_color = vec3(0.34, 0.36, 0.14);
uniform vec3 dirt_color : source_color = vec3(0.30, 0.22, 0.13);
uniform vec3 stone_color : source_color = vec3(0.38, 0.38, 0.35);
uniform vec3 crest_color : source_color = vec3(0.45, 0.44, 0.40);

uniform float tile_scale : hint_range(0.02, 2.0) = 0.18;
uniform float slope_start : hint_range(0.0, 1.0) = 0.55;
uniform float slope_end : hint_range(0.0, 1.0) = 0.85;
uniform float patch_scale : hint_range(0.5, 32.0) = 6.0;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.45;
uniform float speckle_strength : hint_range(0.0, 1.0) = 0.35;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
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
	float amp = 0.5;
	for (int l = 0; l < 4; l++) {
		total += vnoise(p) * amp;
		p = p * 2.03 + vec2(19.19, 7.33);
		amp *= 0.5;
	}
	return total;
}

vec3 layer_albedo(vec3 p, vec3 n, float slope, out float rough_out) {
	float macro = fbm(p.xz * 0.015 + vec2(3.1, 8.7));

	// Grass: two-tone mixed by macro noise
	float gmix = fbm(p.xz * tile_scale * 2.2);
	vec3 grass = mix(grass_color, grass_dry, clamp(gmix * 1.4 - 0.2, 0.0, 1.0));
	grass *= 0.85 + 0.3 * fbm(p.xz * tile_scale * 9.0);

	// Dirt patches: blotchy noise mask, stronger in low macro areas
	float patches = smoothstep(1.0 - dirt_amount, 1.05 - dirt_amount * 0.4,
		fbm(p.xz * patch_scale * 0.22 + macro * 2.0));
	vec3 dirt = dirt_color * (0.8 + 0.4 * fbm(p.xz * tile_scale * 5.0));

	// Rock on slopes
	float rock_mask = smoothstep(slope_start, slope_end, slope);
	vec3 rock = stone_color * (0.75 + 0.5 * fbm(p.xz * tile_scale * 1.4 + 40.0));

	// Stone crest by height
	float crest = smoothstep(1.4, 2.6, p.y);
	vec3 col = mix(grass, dirt, patches);
	col = mix(col, rock, rock_mask);
	col = mix(col, crest_color, crest * (1.0 - patches));

	// Pebble speckle: high-frequency cells brightened like scattered stones
	vec2 cell = floor(p.xz * tile_scale * 14.0);
	vec2 fcell = fract(p.xz * tile_scale * 14.0) - 0.5;
	float pebble = step(0.93, hash21(cell)) * (1.0 - smoothstep(0.18, 0.42, length(fcell)));
	col = mix(col, stone_color * 1.25, pebble * speckle_strength * (1.0 - rock_mask));

	rough_out = mix(roughness, roughness * 0.7, max(rock_mask, crest));
	return col;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float rough_out;
	ALBEDO = layer_albedo(world_pos, n, slope, rough_out);
	ROUGHNESS = rough_out;
}
