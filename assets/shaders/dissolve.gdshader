shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// === Noise-based entity dissolve shader ===
// Drives a Worley/value-noise threshold dissolve with an emissive edge glow.
// Compatible with DissolveController.gd — set dissolve_threshold 0→1 to dissolve.
//
// Required texture: a tileable grayscale noise (Worley or value noise).
// Create in Godot: NoiseTexture2D with FastNoiseLite, seamless=true, size=256.
// Assign to noise_tex uniform.

uniform float dissolve_threshold : hint_range(0.0, 1.0) = 0.0;
uniform vec4  edge_color         : source_color = vec4(1.0, 0.45, 0.10, 1.0);
uniform float edge_width         : hint_range(0.0, 0.35) = 0.065;
uniform float edge_emission      : hint_range(0.0, 12.0) = 6.0;
uniform sampler2D noise_tex      : hint_default_white, repeat_enable;
uniform vec2  noise_scale        = vec2(3.5, 3.5);
uniform float noise_time_scroll  : hint_range(0.0, 2.0) = 0.0;  // set via shader param if animated

// Base surface params (forwarded from underlying material)
uniform vec4  albedo_color       : source_color = vec4(0.3, 0.2, 0.3, 1.0);
uniform float roughness          : hint_range(0.0, 1.0) = 0.75;
uniform float metallic           : hint_range(0.0, 1.0) = 0.0;
uniform sampler2D albedo_texture : hint_default_white, repeat_enable;

void vertex() {
	// No vertex displacement — dissolve is fragment-only
}

void fragment() {
	vec2 uv = UV * noise_scale + vec2(noise_time_scroll * TIME * 0.08, 0.0);
	float noise_val = texture(noise_tex, uv).r;

	// Dissolve: discard pixels where noise < threshold
	if (noise_val < dissolve_threshold) {
		discard;
	}

	// Edge band: pixels just above the threshold get the edge color + emission
	float edge_band = smoothstep(dissolve_threshold, dissolve_threshold + edge_width, noise_val);
	float is_edge   = 1.0 - edge_band;  // 1 at threshold, 0 past edge_width

	// Sample base albedo
	vec4 base = albedo_color * texture(albedo_texture, UV);

	// Mix edge color into albedo
	ALBEDO      = mix(edge_color.rgb, base.rgb, edge_band);
	ROUGHNESS   = roughness;
	METALLIC    = metallic;

	// Emission spikes at the dissolve edge
	EMISSION    = edge_color.rgb * edge_emission * is_edge;
	ALPHA       = 1.0;
}
