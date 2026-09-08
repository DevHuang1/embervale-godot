shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley;

uniform sampler2D grass_tex : source_color, repeat_enable;
uniform sampler2D dirt_tex : source_color, repeat_enable;
uniform sampler2D sand_tex : source_color, repeat_enable;
uniform sampler2D rock_tex : source_color, repeat_enable;
uniform sampler2D moss_tex : source_color, repeat_enable;
uniform sampler2D mud_tex : source_color, repeat_enable;
uniform sampler2D moss_norm : hint_normal, repeat_enable;
uniform sampler2D mud_norm : hint_normal, repeat_enable;
uniform sampler2D moss_rough : hint_default_white, repeat_enable;
uniform sampler2D mud_rough : hint_default_white, repeat_enable;
// Kept as declared samplers so the terrain material contract remains
// compatible with the normal/roughness layer bindings and future relief pass.
uniform sampler2D grass_norm : hint_normal, repeat_enable;
uniform sampler2D dirt_norm : hint_normal, repeat_enable;
uniform sampler2D sand_norm : hint_normal, repeat_enable;
uniform sampler2D rock_norm : hint_normal, repeat_enable;
uniform sampler2D grass_rough : hint_default_white, repeat_enable;
uniform sampler2D dirt_rough : hint_default_white, repeat_enable;
uniform sampler2D sand_rough : hint_default_white, repeat_enable;
uniform sampler2D rock_rough : hint_default_white, repeat_enable;
uniform vec3 grass_color : source_color = vec3(0.3, 0.48, 0.2);
uniform vec3 dirt_color : source_color = vec3(0.3, 0.22, 0.13);
uniform vec3 sand_color : source_color = vec3(0.7, 0.58, 0.36);
uniform vec3 rock_color : source_color = vec3(0.38, 0.38, 0.35);
uniform vec3 moss_color : source_color = vec3(0.24, 0.58, 0.28);
uniform vec3 mud_color : source_color = vec3(0.28, 0.19, 0.12);
uniform vec3 realm_tint : source_color = vec3(1.0);
uniform float realm_tint_strength : hint_range(0.0, 1.0) = 0.12;
uniform float dirt_amount : hint_range(0.0, 1.0) = 0.55;
uniform float sand_amount : hint_range(0.0, 1.0) = 0.22;
uniform float moss_strength : hint_range(0.0, 1.0) = 0.45;
uniform float moisture_strength : hint_range(0.0, 1.0) = 0.3;
uniform float uv_world_scale : hint_range(0.02, 3.0) = 0.34;
uniform float tex_gain : hint_range(0.5, 2.5) = 1.25;
uniform float terrain_brightness : hint_range(0.5, 2.0) = 1.18;

varying vec3 world_pos;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	return fract(p.x * p.y * 1.0);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 grade(vec3 color) {
	return clamp((color - vec3(0.5)) * tex_gain + vec3(0.5), vec3(0.0), vec3(1.0));
}

vec3 tint_layer(vec3 sampled, vec3 tint, float lift) {
	// Preserve authored albedo contrast. Multiplying dark source pixels by a
	// dark realm tint made every layer converge toward near-black/flat green.
	vec3 detailed = grade(sampled);
	float luminance = dot(detailed, vec3(0.299, 0.587, 0.114));
	float visible_relief = smoothstep(0.035, 0.62, luminance);
	// Keep the authored texture as the dominant signal. Realm tint is applied
	// later as a restrained grade, so fog cannot erase the material identity.
	vec3 colored_detail = mix(tint * 0.72, detailed * 2.35 + tint * 0.18, 0.76);
	return colored_detail * mix(0.82, 1.30, visible_relief) * lift;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = world_pos.xz * uv_world_scale;
	float region = noise(world_pos.xz * 0.032);
	float detail = noise(world_pos.xz * 0.12 + vec2(17.0, -9.0));
	float damp_basin = noise(world_pos.xz * 0.021 + vec2(-23.0, 41.0));
	float slope = 1.0 - clamp(NORMAL.y, 0.0, 1.0);
	float mud = smoothstep(0.47, 0.66, region + damp_basin * 0.18)
		* clamp(dirt_amount * 1.45, 0.0, 0.94);
	float sand = smoothstep(0.56, 0.72, detail)
		* clamp(sand_amount * 2.65, 0.0, 0.86) * (1.0 - mud * 0.82);
	float rock_weight = smoothstep(0.34, 0.68, slope) * 0.82;
	float moss = smoothstep(0.48, 0.66, damp_basin)
		* clamp(moss_strength * 1.55, 0.0, 0.84)
		* mix(0.72, 1.0, moisture_strength) * (1.0 - sand * 0.72);
	vec3 grass = tint_layer(texture(grass_tex, uv).rgb, grass_color, 1.34);
	vec3 dirt = tint_layer(texture(dirt_tex, uv * 0.82).rgb, dirt_color, 1.24);
	vec3 sand_layer = tint_layer(texture(sand_tex, uv * 0.58).rgb, sand_color, 1.12);
	vec3 rock = tint_layer(texture(rock_tex, uv * 1.35).rgb, rock_color, 1.18);
	vec3 moss_layer = tint_layer(texture(moss_tex, uv * 0.72).rgb, moss_color, 1.28);
	vec3 mud_layer = tint_layer(texture(mud_tex, uv * 0.88).rgb, mud_color, 1.20);
	vec3 blended_normal = normalize(mix(texture(grass_norm, uv).rgb * 2.0 - 1.0,
		texture(dirt_norm, uv * 0.82).rgb * 2.0 - 1.0, mud));
	blended_normal = normalize(mix(blended_normal,
		texture(sand_norm, uv * 0.58).rgb * 2.0 - 1.0, sand));
	blended_normal = normalize(mix(blended_normal,
		texture(rock_norm, uv * 1.35).rgb * 2.0 - 1.0, rock_weight));
	blended_normal = normalize(mix(blended_normal,
		texture(mud_norm, uv * 0.88).rgb * 2.0 - 1.0, mud));
	blended_normal = normalize(mix(blended_normal,
		texture(moss_norm, uv * 0.72).rgb * 2.0 - 1.0, moss));
	vec3 albedo = mix(grass, dirt, mud);
	albedo = mix(albedo, mud_layer, mud);
	albedo = mix(albedo, sand_layer, sand);
	albedo = mix(albedo, moss_layer, moss);
	albedo = mix(albedo, rock, rock_weight);
	float macro_breakup = noise(world_pos.xz * 0.085 + vec2(73.0, 19.0));
	albedo *= mix(0.78, 1.24, macro_breakup);
	albedo = mix(albedo, albedo * realm_tint, realm_tint_strength);
	ALBEDO = clamp(albedo * terrain_brightness, vec3(0.0), vec3(1.0));
	NORMAL_MAP = blended_normal * 0.5 + 0.5;
	float roughness = mix(texture(grass_rough, uv).r, texture(dirt_rough, uv * 0.82).r, mud);
	roughness = mix(roughness, texture(sand_rough, uv * 0.58).r, sand);
	roughness = mix(roughness, texture(rock_rough, uv * 1.35).r, rock_weight);
	roughness = mix(roughness, texture(mud_rough, uv * 0.88).r, mud);
	roughness = mix(roughness, texture(moss_rough, uv * 0.72).r, moss);
	ROUGHNESS = clamp(roughness * (1.0 - moss * 0.16), 0.35, 1.0);
}
