shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// === Entity Body Shader ===
// Used by all enemies and the hero for:
//   - Per-clone albedo variation (variation_seed drives hue shift)
//   - Vivid rim/edge emission (gameplay readability at distance)
//   - Hit flash (flash_intensity 0→1, timed externally)
//   - HP wear darkening (hp_wear 0→1 as entity takes damage)
//   - Elemental status overlay (elemental_color + elemental_intensity)
//   - Combat glow pulse (emissive_color + emission_energy, driven per frame)
//
// Every clone duplicates this material and gets its own variation_seed.
// The shared master lives at res://assets/materials/entity_hushling.tres
// (and entity_hero.tres for the hero).

// === Base surface ===
uniform vec4  base_color       : source_color = vec4(0.30, 0.25, 0.38, 1.0);
uniform vec4  rim_color        : source_color = vec4(0.42, 0.72, 0.50, 1.0);
uniform float roughness        : hint_range(0.0, 1.0) = 0.68;
uniform float metallic         : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D albedo_tex   : hint_default_white, repeat_enable;
uniform sampler2D normal_tex   : hint_normal, repeat_enable;
uniform sampler2D orm_tex      : hint_default_white, repeat_enable;  // R=AO G=Rough B=Metal

// === Per-clone variation ===
uniform float variation_seed   : hint_range(0.0, 1.0) = 0.0;
uniform float variation_strength : hint_range(0.0, 0.35) = 0.12;

// === Rim emission (gameplay read) ===
uniform vec4  emission_color   : source_color = vec4(0.42, 0.72, 0.50, 1.0);
uniform float emission_energy  : hint_range(0.0, 8.0) = 0.55;
uniform float rim_power        : hint_range(0.5, 8.0) = 2.8;
uniform float rim_strength     : hint_range(0.0, 3.0) = 1.2;

// === Hit flash ===
uniform float flash_intensity  : hint_range(0.0, 1.0) = 0.0;
uniform vec4  flash_color      : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// === HP wear ===
uniform float hp_wear          : hint_range(0.0, 1.0) = 0.0;  // 0=full HP, 1=near death
uniform vec4  wear_tint        : source_color = vec4(0.08, 0.04, 0.03, 1.0);

// === Elemental status overlay ===
uniform vec4  elemental_color  : source_color = vec4(0.0, 0.5, 1.0, 0.0);
uniform float elemental_intensity : hint_range(0.0, 4.0) = 0.0;

// === Combat emissive (driven by game code) ===
uniform vec4  emissive_color   : source_color = vec4(0.0, 0.0, 0.0, 0.0);
uniform float emissive_energy  : hint_range(0.0, 12.0) = 0.0;

// === Dissolve (soft fade-out, not threshold dissolve) ===
uniform float dissolve_alpha   : hint_range(0.0, 1.0) = 1.0;

// ─── helpers ─────────────────────────────────────────────────────────────────

// Cheap hue rotation in RGB (no vec3→HSV, avoids extra sampler)
vec3 hue_shift(vec3 col, float shift) {
	// Rotate around the grey axis using a small-angle approximation
	float s = sin(shift * 6.2832);
	float c = cos(shift * 6.2832);
	mat3 rot = mat3(
		vec3(0.299 + 0.701*c - 0.168*s, 0.587 - 0.587*c - 0.330*s, 0.114 - 0.114*c + 0.497*s),
		vec3(0.299 - 0.299*c + 0.328*s, 0.587 + 0.413*c + 0.035*s, 0.114 - 0.114*c - 0.364*s),
		vec3(0.299 - 0.300*c - 0.900*s, 0.587 - 0.588*c + 1.050*s, 0.114 + 0.886*c - 0.203*s)
	);
	return clamp(rot * col, 0.0, 1.0);
}

void vertex() {
	// No vertex displacement
}

void fragment() {
	// Base albedo + texture
	vec3 orm   = texture(orm_tex, UV).rgb;
	vec4 tex   = texture(albedo_tex, UV);
	vec3 col   = base_color.rgb * tex.rgb;

	// Per-clone hue variation — keeps swarm readable without extra draw calls
	col = hue_shift(col, (variation_seed - 0.5) * variation_strength);

	// HP wear: darkens toward wear_tint as damage accumulates
	col = mix(col, wear_tint.rgb, hp_wear * 0.72);

	// Normal map
	NORMAL_MAP = texture(normal_tex, UV).rgb;

	// Surface properties blended with ORM
	ALBEDO    = col;
	ROUGHNESS = roughness * (0.85 + orm.g * 0.15);
	METALLIC  = metallic  * orm.b;
	AO        = orm.r;

	// Rim emission — bright at glancing angles, dark face-on
	float rim  = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	vec3 emit  = emission_color.rgb * emission_energy;
	emit      += rim_color.rgb * rim * rim_strength;

	// Elemental status glow (fire, ice, nature, etc.)
	emit += elemental_color.rgb * elemental_intensity;

	// Game-code driven combat emissive (boss phase transitions, skill casts)
	emit += emissive_color.rgb * emissive_energy;

	// Hit flash: lerp toward white
	ALBEDO   = mix(ALBEDO, flash_color.rgb, flash_intensity);
	emit      = mix(emit, vec3(1.0), flash_intensity * 0.8);

	EMISSION  = emit;
	ALPHA     = dissolve_alpha;
}
