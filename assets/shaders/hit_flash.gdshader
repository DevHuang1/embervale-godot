shader_type spatial;
render_mode unshaded, vertex_lighting;

uniform vec3 flash_color : source_color = vec3(1.0, 0.84, 0.47);
uniform float flash_intensity : hint_range(0, 1) = 0.0;

void fragment() {
	ALBEDO = flash_color * flash_intensity;
	EMISSION = flash_color * flash_intensity * 2.0;
}