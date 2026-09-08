shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// === Static Mobile Grass ===
// Grass is intentionally static: mobile devices should not pay a per-vertex
// TIME/wind/trample deformation cost for thousands of instances.

uniform vec3 blade_color : source_color = vec3(0.16, 0.24, 0.10);
uniform vec3 tip_color : source_color = vec3(0.30, 0.40, 0.16);
uniform vec3 dry_color : source_color = vec3(0.38, 0.34, 0.14);
uniform vec3 root_color : source_color = vec3(0.10, 0.13, 0.065);
uniform float blade_height : hint_range(0.05, 2.0) = 0.34;
// Cylinder reeds are centered around their origin; authored grass clumps root
// at local y=0. Materials choose the appropriate height convention.
uniform float root_height_offset : hint_range(0.0, 0.5) = 0.5;
uniform float wind_gloss : hint_range(0.0, 1.0) = 0.25;

varying float v_h;
varying float v_variation;

void vertex() {
	v_h = clamp(VERTEX.y / blade_height + root_height_offset, 0.0, 1.0);
	vec2 instance_pos = MODEL_MATRIX[3].xz;
	v_variation = fract(sin(dot(instance_pos, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	// Leaf blades face many directions but share an upward-growing surface.
	// Keep enough side normal for volume while avoiding black cardboard strips.
	NORMAL = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), 0.48));
	vec3 healthy = mix(blade_color, tip_color, smoothstep(0.18, 1.0, v_h));
	float dry_mix = smoothstep(0.76, 0.98, v_variation) * (0.18 + 0.22 * v_h);
	vec3 varied = mix(healthy, dry_color, dry_mix);
	// Soil-coloured lower blades visually bury the clump instead of leaving a
	// hard bright seam where raw geometry intersects the terrain.
	ALBEDO = mix(root_color, varied, smoothstep(0.02, 0.34, v_h));
	// Thin grass transmits sunlight; BACKLIGHT preserves that natural rim on
	// the shadowed face without making the whole carpet glow in darkness.
	BACKLIGHT = ALBEDO * mix(0.18, 0.42, v_h);
	AO = mix(0.72, 1.0, v_h);
	ROUGHNESS = mix(0.92, 0.68, v_h * wind_gloss);
	SPECULAR = mix(0.10, 0.24, v_h * wind_gloss);
}
