shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// === Grass Blade Sway v2 ===
// Wind-bent grass tufts: bend increases toward the tip so roots stay
// planted. Phase is offset per-instance using world origin.
// v2 adds a `wind_zone` vector (direction * strength) that WorldManager can
// drive for weather/realm gusts, layered under the ambient breeze.

uniform vec3 blade_color : source_color = vec3(0.16, 0.24, 0.10);
uniform vec3 tip_color : source_color = vec3(0.30, 0.40, 0.16);
uniform float wind_strength : hint_range(0.0, 0.6) = 0.16;
uniform float wind_speed : hint_range(0.0, 4.0) = 1.6;
uniform float blade_height : hint_range(0.05, 2.0) = 0.34;
// Cylinder reeds are centered around their origin; authored grass clumps root
// at local y=0. Materials choose the appropriate height convention.
uniform float root_height_offset : hint_range(0.0, 0.5) = 0.5;
// Realm/weather gusts: direction in XZ scaled by strength. Zero = calm.
uniform vec2 wind_zone = vec2(0.0);
uniform float wind_gloss : hint_range(0.0, 1.0) = 0.25;

// WorldState globals: shared gust field + hero trample push.
global uniform vec2 world_wind;
global uniform vec4 world_hero_pos_radius;   // xy = hero (x,z), z = radius
// Extra movers (enemies/boss): xy = position xz, z = push radius
// (shader globals cannot be arrays, so slots ship individually)
global uniform vec4 world_pusher_1;
global uniform vec4 world_pusher_2;
global uniform vec4 world_pusher_3;

varying float v_h;

// Offset pushing a blade away from a mover's feet inside its radius
vec3 _push_offset(vec4 mover, vec3 world_vertex) {
	if (mover.z < 0.001) {
		return vec3(0.0);
	}
	vec2 away = world_vertex.xz - mover.xy;
	float d = length(away);
	float push = (1.0 - smoothstep(0.0, mover.z, d)) * v_h;
	if (push < 0.001) {
		return vec3(0.0);
	}
	vec2 dir = away / max(d, 0.0001);
	return vec3(dir.x * push * 0.26, -push * 0.05, dir.y * push * 0.26);
}

void vertex() {
	v_h = clamp(VERTEX.y / blade_height + root_height_offset, 0.0, 1.0);
	float phase = TIME * wind_speed
		+ (MODEL_MATRIX[3][0] + MODEL_MATRIX[3][2]) * 0.37
		+ VERTEX.x * 2.0;
	float gust = 0.75 + 0.25 * sin(TIME * 0.43 + MODEL_MATRIX[3][0] * 0.11);
	float sway = sin(phase) * wind_strength * gust * v_h;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.83) * wind_strength * 0.55 * gust * v_h;
	// Zone wind bends whole blades downwind, tips furthest (local + shared)
	vec2 zone = wind_zone + world_wind;
	VERTEX.x += zone.x * v_h;
	VERTEX.z += zone.y * v_h;
	// Trample: hero plus up to three extra movers (enemies/boss)
	vec3 world_v = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX += _push_offset(world_hero_pos_radius, world_v);
	VERTEX += _push_offset(world_pusher_1, world_v);
	VERTEX += _push_offset(world_pusher_2, world_v);
	VERTEX += _push_offset(world_pusher_3, world_v);
}

void fragment() {
	ALBEDO = mix(blade_color, tip_color, v_h * v_h);
	ROUGHNESS = mix(0.95, 0.55, v_h * wind_gloss);
	SPECULAR = mix(0.12, 0.35, v_h * wind_gloss);
}
