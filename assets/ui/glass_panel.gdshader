shader_type canvas_item;
render_mode unshaded;

// Ember-glass veil: top-edge sheen highlight, hairline inner rim and a
// faint living grain. Drawn between a panel's stylebox and its content,
// so text stays crisp while the surface reads as frosted glass.

uniform vec2 panel_size = vec2(420.0, 320.0);
uniform float corner_radius = 14.0;
uniform float sheen_strength : hint_range(0.0, 1.0) = 0.10;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.045;
uniform vec4 sheen_color : source_color = vec4(1.0, 0.93, 0.78, 1.0);

float rounded_rect_sdf(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	vec2 p = UV * panel_size - panel_size * 0.5;
	float d = rounded_rect_sdf(p, panel_size * 0.5 - 1.0, corner_radius);
	float aa = max(fwidth(d), 0.0001);

	// Hairline inner rim hugging the stylebox border.
	float edge = (1.0 - smoothstep(-2.2, 0.6, d)) * smoothstep(-6.0, -2.4, d);

	// Sheen: bright band across the upper third fading downward.
	float sheen_band = smoothstep(panel_size.y * 0.70, -panel_size.y * 0.10,
		p.y + panel_size.y * 0.30);
	float sheen = sheen_band * sheen_strength;

	// Living grain: slow-drifting fine noise.
	float n = fract(sin(dot(UV * panel_size * 0.75 + vec2(TIME * 7.3, TIME * -4.1),
		vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float grain = n * grain_strength;

	float alpha = clamp(edge * 0.16 + sheen + grain * 0.7, 0.0, 1.0)
		* smoothstep(1.0, -1.0, d);
	vec3 col = sheen_color.rgb * (edge * 0.85 + 1.0);
	COLOR = vec4(col, clamp(alpha, 0.0, 1.0));
}
