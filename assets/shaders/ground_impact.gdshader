shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded;

uniform vec4 impact_color : source_color = vec4(1.0, 0.38, 0.08, 0.85);
uniform vec4 char_color : source_color = vec4(0.055, 0.025, 0.018, 0.82);
uniform float fade : hint_range(0.0, 1.0) = 1.0;
uniform float crack_amount : hint_range(0.0, 1.0) = 0.8;
uniform float burn_amount : hint_range(0.0, 1.0) = 0.75;
uniform float seed = 1.0;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 345.45));
	p += dot(p, p + 34.345);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float edge_noise = noise(p * 4.2 + seed * 2.7) * 0.12;
	float irregular_radius = radius + edge_noise;
	// Hard clip guarantees the supporting quad can never become visible.
	if (irregular_radius > 0.98) { discard; }

	float charred = (1.0 - smoothstep(0.12, 0.94, irregular_radius)) * burn_amount;
	float rim = smoothstep(0.58, 0.72, irregular_radius)
		* (1.0 - smoothstep(0.84, 0.97, irregular_radius));

	// Angular branching fissures: narrow primary rays with noisy breaks and
	// a secondary offset family. They widen slightly toward the impact core.
	float spokes = abs(sin(angle * 5.0 + seed + noise(p * 6.0) * 2.2));
	float branches = abs(sin(angle * 9.0 - seed * 1.7 + radius * 9.0));
	float crack = (1.0 - smoothstep(0.0, 0.105 + radius * 0.025, spokes));
	crack += (1.0 - smoothstep(0.0, 0.055, branches)) * smoothstep(0.25, 0.72, radius);
	crack *= smoothstep(0.10, 0.30, radius) * (1.0 - smoothstep(0.82, 0.97, radius));
	crack *= smoothstep(0.28, 0.52, noise(p * 11.0 + seed));
	crack = clamp(crack * crack_amount, 0.0, 1.0);

	vec3 base = char_color.rgb;
	base = mix(base, impact_color.rgb, crack * 0.92 + rim * 0.34);
	float alpha = max(charred * char_color.a, crack * impact_color.a);
	alpha = max(alpha, rim * impact_color.a * 0.24);
	alpha *= fade * (1.0 - smoothstep(0.82, 0.98, irregular_radius));
	ALBEDO = base;
	EMISSION = impact_color.rgb * (crack * 1.35 + rim * 0.20) * fade;
	ALPHA = alpha;
}
