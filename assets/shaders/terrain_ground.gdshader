shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

// === Terrain Ground v3 (UE-style) ===
// Photo-scanned PBR layers (grass/dirt/sand/rock: albedo + normal +
// roughness) blended UE-Landscape style: macro noise masks pick regions,
// then per-layer texture HEIGHTS sharpen the transitions so layers
// interpenetrate instead of melting. Close range adds parallax occlusion
// mapping against the blended layer heights (tier-gated), per-layer
// normal detail, and rain wetting via world_rain_level. Distance still
// settles everything into calm realm-tinted color masses.
// Realm palettes + persistent wear map keep driving every biome.

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
uniform float roughness : hint_range(0.0, 1.0) = 1.0;

// --- Scanned PBR layers (CC0 sets from assets/textures/pbr/) ---
uniform sampler2D grass_tex : source_color, hint_default_white;
uniform sampler2D dirt_tex : source_color, hint_default_white;
uniform sampler2D sand_tex : source_color, hint_default_white;
uniform sampler2D rock_tex : source_color, hint_default_white;
uniform sampler2D grass_norm : hint_normal;
uniform sampler2D dirt_norm : hint_normal;
uniform sampler2D sand_norm : hint_normal;
uniform sampler2D rock_norm : hint_normal;
uniform sampler2D grass_rough : hint_default_white;
uniform sampler2D dirt_rough : hint_default_white;
uniform sampler2D sand_rough : hint_default_white;
uniform sampler2D rock_rough : hint_default_white;

// World units per texture tile
uniform float uv_world_scale : hint_range(0.02, 1.0) = 0.115;
// How strongly detail textures modulate the tint colors (0 = flat colors)
uniform float tex_blend : hint_range(0.0, 1.0) = 0.82;
// Sandy dry patches on flat open ground
uniform float sand_amount : hint_range(0.0, 1.0) = 0.34;

// --- Height-weighted blending (UE landscape heightlerp feel) ---
// 0 recovers soft noise-only blends; higher values carve sharper edges
// where one layer's surface height rises above the mix.
uniform float height_contrast : hint_range(0.0, 6.0) = 2.4;

// --- Parallax occlusion (tier-gated by QualityScaler -> pom_mode) ---
// 0 = off (analytic bump only), 1 = single-step offset (MEDIUM),
// 2 = 8-step occlusion march near camera (HIGH)
uniform int pom_mode = 0;
uniform float depth_scale : hint_range(0.0, 0.2) = 0.025;
uniform float pom_near : hint_range(4.0, 48.0) = 15.0;

// Debug: 1 = visualize layer weights (r=grass g=dirt b=sand+rock)
uniform int debug_view = 0;

// Close-range micro relief from the blended per-layer normal maps
uniform float normal_strength : hint_range(0.0, 2.0) = 0.95;
// Broad geometric relief from the analytic height field
uniform float bump_strength : hint_range(0.0, 2.0) = 0.42;
uniform float detail_scale : hint_range(0.05, 8.0) = 0.85;

// Realm accent: sparse glowing flecks (ember, fen-light, moonmoss).
uniform vec3 accent_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float accent_strength : hint_range(0.0, 1.0) = 0.0;

// --- Persistent ground wear (TerrainWear splats via WorldState global) ---
global uniform sampler2D world_wear_map;
global uniform vec4 world_wear_bounds;   // xy = min corner (x,z), z = size
global uniform float world_rain_level;   // published by WorldState each frame
uniform float wear_strength : hint_range(0.0, 1.0) = 0.8;

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

float lum(vec3 c) {
	return dot(c, vec3(0.299, 0.587, 0.114));
}

// Dirt keeps its own two-tone so shaded soil stays rich
vec3 dirt_tint_of(vec2 wp) {
	float m = fbm(wp * tile_scale * 5.0);
	return mix(dirt_color * 0.82, dirt_color * 1.14, m);
}

// Layer UV multipliers (sand runs broader dunes, rock tighter plates)
vec2 layer_uv(vec2 uv, int layer) {
	if (layer == 2) { return uv * 0.62; }
	if (layer == 3) { return uv * 1.5; }
	return uv;
}

// Blended layer surface height at a uv point. Weights are fixed per
// fragment (computed once at the entry uv) so the parallax march sees a
// stable field.
float layer_height(vec2 uv, float wg, float wd, float ws, float wrr) {
	float h = wg * lum(textureLod(grass_tex, layer_uv(uv, 0), 0.0).rgb);
	h += wd * lum(textureLod(dirt_tex, layer_uv(uv, 1), 0.0).rgb);
	h += ws * lum(textureLod(sand_tex, layer_uv(uv, 2), 0.0).rgb);
	h += wrr * lum(textureLod(rock_tex, layer_uv(uv, 3), 0.0).rgb);
	return clamp(h, 0.0, 1.0);
}

