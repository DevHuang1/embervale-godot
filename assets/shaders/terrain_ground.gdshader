shader_type spatial;
// Opaque/depth-writing in every view. Disabled culling is a controlled
// fallback for steep first-person crest views; alpha is never used.
render_mode blend_mix, depth_draw_opaque, cull_disabled, specular_schlick_ggx;

// === Terrain Ground v4 (UE-style, higher-quality pass) ===
// Additions over v3:
//   * Stochastic hex-tile sampling for grass/dirt (kills obvious tiling
//     repetition at range). Tier-gated by QualityScaler → stochastic_mode.
//   * Triplanar rock projection for steep slopes — cliffs no longer smear
//     the top-down rock texture. Cost is rock_mask weighted so flat
//     ground stays cheap.
//   * Macro colour variation (low-frequency multiplier) breaks the mass
//     tint across biome-sized regions without extra samples.
//   * Puddle accumulation: in low-lying areas (analytic height field)
//     rain wets more aggressively — darker albedo, near-mirror roughness,
//     slight blue tint — so water actually pools where it should.
//   * Cavity AO from the blended layer heights.
//   * Per-layer specular tuning (rock is glossier, grass is matte).
//   * Secondary micro-normal octave at very close range.

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
uniform vec3 realm_tint : source_color = vec3(1.0);
uniform float realm_tint_strength : hint_range(0.0, 1.0) = 0.0;
uniform float moisture_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 moss_color : source_color = vec3(0.22, 0.42, 0.24);
uniform float moss_strength : hint_range(0.0, 1.0) = 0.0;

// --- Scanned PBR layers (CC0 sets from assets/textures/pbr/) ---
uniform sampler2D grass_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D dirt_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D sand_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D rock_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D moss_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D mud_tex : source_color, hint_default_white, repeat_enable;
uniform sampler2D grass_norm : hint_normal, repeat_enable;
uniform sampler2D dirt_norm : hint_normal, repeat_enable;
uniform sampler2D sand_norm : hint_normal, repeat_enable;
uniform sampler2D rock_norm : hint_normal, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, repeat_enable;
uniform sampler2D dirt_rough : hint_default_white, repeat_enable;
uniform sampler2D sand_rough : hint_default_white, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, repeat_enable;

// World units per texture tile
uniform float uv_world_scale : hint_range(0.02, 3.0) = 0.9;
// How strongly detail textures modulate the tint colors (0 = flat colors)
uniform float tex_blend : hint_range(0.0, 1.0) = 0.95;
uniform float tex_gain : hint_range(0.5, 2.5) = 1.0;
uniform float tex_saturation : hint_range(0.0, 1.5) = 1.0;
// Sandy dry patches on flat open ground
uniform float sand_amount : hint_range(0.0, 1.0) = 0.34;
uniform vec3 sand_color : source_color = vec3(0.70, 0.58, 0.36);

// --- Surface regions (Minecraft-style material zones) ---
// Low-frequency fields carve whole sand / dirt areas with feathered borders
// so the ground reads as distinct terrain types instead of one grass wash.
uniform float region_scale : hint_range(0.001, 0.05) = 0.0075;
uniform float region_edge : hint_range(0.02, 0.4) = 0.13;

// --- Shoreline beaches (river + pond waterlines) ---
// Twins of WorldWaterways' centerline so the sand band hugs the carved
// channel. Bound per realm by TerrainRelief; disabled by default.
uniform float river_enabled = 0.0;
uniform float river_base_x = 0.0;
uniform float river_meander = 0.0;
uniform float river_wavelen = 120.0;
uniform float river_phase = 0.0;
uniform float river_detail = 0.25;
// Water-plane half width bound from WorldWaterways; sand is complete across
// the water and fades to grass over `river_beach` metres beyond it.
uniform float river_half_width = 6.6;
uniform float river_beach : hint_range(0.0, 12.0) = 2.6;
// xy = pond center, z = basin radius, w = enabled
uniform vec4 pond_a = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 pond_b = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 pond_c = vec4(0.0, 0.0, 0.0, 0.0);

// --- Height-weighted blending (UE landscape heightlerp feel) ---
uniform float height_contrast : hint_range(0.0, 6.0) = 2.4;

