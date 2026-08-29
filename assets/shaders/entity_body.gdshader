shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// === Embervale Entity Body v3 ===
// Full PBR lighting response (moonlight, lanterns, warm pools), fresnel rim
// lighting with width control, animated emissive glow gated by a mask,
// optional texture inputs (albedo / normal / ORM / detail normal), a cheap
// subsurface wrap for fungal pods, and a ScanManager-driven dirt scanline.
//
// STRICT SUPERSET: every new uniform defaults to "off", so pre-existing
// materials (.tres) and script-driven parameters render exactly as before.

uniform vec3 base_color : source_color = vec3(0.16, 0.24, 0.18);
uniform float roughness : hint_range(0.0, 1.0) = 0.62;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform float specular : hint_range(0.0, 1.0) = 0.35;

// --- Texture inputs (all optional; mixes default to 0) ---
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float albedo_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D normal_texture : hint_normal;
uniform float normal_mix : hint_range(0.0, 1.0) = 0.0;
// glTF-style ORM packing: R = ambient occlusion, G = roughness, B = metallic
uniform sampler2D orm_texture : hint_default_white;
uniform float orm_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D roughness_texture : hint_default_white;
uniform float roughness_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D detail_normal : hint_normal;
uniform float detail_normal_strength : hint_range(0.0, 1.5) = 0.0;
uniform vec2 detail_normal_scale = vec2(7.0, 7.0);

// --- Emission (mask gates the glow so painted pods/hearts light up only) ---
uniform vec3 emission_color : source_color = vec3(0.0, 0.0, 0.0);
uniform float emission_energy : hint_range(0.0, 4.0) = 0.0;
uniform float glow_intensity : hint_range(0.0, 4.0) = 1.0;
uniform float emission_mask_mix : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D emission_mask : hint_default_white;

// --- Rim ---
uniform vec3 rim_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float rim_power : hint_range(0.5, 8.0) = 2.6;
uniform float rim_intensity : hint_range(0.0, 4.0) = 1.1;
uniform float rim_ambient_floor : hint_range(0.0, 1.0) = 0.12;
// Extra width shaping: 0 keeps the classic falloff, 1 widens the halo.
uniform float rim_width : hint_range(0.0, 1.0) = 0.0;

// --- Cheap subsurface approximation (fungal pods, thin cloth) ---
// Wrap-lighting style translucency: glows toward the silhouette where real
// SSS lets light bleed through thin forms.
uniform float sss_strength : hint_range(0.0, 2.0) = 0.0;
uniform vec3 sss_tint : source_color = vec3(0.45, 0.75, 0.55);

// --- Hit flash ---
uniform vec3 flash_color : source_color = vec3(1.0, 0.84, 0.47);
uniform float flash_intensity : hint_range(0.0, 1.0) = 0.0;

// --- Divining Lens reveal: grime + teal scanline that sweeps and fades ---
// Driven per-entity by EntityAnimator from ScanManager.reveal_stamp_msec.
uniform float scan_reveal : hint_range(0.0, 1.0) = 0.0;

uniform float sway_amount : hint_range(0.0, 0.05) = 0.004;
uniform float sway_speed : hint_range(0.0, 6.0) = 1.6;

// Cloth micro-detail (defaults off; tuned per-material so shared looks hold)
uniform float cloth_noise_amount : hint_range(0.0, 0.3) = 0.0;
uniform float cloth_noise_scale : hint_range(1.0, 64.0) = 18.0;
uniform vec3 trim_color : source_color = vec3(0.23, 0.16, 0.10);
uniform float trim_height : hint_range(-2.0, 2.0) = -0.35;
uniform float trim_softness : hint_range(0.01, 1.0) = 0.2;
uniform float trim_blend : hint_range(0.0, 1.0) = 0.0;
uniform float joint_ao_strength : hint_range(0.0, 1.0) = 0.0;
uniform float joint_ao_low : hint_range(-2.0, 2.0) = -0.3;
uniform float joint_ao_high : hint_range(-2.0, 2.0) = -0.08;

