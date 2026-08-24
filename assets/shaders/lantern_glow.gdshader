shader_type spatial;
render_mode unshaded, vertex_lighting;

uniform vec3 emissive_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float emissive_intensity : hint_range(0, 2) = 1.2;
uniform float pulse_speed : hint_range(0, 10) = 4.2;

void fragment() {
	float pulse = sin(TIME * pulse_speed) * 0.05 + 1.0;
	EMISSION = emissive_color * emissive_intensity * pulse;
	ALBEDO = vec3(0.0);
}