// --- Parallax occlusion (tier-gated by QualityScaler -> pom_mode) ---
// 0 = off (analytic bump only), 1 = single-step offset (MEDIUM),
// 2 = 8-step occlusion march near camera (HIGH)
uniform int pom_mode = 0;
uniform float depth_scale : hint_range(0.0, 0.2) = 0.025;
uniform float pom_near : hint_range(4.0, 48.0) = 15.0;

// --- Stochastic hex-tile sampling (v4) ---
// 0 = plain tiled sampling (LOW/MEDIUM), 1 = 3-tap hex-cell blend on
// grass/dirt to erase obvious repetition (HIGH). Fades out beyond
// stochastic_far so we only pay for it near camera.
uniform int stochastic_mode = 0;
uniform float stochastic_far : hint_range(6.0, 80.0) = 34.0;

// Debug: 1 = visualize layer weights (r=grass g=dirt b=sand+rock)
uniform int debug_view = 0;

// Close-range micro relief from the blended per-layer normal maps
uniform float normal_strength : hint_range(0.0, 3.0) = 1.4;
// Broad geometric relief from the analytic height field
uniform float bump_strength : hint_range(0.0, 2.0) = 0.42;
uniform float detail_scale : hint_range(0.05, 8.0) = 0.85;
// Secondary micro-normal octave (v4)
uniform float micro_normal_strength : hint_range(0.0, 1.5) = 0.55;
uniform float micro_normal_scale : hint_range(1.0, 8.0) = 3.7;

// Realm accent: sparse glowing flecks (ember, fen-light, moonmoss).
uniform vec3 accent_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float accent_strength : hint_range(0.0, 1.0) = 0.0;

// Visual richness: brightness boost + domain-warped speckle + ember flecks
uniform float terrain_brightness : hint_range(0.5, 2.0) = 1.28;
uniform float detail_warp_amount : hint_range(0.0, 4.0) = 0.9;
// Disabled by default: hard grid flecks read as square cards on mobile.
uniform float ember_fleck_density : hint_range(0.0, 0.5) = 0.0;
uniform float ember_fleck_intensity : hint_range(0.0, 4.0) = 0.0;

// Macro colour variation (v4): low-frequency albedo modulation
uniform float macro_variation_strength : hint_range(0.0, 0.6) = 0.18;
uniform float macro_variation_scale : hint_range(0.001, 0.05) = 0.008;
uniform float macro_breakup_strength : hint_range(0.0, 1.0) = 0.42;
uniform float micro_grain_strength : hint_range(0.0, 1.0) = 0.24;
uniform float puddle_sheen_strength : hint_range(0.0, 1.0) = 0.18;

// Puddle accumulation (v4) — activated by world_rain_level
uniform float puddle_threshold : hint_range(0.0, 1.0) = 0.32;
uniform float puddle_strength : hint_range(0.0, 1.0) = 0.85;

// --- Persistent ground wear (TerrainWear splats via WorldState global) ---
global uniform sampler2D world_wear_map;
global uniform vec4 world_wear_bounds;
global uniform float world_rain_level;
uniform float wear_strength : hint_range(0.0, 1.0) = 0.8;

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
	p = fract(p * vec2(127.13, 311.71));
	p += dot(p, p + 34.43);
	return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
	float n = hash21(p);
	return vec2(n, fract(n * 3.71 + 0.137));
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