// Parallax occlusion against the blended layer heights.
// cam_vec: direction from fragment toward the camera (world space).
vec2 pom_offset(vec2 uv, vec3 cam_vec, vec3 nrm, int steps,
		float wg, float wd, float ws, float wrr) {
	// Project onto the ground plane's tangent basis (uv spans world xz)
	vec3 t1 = normalize(vec3(1.0, 0.0, 0.0) - nrm * nrm.x);
	vec3 t2 = cross(nrm, t1);
	vec3 v = normalize(cam_vec);
	float vz = max(dot(v, nrm), 0.15);
	vec2 p = vec2(dot(v, t1), dot(v, t2)) / vz * depth_scale;
	float step_d = 1.0 / float(steps);
	vec2 duv = p * step_d;
	float d = 0.0;
	vec2 cuv = uv;
	float dh = 1.0 - layer_height(cuv, wg, wd, ws, wrr);
	for (int i = 0; i < 8; i++) {
		if (i >= steps || d >= dh) { break; }
		cuv -= duv;
		d += step_d;
		dh = 1.0 - layer_height(cuv, wg, wd, ws, wrr);
	}
	return cuv;
}

float surf_height(vec2 p) {
	float macro = fbm(p * 0.015 + vec2(3.1, 8.7));
	float h = fbm(p * tile_scale * 2.2) * 0.34;
	h += fbm(p * detail_scale) * 0.20;
	h += smoothstep(1.0 - dirt_amount, 1.05 - dirt_amount * 0.4,
		fbm(p * patch_scale * 0.22 + macro * 2.0)) * 0.42;
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	float cam_dist = length(VERTEX);

	// --- Macro masks (region layout, unchanged from v2) ---
	vec2 wp = world_pos.xz;
	float macro = fbm(wp * 0.015 + vec2(3.1, 8.7));
	float gmix = fbm(wp * tile_scale * 2.2);
	vec3 grass_tint = mix(grass_color, grass_dry,
		clamp(gmix * 1.25 - 0.12, 0.0, 1.0));
	float patches = smoothstep(0.92 - dirt_amount, 1.18 - dirt_amount * 0.4,
		fbm(wp * patch_scale * 0.22 + macro * 2.0));
	float dryness = fbm(wp * patch_scale * 0.13 + vec2(51.2, 17.4));
	float flatness = smoothstep(0.28, 0.05, slope);
	float sand_mask = sand_amount * flatness
		* smoothstep(0.38, 0.68, dryness) * (1.0 - patches);
	float rock_mask = smoothstep(slope_start - 0.07, slope_end + 0.05, slope);
	float crest = smoothstep(1.4, 2.6, world_pos.y);
	float wr = max(rock_mask, crest * (1.0 - patches));

	vec2 uv = wp * uv_world_scale;

	// --- Base weights -> height-modulated weights (UE heightlerp) ---
	float wg = 1.0;
	float wd = patches;
	float ws = sand_mask;
	float wrr = wr;
	vec2 uvg = layer_uv(uv, 0);
	vec2 uvd = layer_uv(uv, 1);
	vec2 uvs = layer_uv(uv, 2);
	vec2 uvr = layer_uv(uv, 3);
	vec3 gc = texture(grass_tex, uvg).rgb;
	vec3 dc = texture(dirt_tex, uvd).rgb;
	vec3 sc = texture(sand_tex, uvs).rgb;
	vec3 rc = texture(rock_tex, uvr).rgb;
	float wsum = wg + wd + ws + wrr;
	float hg = lum(gc);
	float hd = lum(dc);
	float hs = lum(sc);
	float hr = lum(rc);
	float havg = (wg * hg + wd * hd + ws * hs + wrr * hr) / max(wsum, 0.001);
	float hc = height_contrast;
	wg *= exp((hg - havg) * hc);
	wd *= exp((hd - havg) * hc);
	ws *= exp((hs - havg) * hc);
	wrr *= exp((hr - havg) * hc);
	wsum = wg + wd + ws + wrr;
	wg /= wsum; wd /= wsum; ws /= wsum; wrr /= wsum;

	// --- Parallax offset uv (tier-gated, close range only) ---
	vec2 puv = uv;
	float pom_fade = smoothstep(pom_near + 6.0, pom_near * 0.45, cam_dist);
	if (pom_mode > 0 && pom_fade > 0.001 && depth_scale > 0.0001) {
		int steps = 1;
		if (pom_mode > 1) { steps = 8; }
		puv = pom_offset(uv, CAMERA_POSITION_WORLD - world_pos, n, steps,
			wg, wd, ws, wrr);
		uvg = layer_uv(puv, 0);
		uvd = layer_uv(puv, 1);
		uvs = layer_uv(puv, 2);
		uvr = layer_uv(puv, 3);
		gc = texture(grass_tex, uvg).rgb;
		dc = texture(dirt_tex, uvd).rgb;
		sc = texture(sand_tex, uvs).rgb;
		rc = texture(rock_tex, uvr).rgb;
	}

	// --- Height-blended albedo under realm tints ---
	vec3 col = wg * (grass_tint * mix(vec3(1.0), gc, tex_blend));
	col += wd * (dirt_tint_of(wp) * mix(vec3(1.0), dc, tex_blend));
	col += ws * (mix(grass_dry, vec3(0.62, 0.55, 0.40), 0.45)
		* mix(vec3(1.0), sc, tex_blend));
	col += wrr * (stone_color * mix(vec3(1.0), rc, tex_blend));

	// Pebble speckle: softened cells so stones read as embedded, not pasted
	vec2 cell = floor(wp * tile_scale * 14.0);
	vec2 fcell = fract(wp * tile_scale * 14.0) - 0.5;
	float pebble = step(0.94, hash21(cell)) * (1.0 - smoothstep(0.16, 0.46, length(fcell)));
	col = mix(col, stone_color * 1.22,
		pebble * speckle_strength * 0.8 * (1.0 - wr));

	ALBEDO = col;

	if (debug_view == 1) {
		ALBEDO = vec3(wg, wd, ws + wrr);
		EMISSION = ALBEDO * 0.35;
	}

	// --- Roughness from per-layer roughness maps ---
	float rg = texture(grass_rough, uvg).r;
	float rd = texture(dirt_rough, uvd).r;
	float rs = texture(sand_rough, uvs).r;
	float rk = texture(rock_rough, uvr).r;
	float r_out = (wg * rg + wd * rd + ws * rs + wrr * rk) * roughness;
	r_out *= mix(1.0, 0.82, wr);

	// --- Relief stack ---
	// 1) Broad geometric swell from the analytic height field
	float e = 0.09;
	float h0 = surf_height(world_pos.xz);
	float hx = surf_height(world_pos.xz + vec2(e, 0.0));
	float hz = surf_height(world_pos.xz + vec2(0.0, e));
	float k = bump_strength / e * clamp(n.y, 0.0, 1.0);
	vec3 n_bump = normalize(vec3(n.x - (hx - h0) * k, max(n.y, 0.08),
		n.z - (hz - h0) * k));

	// 2) Blended per-layer normal maps: fade with distance so far ground
	//    stays smooth
	float close_fade = smoothstep(30.0, 6.0, cam_dist);
	if (normal_strength > 0.001 && close_fade > 0.001) {
		vec3 gn = texture(grass_norm, uvg).rgb;
		vec3 dn = texture(dirt_norm, uvd).rgb;
		vec3 sn = texture(sand_norm, uvs).rgb;
		vec3 rn = texture(rock_norm, uvr).rgb;
		vec3 tn = wg * gn + wd * dn + ws * sn + wrr * rn;
		tn = tn * 2.0 - 1.0;
		float nf = normal_strength * close_fade;
		n_bump = normalize(vec3(n_bump.x + tn.x * nf, n_bump.y,
			n_bump.z + tn.y * nf));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_bump, 0.0)).xyz);

	// Cavity shading + gentle close-range crumb variation
	float cav = smoothstep(0.30, 1.05, h0);
	AO = mix(0.80, 1.0, cav);
	float grain = hash21(floor(world_pos.xz * 110.0));
	ALBEDO *= mix(1.0, 0.95 + grain * 0.09, close_fade);
	ROUGHNESS = clamp(r_out * mix(0.96, 1.03, grain), 0.0, 1.0);

	// --- Rain wetting: darken albedo, gloss the surface ---
	float wet = clamp(world_rain_level, 0.0, 1.0);
	if (wet > 0.003) {
		ALBEDO *= mix(1.0, 0.62, wet * 0.8);
		ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.32), wet * 0.75);
	}

	// Trodden ground: darkened, roughened paths remembered by the wear map
	vec2 wear_uv = (world_pos.xz - world_wear_bounds.xy)
		/ max(world_wear_bounds.z, 1.0);
	if (all(greaterThan(wear_uv, vec2(0.0))) && all(lessThan(wear_uv, vec2(1.0)))) {
		float wear = texture(world_wear_map, wear_uv).r * wear_strength;
		ALBEDO *= mix(1.0, 0.7, wear);
		ROUGHNESS = mix(ROUGHNESS, 1.0, wear * 0.6);
	}

	// Realm accent flecks: sparse emissive speckles keyed to world space
	if (accent_strength > 0.001) {
		float fn = hash21(floor(world_pos.xz * 4.0) + vec2(7.7, 3.3));
		float band = smoothstep(0.94, 0.985, fn) * accent_strength;
		ALBEDO = mix(ALBEDO, accent_color, band * 0.8);
		EMISSION += accent_color * band;
	}
}