// --- WorldState reactivity (strict superset: defaults keep prior looks) ---
// Ambient magic lifts mask-gated emission at night (fireflies brighten with it).
global uniform float world_magic_level;
global uniform float world_rain_level;
uniform float magic_glow_lift : hint_range(0.0, 1.0) = 0.25;
// Battle wear: darkens and roughens the body as HP drops (0 = pristine).
uniform float hp_wear : hint_range(0.0, 1.0) = 0.0;

// === v3 drop-in superset ===
// Per-clone surface variation, wet-weather reactivity (same downpour as the
// terrain), micro roughness breakup, breathing weak-point emission, and a
// secondary albedo layer for hybrid surfaces (bark+stone, clay+crust). All
// default OFF so every existing .tres renders identically until bound.
uniform float albedo_variation : hint_range(0.0, 0.5) = 0.0;
uniform float variation_seed : hint_range(0.0, 1.0) = 0.35;
uniform float micro_roughness : hint_range(0.0, 0.4) = 0.0;
uniform float rain_response : hint_range(0.0, 1.0) = 0.0;
uniform float emission_pulse_speed : hint_range(0.0, 8.0) = 0.0;
uniform sampler2D detail_tex : source_color, hint_default_white;
uniform float detail_mix : hint_range(0.0, 1.0) = 0.0;
uniform float detail_scale : hint_range(0.5, 16.0) = 4.0;

varying vec3 world_pos_v;
varying float local_y_v;

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
	local_y_v = VERTEX.y;
	world_pos_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.x += sin(TIME * sway_speed + VERTEX.y * 4.0) * sway_amount;
	VERTEX.z += cos(TIME * sway_speed * 0.8 + VERTEX.x * 3.0) * sway_amount * 0.6;
}