float lum(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

vec3 grade_texture(vec3 c) {
	float l = lum(c);
	vec3 saturated = mix(vec3(l), c, tex_saturation);
	// Gain is centered around mid-grey, preserving dark cracks instead of
	// lifting the complete texture toward a single bright realm tint.
	return clamp((saturated - vec3(0.5)) * tex_gain + vec3(0.5), vec3(0.0), vec3(1.0));
}

mat2 rot2(float a) {
	float c = cos(a); float s = sin(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

// Stochastic 3-tap sampling: sample the texture at three rotated /
// offset positions keyed to hex-cell hashes and blend by barycentric
// weights. Variance-preserving normalisation keeps overall brightness
// stable. Approach adapted from Heitz & Neyret (2018), simplified for
// mobile. Fades to plain sampling beyond `blend_fade` (0..1).
vec3 stochastic_sample(sampler2D tex, vec2 uv, float blend_fade) {
	if (blend_fade < 0.02) { return texture(tex, uv).rgb; }
	// Hex-lattice cell lookup via skewed grid
	vec2 skew = vec2(uv.x + uv.y * 0.5, uv.y);
	vec2 cell = floor(skew);
	vec2 f = fract(skew);
	// Three vertices of the hex cell we're inside
	vec2 v0, v1, v2;
	if (f.x + f.y < 1.0) {
		v0 = cell;
		v1 = cell + vec2(1.0, 0.0);
		v2 = cell + vec2(0.0, 1.0);
	} else {
		v0 = cell + vec2(1.0, 1.0);
		v1 = cell + vec2(1.0, 0.0);
		v2 = cell + vec2(0.0, 1.0);
	}
	// Barycentric weights
	vec3 w;
	if (f.x + f.y < 1.0) {
		w = vec3(1.0 - f.x - f.y, f.x, f.y);
	} else {
		w = vec3(f.x + f.y - 1.0, 1.0 - f.y, 1.0 - f.x);
	}
	// Per-cell random rotation + offset
	vec2 o0 = hash22(v0);
	vec2 o1 = hash22(v1);
	vec2 o2 = hash22(v2);
	float a0 = o0.x * 6.2831853;
	float a1 = o1.x * 6.2831853;
	float a2 = o2.x * 6.2831853;
	vec2 uv0 = rot2(a0) * uv + o0 * 4.0;
	vec2 uv1 = rot2(a1) * uv + o1 * 4.0;
	vec2 uv2 = rot2(a2) * uv + o2 * 4.0;
	vec3 s0 = texture(tex, uv0).rgb;
	vec3 s1 = texture(tex, uv1).rgb;
	vec3 s2 = texture(tex, uv2).rgb;
	vec3 mean = (s0 + s1 + s2) / 3.0;
	// Variance-preserve: weighted deviation around mean
	vec3 stoch = mean + (s0 - mean) * w.x + (s1 - mean) * w.y + (s2 - mean) * w.z;
	vec3 plain = texture(tex, uv).rgb;
	return mix(plain, stoch, blend_fade);
}

// Triplanar sample (albedo-only, XZ plane already provided as `top`).
// Blends in world-Y-facing "side" samples for steep slopes.
vec3 triplanar_side(sampler2D tex, vec3 wp, vec3 n) {
	vec2 uv_x = wp.zy * uv_world_scale * 1.5;
	vec2 uv_z = wp.xy * uv_world_scale * 1.5;
	vec3 sx = texture(tex, uv_x).rgb;
	vec3 sz = texture(tex, uv_z).rgb;
	vec3 an = abs(n);
	float wx = an.x; float wz = an.z;
	float wsum = max(wx + wz, 0.001);
	return (sx * wx + sz * wz) / wsum;
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

float layer_height(vec2 uv, float wg, float wd, float ws, float wrr) {
	float h = wg * lum(textureLod(grass_tex, layer_uv(uv, 0), 0.0).rgb);
	h += wd * lum(textureLod(dirt_tex, layer_uv(uv, 1), 0.0).rgb);
	h += ws * lum(textureLod(sand_tex, layer_uv(uv, 2), 0.0).rgb);
	h += wrr * lum(textureLod(rock_tex, layer_uv(uv, 3), 0.0).rgb);
	return clamp(h, 0.0, 1.0);
}

vec2 pom_offset(vec2 uv, vec3 cam_vec, vec3 nrm, int steps,
		float wg, float wd, float ws, float wrr) {
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
	// High is intentionally a short four-sample near-camera march for mobile.
	for (int i = 0; i < 4; i++) {
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

// Pond beach ring: 1 inside the basin, fading across the bank into grass.
float pond_beach(vec4 pond, vec2 wp) {
	if (pond.w < 0.5) {
		return 0.0;
	}
	float d = length(wp - pond.xy) / max(pond.z, 0.001);
	return 1.0 - smoothstep(0.82, 1.5, d);
}

// River centerline twin of WorldWaterways.center_x, so the beach band hugs
// the exact carved channel without an extra sampler or vertex attribute.
float river_center_x(float z) {
	float wavelen = max(river_wavelen, 1.0);
	float primary = sin(z / wavelen * TAU + river_phase);
	float secondary = sin(z / (wavelen * 0.37) * TAU + river_phase * 1.7);
	return river_base_x + river_meander * primary
		+ river_meander * river_detail * secondary;
}

// Complete sand at every waterline, fading up the bank toward grass.
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

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float slope = 1.0 - clamp(n.y, 0.0, 1.0);
	// Terrain is one large mesh, so local vertex distance measures from its
	// centre and incorrectly removes detail away from world origin. Measure
	// from the active camera so close texture relief follows the player.
	float cam_dist = distance(CAMERA_POSITION_WORLD, world_pos);

	// --- Macro masks (region layout) ---
	vec2 wp = world_pos.xz;
	float macro = fbm(wp * 0.015 + vec2(3.1, 8.7));
	float gmix = fbm(wp * tile_scale * 2.2);
	vec3 grass_tint = mix(grass_color, grass_dry,
		clamp(gmix * 1.25 - 0.12, 0.0, 1.0));
	float patches = smoothstep(0.92 - dirt_amount, 1.18 - dirt_amount * 0.4,
		fbm(wp * patch_scale * 0.22 + macro * 2.0));
	float dryness = fbm(wp * patch_scale * 0.13 + vec2(51.2, 17.4));
	float flatness = smoothstep(0.28, 0.05, slope);
	// --- Surface regions (Minecraft-style material zones) ---
	// Low-frequency fields carve whole sand / dirt areas with feathered
	// borders, so the ground reads as distinct terrain types instead of a
	// uniform grass wash speckled with sub-metre noise.
	float edge = max(region_edge, 0.02);
	float sand_field = fbm(wp * region_scale + vec2(11.3, 37.9));
	float dirt_field = fbm(wp * region_scale * 0.83 + vec2(83.1, 19.7));
	float sand_cut = 0.70 - sand_amount * 0.55;
	float dirt_cut = 0.78 - dirt_amount * 0.42;
	float sand_region = smoothstep(sand_cut, sand_cut + edge, sand_field);
	float dirt_region = smoothstep(dirt_cut, dirt_cut + edge, dirt_field);
	// Shoreline beach: complete sand at the river and pond waterlines.
	float beach = shoreline_sand(wp);
	// Make secondary surfaces readable at gameplay distance. The old narrow
	// threshold produced tiny sand islands that disappeared under lighting.
	// Region cores own the zone; the fine patch noise only adds edge breakup.
	float sand_patch = sand_amount * flatness * 1.65
		* smoothstep(0.28, 0.58, dryness) * (1.0 - dirt_region * 0.72) * 0.45;
	float sand_mask = clamp(max(max(sand_region, sand_patch), beach), 0.0, 1.0);
	float dirt_mask = clamp(max(dirt_region, patches * 0.22), 0.0, 1.0);
	float rock_mask = smoothstep(slope_start - 0.07, slope_end + 0.05, slope);
	float crest = smoothstep(1.4, 2.6, world_pos.y);
	float wr = max(rock_mask, crest * (1.0 - patches));

	vec2 uv = wp * uv_world_scale;

	// --- Base weights -> height-modulated weights (UE heightlerp) ---
	// Partition the base layers before height blending. Keeping grass fixed at
	// 1.0 made every other surface a weak tint laid over a nearly solid field.
	float wg = max(0.02, (1.0 - dirt_mask) * (1.0 - sand_mask) * (1.0 - wr));
	float wd = dirt_mask * (1.0 - sand_mask * 0.85) * (1.0 - wr) * 1.75;
	float ws = sand_mask * (1.0 - wr) * 1.6;
	float wrr = wr * 1.45;
	vec2 uvg = layer_uv(uv, 0);
	vec2 uvd = layer_uv(uv, 1);
	vec2 uvs = layer_uv(uv, 2);
	vec2 uvr = layer_uv(uv, 3);

	// Stochastic fade (0..1): only apply near camera and on grass/dirt
	// layers where tiling is most obvious. Gated by tier.
	float stoch_fade = 0.0;
	if (stochastic_mode > 0) {
		stoch_fade = smoothstep(stochastic_far, stochastic_far * 0.4, cam_dist);
	}

	vec3 gc = stochastic_sample(grass_tex, uvg, stoch_fade);
	vec3 dc = stochastic_sample(dirt_tex, uvd, stoch_fade);
	vec3 sc = texture(sand_tex, uvs).rgb;
	vec3 rc = texture(rock_tex, uvr).rgb;
	vec3 mc = texture(moss_tex, uv * 0.82).rgb;
	vec3 mudc = texture(mud_tex, uv * 0.72).rgb;
	gc = grade_texture(gc);
	dc = grade_texture(dc);
	sc = grade_texture(sc);
	rc = grade_texture(rc);
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
		if (pom_mode > 1) { steps = 4; }
		puv = pom_offset(uv, CAMERA_POSITION_WORLD - world_pos, n, steps,
			wg, wd, ws, wrr);
		uvg = layer_uv(puv, 0);
		uvd = layer_uv(puv, 1);
		uvs = layer_uv(puv, 2);
		uvr = layer_uv(puv, 3);
		gc = stochastic_sample(grass_tex, uvg, stoch_fade);
		dc = stochastic_sample(dirt_tex, uvd, stoch_fade);
		sc = texture(sand_tex, uvs).rgb;
		rc = texture(rock_tex, uvr).rgb;
		mc = texture(moss_tex, puv * 0.82).rgb;
		mudc = texture(mud_tex, puv * 0.72).rgb;
		gc = grade_texture(gc);
		dc = grade_texture(dc);
		sc = grade_texture(sc);
		rc = grade_texture(rc);
	}

	// Triplanar side-projection for rock on steep slopes (only meaningful
	// where rock weight AND slope contribute together).
	float triplanar_strength = smoothstep(0.35, 0.85, slope) * wrr;
	if (triplanar_strength > 0.01) {
		vec3 rc_side = triplanar_side(rock_tex, world_pos, n);
		rc = mix(rc, rc_side, triplanar_strength);
	}

	// --- Height-blended albedo under realm tints ---
	// Preserve the authored texture's painted shapes. Multiplying dark source
	// albedo by a dark realm tint crushed its internal contrast into one color.
	// Keep imported PBR albedo detail visually authoritative. The previous
	// extra 0.78 multiplier compounded with realm tinting and made valid maps
	// read as a single color at normal camera distance.
	float authored_mix = clamp(tex_blend, 0.0, 1.0);
	vec3 col = wg * mix(grass_tint, gc, authored_mix);
	col += wd * mix(dirt_tint_of(wp), dc, authored_mix);
	// Mud accent rides inside the dirt zone instead of speckling the whole map.
	col = mix(col, grade_texture(mudc) * dirt_color * 2.0,
		clamp(patches * dirt_mask * 0.30, 0.0, 0.42));
	col += ws * mix(sand_color, sc, authored_mix);
	col += wrr * mix(mix(stone_color, crest_color, crest), rc, authored_mix);

	// Pebble speckle
	vec2 cell = floor(wp * tile_scale * 14.0);
	vec2 fcell = fract(wp * tile_scale * 14.0) - 0.5;
	float pebble = step(0.94, hash21(cell)) * (1.0 - smoothstep(0.16, 0.46, length(fcell)));
	col = mix(col, stone_color * 1.22,
		pebble * speckle_strength * 0.8 * (1.0 - wr) * (1.0 - sand_mask * 0.6));

	// Macro colour variation (v4): sweep tint across biome-scale regions
	float macro_var = fbm(wp * macro_variation_scale + vec2(17.3, 41.9));
	float macro_boost = (macro_var - 0.5) * 2.0 * macro_variation_strength;
	col *= (1.0 + macro_boost);
	// Broad overlapping mineral/soil veins prevent the ground reading as a
	// single flat wash while retaining soft, natural transitions.
	float vein_a = fbm(wp * 0.041 + vec2(73.1, 14.8));
	float vein_b = fbm(rot2(0.73) * wp * 0.067 + vec2(9.2, 48.6));
	float soil_vein = smoothstep(0.48, 0.76, vein_a * 0.62 + vein_b * 0.38);
	vec3 vein_tint = mix(grass_tint * 0.88, dirt_color * 1.06,
		clamp(patches + sand_mask * 0.35, 0.0, 1.0));
	col = mix(col, col * 0.78 + vein_tint * 0.22,
		soil_vein * macro_breakup_strength * (1.0 - wr) * 0.36
			* (1.0 - sand_mask * 0.85));
	// Exposed earth islands provide a readable large-scale material change;
	// their feathered noise edge avoids painted circles or hard tile borders.
	float earth_field = fbm(wp * 0.052 + vec2(26.4, 83.1));
	earth_field = earth_field * 0.68 + vein_b * 0.32;
	float exposed_earth = smoothstep(0.54, 0.69, earth_field)
		* dirt_amount * flatness * (1.0 - wr) * (1.0 - sand_mask * 0.9);
	vec3 earth_col = mix(dirt_tint_of(wp), dc, authored_mix);
	col = mix(col, earth_col, exposed_earth * 0.72);

	float realm_field = fbm(wp * 0.024 + vec2(31.7, 11.4));
	float moisture_field = fbm(wp * 0.080 + vec2(8.3, 19.1));
	float moisture_mask = smoothstep(0.34, 0.70, moisture_field);
	vec3 tint_mix = mix(vec3(1.0), realm_tint, realm_tint_strength);
	col *= tint_mix;
	// A luminance-only contrast lift keeps grass, soil, and sand grain readable
	// under fog/ambient without shifting hue. The former per-channel curve
	// crushed dark grass to black and turned sand orange/red.
	float col_lum = lum(col);
	float contrast_lift = mix(0.88, 1.18, smoothstep(0.10, 0.72, col_lum));
	col *= mix(1.0, contrast_lift, clamp(tex_blend, 0.0, 1.0));
	float moss_mask = moss_strength * mix(0.48, 1.0, moisture_strength)
		* moisture_mask * (1.0 - wr) * flatness
		* (1.0 - sand_mask) * (1.0 - dirt_mask * 0.35);
	// Preserve some grass texture inside the moss rather than replacing it with
	// a flat green swatch; this gives moss visible organic breakup on mobile.
	vec3 moss_surface = mix(moss_color, grade_texture(mc) * moss_color * 1.65, 0.58)
		* (0.82 + realm_field * 0.24);
	col = mix(col, moss_surface, clamp(moss_mask * 1.15, 0.0, 0.82));
	float wet_response = moisture_strength * moisture_mask * (1.0 - wr) * 0.18;
	col = mix(col, col * 0.90 + moss_color * 0.04, clamp(wet_response, 0.0, 1.0));
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
	r_out *= mix(1.0, 0.78, clamp(moisture_strength * moisture_mask, 0.0, 1.0));
	// Authored moss and mud surfaces carry a distinct wet response instead of
	// relying on color alone; keep the effect bounded for mobile readability.
	r_out = mix(r_out, 0.58, clamp(moss_mask * 0.30, 0.0, 0.30));
	r_out = mix(r_out, 0.46, clamp(patches * 0.24, 0.0, 0.24));

	// Per-layer specular tuning (v4): rock a touch glossier, grass matte
	SPECULAR = mix(0.42, 0.62, wrr) - wg * 0.06;

	// --- Relief stack ---
	float e = 0.09;
	float h0 = surf_height(world_pos.xz);
	float hx = surf_height(world_pos.xz + vec2(e, 0.0));
	float hz = surf_height(world_pos.xz + vec2(0.0, e));
	float k = bump_strength / e * clamp(n.y, 0.0, 1.0);
	vec3 n_bump = normalize(vec3(n.x - (hx - h0) * k, max(n.y, 0.08),
		n.z - (hz - h0) * k));

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

		// Secondary micro-normal octave for crumb detail
		float micro_fade = smoothstep(14.0, 2.5, cam_dist);
		if (micro_normal_strength > 0.001 && micro_fade > 0.001) {
			vec2 muv = uvg * micro_normal_scale;
			vec3 mn = texture(grass_norm, muv).rgb * 2.0 - 1.0;
			float mf = micro_normal_strength * micro_fade;
			n_bump = normalize(vec3(n_bump.x + mn.x * mf, n_bump.y,
				n_bump.z + mn.y * mf));
		}
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n_bump, 0.0)).xyz);

	// Cavity AO: analytic height + layer-height blend darkening seams
	float cav = smoothstep(0.30, 1.05, h0);
	float layer_cav = 1.0 - clamp(havg, 0.0, 1.0);
	AO = mix(0.80, 1.0, cav) * (1.0 - layer_cav * 0.18);

	float grain = hash21(floor(world_pos.xz * 110.0));
	float grain_contrast = (grain - 0.5) * micro_grain_strength;
	ALBEDO *= 1.0 + grain_contrast * close_fade;
	ROUGHNESS = clamp(r_out * mix(0.96, 1.03, grain), 0.0, 1.0);
	// Persistent dampness gives wet realms patchy material response even when
	// it is not actively raining; it changes roughness, not gameplay geometry.
	float damp_sheen = moisture_strength * moisture_mask * flatness
		* (1.0 - wr) * puddle_sheen_strength;
	ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.46), damp_sheen);
	SPECULAR = mix(SPECULAR, 0.68, damp_sheen);

	// --- Rain wetting + puddle accumulation (v4) ---
	float wet = clamp(world_rain_level, 0.0, 1.0);
	if (wet > 0.003) {
		ALBEDO *= mix(1.0, 0.62, wet * 0.8);
		ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.32), wet * 0.75);
		// Water pools in low areas of the analytic height field
		float low_area = 1.0 - smoothstep(puddle_threshold,
			puddle_threshold + 0.18, h0);
		float puddle = low_area * flatness * (1.0 - wr) * wet * puddle_strength;
		if (puddle > 0.001) {
			ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.42, 0.48, 0.56), puddle);
			ROUGHNESS = mix(ROUGHNESS, 0.04, puddle);
			SPECULAR = mix(SPECULAR, 0.85, puddle);
			NORMAL = mix(NORMAL, normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz),
				puddle * 0.85);
		}
	}

	// Trodden ground: darkened, roughened paths remembered by the wear map
	vec2 wear_uv = (world_pos.xz - world_wear_bounds.xy)
		/ max(world_wear_bounds.z, 1.0);
	if (all(greaterThan(wear_uv, vec2(0.0))) && all(lessThan(wear_uv, vec2(1.0)))) {
		float wear = texture(world_wear_map, wear_uv).r * wear_strength;
		ALBEDO *= mix(1.0, 0.7, wear);
		ROUGHNESS = mix(ROUGHNESS, 1.0, wear * 0.6);
	}

	// Domain-warped speckle
	float speckle_ds = 46.0;
	vec2 warp = vec2(
		vnoise(wp * speckle_ds * 0.37 + vec2(7.7, 3.1)),
		vnoise(wp * speckle_ds * 0.41 + vec2(91.2, 61.9)));
	float warped_speckle = vnoise(
		wp * speckle_ds * 2.13 + vec2(31.4, 61.8) + warp * detail_warp_amount);
	float speckle = (warped_speckle - 0.5) * 0.16;

	ALBEDO = clamp(ALBEDO * terrain_brightness * (1.0 + speckle),
		vec3(0.0), vec3(1.0));

	// Realm accent flecks
	if (accent_strength > 0.001) {
		float fn = hash21(floor(world_pos.xz * 4.0) + vec2(7.7, 3.3));
		float band = smoothstep(0.94, 0.985, fn) * accent_strength;
		ALBEDO = mix(ALBEDO, accent_color, band * 0.8);
		EMISSION += accent_color * band;
	}

	// Ember flecks: twinkling warm sparks scattered across grassy ground
	float fleck_ds = 46.0;
	float fleck_n = vnoise(wp * fleck_ds * 3.17 + vec2(91.7, 41.3));
	float fleck_threshold = 1.0 - ember_fleck_density;
	float fleck = smoothstep(fleck_threshold, fleck_threshold + 0.012, fleck_n);
	fleck *= step(0.35, flatness) * (1.0 - rock_mask);
	float twinkle = 0.75 + 0.25 * sin(TIME * 2.1 + fleck_n * 47.0);
	EMISSION += accent_color * fleck * ember_fleck_intensity * twinkle;
}
