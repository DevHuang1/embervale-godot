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

vec3 textured_color(sampler2D layer, vec2 uv, vec3 tint) {
	vec3 sample_color = texture(layer, uv).rgb * tex_gain;
	return mix(tint, sample_color, 0.78);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 normal = normalize(world_normal);
	float slope = 1.0 - clamp(normal.y, 0.0, 1.0);
	vec2 uv = world_pos.xz * uv_world_scale;
	float broad_noise = value_noise(world_pos.xz * 0.045 + vec2(7.0, 19.0));
	float dry_noise = value_noise(world_pos.xz * 0.075 + vec2(31.0, 11.0));
	float dirt_mask = smoothstep(0.48, 0.78, broad_noise) * dirt_amount;
	float sand_mask = smoothstep(0.55, 0.82, dry_noise) * sand_amount;
	float rock_mask = smoothstep(0.42, 0.82, slope);
	vec3 grass = textured_color(grass_tex, uv,
		mix(grass_color, grass_dry, dry_noise * 0.6));
	vec3 dirt = textured_color(dirt_tex, uv * 1.05, dirt_color);
	vec3 sand = textured_color(sand_tex, uv * 0.9, sand_color);
	vec3 rock = textured_color(rock_tex, uv * 0.85, stone_color);
	vec3 color = mix(grass, dirt, dirt_mask * (1.0 - rock_mask));
	color = mix(color, sand, sand_mask * (1.0 - rock_mask) * 0.75);
	color = mix(color, rock, rock_mask);
	color *= mix(vec3(1.0), realm_tint, realm_tint_strength);
	ALBEDO = clamp(color * terrain_brightness, vec3(0.0), vec3(1.0));
	ROUGHNESS = 0.92;
	SPECULAR = 0.22;
	NORMAL = normalize((VIEW_MATRIX * vec4(normal, 0.0)).xyz);
}