void fragment() {
	ALBEDO = mix(base_color, flash_color, flash_intensity * 0.55);

	// Albedo detail texture multiplies through so flat palettes keep working
	vec3 alb_tex = texture(albedo_texture, UV).rgb;
	ALBEDO *= mix(vec3(1.0), alb_tex * 2.0, albedo_mix);

	// Cloth micro-noise: subtle world-space weave
	float cloth_n = value_noise(
		world_pos_v.xz * cloth_noise_scale + vec2(world_pos_v.y * cloth_noise_scale * 0.5));
	ALBEDO *= 1.0 + (cloth_n - 0.5) * 2.0 * cloth_noise_amount;

	// Two-tone banding: trim color below the object-local height band
	float band = smoothstep(trim_height - trim_softness, trim_height + trim_softness, local_y_v);
	ALBEDO = mix(ALBEDO, trim_color, trim_blend * (1.0 - band));
	// v3 per-clone variation + secondary albedo layer (bark/stone hybrids)
	if (albedo_variation > 0.001) {
		float v3seed = hash21(vec2(floor(fract(variation_seed + world_pos_v.y * 0.017) * 4096.0), 7.0));
		float v3sway = (v3seed - 0.5) * 2.0 * albedo_variation;
		ALBEDO *= (1.0 + v3sway) * mix(vec3(1.0), vec3(1.04, 1.0, 0.93), v3sway * 0.5);
	}
	if (detail_mix > 0.001) {
		vec3 dex = texture(detail_tex, UV * detail_scale).rgb;
		float dband = value_noise(world_pos_v.xz * 1.6 + vec2(world_pos_v.y * 0.9));
		ALBEDO = mix(ALBEDO, ALBEDO * (dex * 2.0), detail_mix * (0.45 + 0.55 * dband));
	}

	// ORM: R=AO, G=roughness, B=metallic
	vec3 orm = texture(orm_texture, UV).rgb;
	ROUGHNESS = mix(roughness, orm.g, orm_mix);
	ROUGHNESS = mix(ROUGHNESS, texture(roughness_texture, UV).r, roughness_mix);
	METALLIC = mix(metallic, orm.b, orm_mix);
	SPECULAR = specular;
	// v3 micro roughness: world-space grain keeps large surrogate skins from
	// reading as smooth plastic under a strong key light.
	if (micro_roughness > 0.001) {
		float mrg = value_noise(world_pos_v.xz * 10.0 + vec2(world_pos_v.y * 5.0));
		ROUGHNESS = clamp(ROUGHNESS + (mrg - 0.5) * 2.0 * micro_roughness, 0.02, 1.0);
	}

	// Normal blend: sampled tangent normal + tiled detail micro-surface
	float n_active = clamp(normal_mix + detail_normal_strength, 0.0, 1.0);
	if (n_active > 0.001) {
		vec3 n1 = texture(normal_texture, UV).xyz * 2.0 - 1.0;
		vec3 n2 = texture(detail_normal, UV * detail_normal_scale).xyz * 2.0 - 1.0;
		vec3 blended = normalize(vec3(
			n1.xy * normal_mix + n2.xy * detail_normal_strength,
			mix(1.0, n1.z, max(normal_mix, detail_normal_strength))));
		NORMAL_MAP = blended * 0.5 + 0.5;
	}

	float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), VIEW), 0.0, 1.0),
		mix(rim_power, rim_power * 0.38, rim_width));
	float rim = fresnel + rim_ambient_floor;

	float em_mask = mix(1.0, texture(emission_mask, UV).r, emission_mask_mix);
	// Ambient magic breathes extra life into masked glow (night groves pulse).
	float magic_lift = 1.0 + world_magic_level * magic_glow_lift * 0.35 * em_mask;
	float em_pulse = mix(1.0, 1.0 + 0.16 * sin(TIME * emission_pulse_speed + variation_seed * 6.2831), step(0.001, emission_pulse_speed));
	EMISSION = emission_color * emission_energy * glow_intensity * em_mask * magic_lift * em_pulse
		+ rim_color * rim * rim_intensity
		+ flash_color * flash_intensity * 1.6;

	// Subsurface wrap: silhouettes of thin forms glow with the tint
	float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
	float transmission = pow(1.0 - facing, 2.0);
	EMISSION += sss_tint * sss_strength * transmission
		* (0.35 + 0.65 * glow_intensity);

	// Dirt scanline: a rising teal sweep that drags grime across the form,
	// strongest the instant the lens reveals the object, then fading out.
	if (scan_reveal > 0.001) {
		float line = smoothstep(0.06, 0.0,
			abs(fract(world_pos_v.y * 0.22 - TIME * 1.4) - 0.5));
		float grime = value_noise(world_pos_v.xz * 9.0 + world_pos_v.y * 4.0);
		ALBEDO = mix(ALBEDO, ALBEDO * vec3(0.72, 0.82, 0.78)
			* (0.55 + 0.45 * grime), scan_reveal * 0.85);
		EMISSION += vec3(0.28, 0.95, 0.80) * line * scan_reveal * 1.8;
	}

	// Joint/AO approximation: darken near capsule bottoms
	float joint_shade = joint_ao_strength * (1.0 - smoothstep(joint_ao_low, joint_ao_high, local_y_v));
	AO = clamp(1.0 - joint_shade, 0.0, 1.0);

	// Battle wear: scuffed albedo and dulled roughness as the body breaks down
	if (hp_wear > 0.001) {
		ALBEDO *= mix(1.0, 0.62 + 0.1 * value_noise(world_pos_v.xz * 14.0), hp_wear);
		ROUGHNESS = mix(ROUGHNESS, 0.95, hp_wear * 0.7);
	}

	// v3 wet weather: shared world_rain_level darkens + glosses the skin so
	// bodies answer the same downpour as the terrain (default off per body).
	if (rain_response > 0.001) {
		float wet = clamp(world_rain_level, 0.0, 1.0);
		if (wet > 0.003) {
			ALBEDO *= mix(1.0, 0.72, wet * rain_response * 0.8);
			ROUGHNESS = mix(ROUGHNESS, min(ROUGHNESS, 0.34), wet * rain_response * 0.85);
		}
	}
}
