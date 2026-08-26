shader_type canvas_item;

// === Embervale Screen FX ===
// Fullscreen overlay: health vignette, death desaturation and a
// heavy-hit chromatic aberration punch. Reads the backbuffer via
// hint_screen_texture so the world stays visible underneath.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float vignette_amount : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_softness : hint_range(0.05, 1.0) = 0.55;
uniform vec3 vignette_color : source_color = vec3(0.20, 0.02, 0.02);
uniform float saturation : hint_range(0.0, 1.6) = 1.0;
uniform float chroma_strength : hint_range(0.0, 1.0) = 0.0;
// Rain sheen: a faint vertical smear plus cool highlight lift.
uniform float wetness : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(screen_tex, SCREEN_UV);

	// Rain smear: blend one vertical-offset tap so streaks feel wet
	if (wetness > 0.001) {
		vec4 drip = texture(screen_tex, SCREEN_UV + vec2(0.0, wetness * 0.006));
		base.rgb = mix(base.rgb, mix(drip.rgb, base.rgb, 0.55), wetness * 0.35);
		base.rgb += wetness * vec3(0.010, 0.014, 0.020);
	}
	
	// Chromatic aberration: offset RGB samples radially from center
	if (chroma_strength > 0.001) {
		vec2 dir = SCREEN_UV - vec2(0.5);
		float amt = chroma_strength * 0.008;
		base.r = texture(screen_tex, SCREEN_UV + dir * amt).r;
		base.b = texture(screen_tex, SCREEN_UV - dir * amt).b;
	}
	
	// Saturation control (death desaturation)
	float luma = dot(base.rgb, vec3(0.299, 0.587, 0.114));
	base.rgb = mix(vec3(luma), base.rgb, saturation);
	
	// Vignette: content at center, darkened red tint creeping in at edges
	vec2 p = (SCREEN_UV - vec2(0.5)) * vec2(1.15, 1.0);
	float d = length(p);
	float inner = mix(0.85, 0.30, vignette_softness);
	float edge = smoothstep(inner, inner + 0.45, d);
	vec3 out_rgb = base.rgb * (1.0 - edge * vignette_amount * 0.85);
	out_rgb = mix(out_rgb, vignette_color, edge * vignette_amount * 0.6);
	COLOR = vec4(out_rgb, base.a);
}