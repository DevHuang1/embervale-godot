shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform sampler2D rock_tex : source_color, hint_default_white;
uniform sampler2D rock_norm : hint_normal;
uniform sampler2D rock_rough : hint_default_white;
uniform vec3 rock_tint : source_color = vec3(0.42, 0.39, 0.35);
uniform vec3 snow_tint : source_color = vec3(0.84, 0.90, 0.95);
uniform vec3 accent_tint : source_color = vec3(0.30, 0.56, 0.76);
uniform float snow_line : hint_range(0.0, 1.0) = 0.58;
uniform float snow_softness : hint_range(0.02, 0.5) = 0.18;
uniform float triplanar_scale : hint_range(0.02, 2.0) = 0.24;
uniform float accent_strength : hint_range(0.0, 1.0) = 0.14;

vec3 triplanar_color(sampler2D tex, vec3 p, vec3 n) {
    vec3 weights = pow(abs(n), vec3(4.0));
    weights /= max(dot(weights, vec3(1.0)), 0.0001);
    vec3 x = texture(tex, p.yz * triplanar_scale).rgb;
    vec3 y = texture(tex, p.xz * triplanar_scale).rgb;
    vec3 z = texture(tex, p.xy * triplanar_scale).rgb;
    return x * weights.x + y * weights.y + z * weights.z;
}

void fragment() {
    vec3 n = normalize(NORMAL);
    vec3 p = VERTEX;
    float slope = smoothstep(snow_line - snow_softness, snow_line + snow_softness, n.y);
    float high_noise = texture(rock_rough, p.xz * triplanar_scale * 0.24).r;
    float snow_mask = clamp(slope * (0.68 + high_noise * 0.42), 0.0, 1.0);
    vec3 rock = triplanar_color(rock_tex, p, n) * rock_tint;
    vec3 snow = snow_tint * (0.88 + high_noise * 0.12);
    ALBEDO = mix(rock, snow, snow_mask);
    ROUGHNESS = mix(0.82, 0.62, snow_mask);
    NORMAL_MAP = triplanar_color(rock_norm, p, n);
    NORMAL_MAP_DEPTH = 0.32;
    EMISSION = accent_tint * accent_strength * (1.0 - snow_mask) * smoothstep(0.45, 0.92, high_noise);
}
