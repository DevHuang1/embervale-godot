shader_type spatial;
render_mode unshaded;

uniform vec3 base_color : source_color = vec3(0.09, 0.21, 0.17);
uniform vec3 cloak_color : source_color = vec3(0.086, 0.23, 0.165);
uniform vec3 ember_color : source_color = vec3(0.96, 0.72, 0.29);
uniform float time_scale : hint_range(0, 5) = 1.0;

void vertex() {
	// Subtle sway
	VERTEX.x += sin(TIME * time_scale + VERTEX.z * 5.0) * 0.005;
	VERTEX.z += cos(TIME * time_scale + VERTEX.x * 5.0) * 0.003;
}

void fragment() {
	ALBEDO = mix(base_color, cloak_color, step(1.2, VERTEX.y));
	
	// Lantern glow on hip area
	float lantern_dist = distance(VERTEX, vec3(-0.5, 0.8, 0.3));
	float lantern_glow = smoothstep(0.3, 0.0, lantern_dist);
	EMISSION = ember_color * lantern_glow * 0.5;
}