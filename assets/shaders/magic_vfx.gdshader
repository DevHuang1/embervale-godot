shader_type spatial;

// Embervale magical VFX shader.
// Designed for small additive/billboard quads used by GPUParticles3D.
// It provides a soft radial core, animated rune bands, directional streaking,
// fresnel edging, and a depth fade without requiring extra texture samplers.

render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 core_color : source_color = vec4(1.0, 0.42, 0.08, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.90, 0.46, 1.0);
uniform float intensity : hint_range(0.0, 8.0) = 2.2;
uniform float softness : hint_range(0.05, 2.0) = 0.72;
uniform float edge_power : hint_range(0.2, 8.0) = 2.6;
uniform float swirl_strength : hint_range(0.0, 2.0) = 0.34;
uniform float streak_strength : hint_range(0.0, 3.0) = 0.8;
uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform float dissolve_edge : hint_range(0.0, 0.4) = 0.08;
uniform float depth_fade_distance : hint_range(0.0, 2.0) = 0.28;
uniform float pulse_speed : hint_range(0.0, 12.0) = 3.0;
uniform float pulse_amount : hint_range(0.0, 1.0) = 0.16;
uniform vec2 uv_scroll = vec2(0.0, 0.0);
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float noise2(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    // A very small breathing offset keeps impact particles alive without
    // moving the gameplay collision or the source particle simulation.
    float breathe = sin(TIME * pulse_speed + INSTANCE_CUSTOM.x * 6.2831)
        * 0.012 * pulse_amount;
    VERTEX += NORMAL * breathe;
}

void fragment() {
    vec2 centered = UV * 2.0 - 1.0;
    float radial = 1.0 - smoothstep(0.18, 1.0, length(centered));
    float core = pow(max(radial, 0.0), max(softness, 0.05));

    vec2 flow_uv = UV + uv_scroll * TIME;
    float angle = atan(centered.y, centered.x);
    float swirl = sin(angle * 5.0 + TIME * (1.8 + pulse_speed * 0.35)
        + noise2(flow_uv * 4.0) * 2.4) * 0.5 + 0.5;
    swirl = mix(1.0, swirl, swirl_strength);

    float streak = 1.0 - smoothstep(0.0, 0.92,
        abs(centered.x + sin(TIME * 2.0 + centered.y * 4.0) * 0.08));
    streak = mix(1.0, streak, streak_strength * 0.35);

    float pulse = 1.0 + sin(TIME * pulse_speed
        + UV.x * 5.0) * pulse_amount;
    float edge = pow(clamp(1.0 - core, 0.0, 1.0), edge_power);

    // Particle lifetime is already represented by COLOR.a from the
    // particle process material. Avoid relying on unset custom channels.
    float dissolve_mask = noise2(flow_uv * 8.0 + vec2(TIME * 0.25));
    float dissolve_cut = smoothstep(dissolve - dissolve_edge,
        dissolve + dissolve_edge, dissolve_mask);

    float depth_fade = 1.0;
    if (depth_fade_distance > 0.001) {
        float scene_depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
        float particle_depth = FRAGCOORD.z;
        float linear_scene = 1.0 / (scene_depth * 0.0 + 1.0);
        float linear_particle = 1.0 / (particle_depth * 0.0 + 1.0);
        depth_fade = clamp(abs(linear_scene - linear_particle)
            / depth_fade_distance, 0.0, 1.0);
    }

    float alpha = clamp((core * 0.78 + edge * 0.72) * swirl * streak
        * pulse * dissolve_cut * depth_fade * COLOR.a, 0.0, 1.0);
    vec3 color = mix(core_color.rgb, edge_color.rgb, edge * 0.85);
    color *= intensity * (0.84 + core * 0.46);

    ALBEDO = color;
    EMISSION = color;
    ALPHA = alpha;
    ROUGHNESS = 1.0;
}
