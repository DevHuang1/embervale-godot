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
// Realm/weather gusts: direction in XZ scaled by strength. Zero = calm.
uniform vec2 wind_zone = vec2(0.0);
uniform float wind_gloss : hint_range(0.0, 1.0) = 0.25;

varying float v_h;

void vertex() {
	v_h = clamp((VERTEX.y + blade_height * 0.5) / blade_height, 0.0, 1.0);
	float phase = TIME * wind_speed
		+ (MODEL_MATRIX[3][0] + MODEL_MATRIX[3][2]) * 0.37
		+ VERTEX.x * 2.0;
	float gust = 0.75 + 0.25 * sin(TIME * 0.43 + MODEL_MATRIX[3][0] * 0.11);
	float sway = sin(phase) * wind_strength * gust * v_h;
	VERTEX.x += sway;
	VERTEX.z += cos(phase * 0.83) * wind_strength * 0.55 * gust * v_h;
	// Zone wind bends whole blades downwind, tips furthest
	VERTEX.x += wind_zone.x * v_h;
	VERTEX.z += wind_zone.y * v_h;
}

void fragment() {
	ALBEDO = mix(blade_color, tip_color, v_h * v_h);
	ROUGHNESS = mix(0.95, 0.55, v_h * wind_gloss);
	SPECULAR = mix(0.12, 0.35, v_h * wind_gloss);
}
