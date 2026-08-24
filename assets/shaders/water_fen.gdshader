shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// === Moonfen Water v2 ===
// Dark fen water: rolling vertex waves, fresnel-deepened albedo, animated
// moon glints on ripple crests — plus fine detail chop, procedural
// caustics in the shallows and depth-fade foam along shorelines.
// (True planar reflections: add a ReflectionProbe over the fen; this shader's
// low grazing-angle roughness picks them up automatically.)

uniform vec3 deep_color : source_color = vec3(0.02, 0.05, 0.09);
uniform vec3 shallow_color : source_color = vec3(0.05, 0.13, 0.17);
uniform vec3 glint_color : source_color = vec3(0.45, 0.60, 0.95);
uniform float wave_height : hint_range(0.0, 0.3) = 0.055;
uniform float wave_speed : hint_range(0.0, 3.0) = 0.9;
uniform float glint_intensity : hint_range(0.0, 4.0) = 1.5;
uniform float alpha_amount : hint_range(0.0, 1.0) = 0.88;
// v2 extras
uniform float detail_chop : hint_range(0.0, 1.0) = 0.55;
uniform vec3 caustic_color : source_color = vec3(0.30, 0.55, 0.60);
uniform float caustic_intensity : hint_range(0.0, 2.0) = 0.6;
uniform vec3 foam_color : source_color = vec3(0.72, 0.80, 0.78);
uniform float foam_width : hint_range(0.02, 1.5) = 0.28;
uniform sampler2D depth_texture : hint_depth_texture;

varying vec3 world_pos;
varying vec3 view_pos_v;

float ripple(vec2 p) {
	return sin(p.x * 1.9 + TIME * wave_speed * 1.7) * 0.5
		+ sin((p.x + p.y) * 1.1 - TIME * wave_speed) * 0.3
		+ cos(p.y * 2.3 + TIME * wave_speed * 2.2) * 0.2;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Cheap voronoi sparkle for caustics
float voronoi(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	float md = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash12(i + g), hash12(i + g + 19.19));
			o = 0.5 + 0.45 * sin(TIME * 0.9 + 6.2831 * o);
			md = min(md, length(g + o - f));
		}
	}
	return md;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_pos_v = (VIEW_MATRIX * vec4(world_pos, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 0.9 + TIME * wave_speed) * wave_height
		+ cos(world_pos.z * 1.3 + TIME * wave_speed * 1.4) * wave_height * 0.6;
}

void fragment() {
	vec2 wp = world_pos.xz;
	
	// Perturb the normal from the ripple field for broken reflections
	float e = 0.12;
	float rx = ripple(wp + vec2(e, 0.0)) - ripple(wp - vec2(e, 0.0));
	float rz = ripple(wp + vec2(0.0, e)) - ripple(wp - vec2(0.0, e));
	// Fine detail chop: small fast cross-ripples that sell wind
	rx += (sin(wp.y * 9.0 + TIME * 4.1) - sin((wp.x + wp.y) * 7.0 - TIME * 3.3))
		* 0.22 * detail_chop;
	rz += (cos(wp.x * 8.0 - TIME * 3.7) - sin((wp.x - wp.y) * 6.0 + TIME * 4.6))
		* 0.22 * detail_chop;
	vec3 n = normalize(vec3(-rx * 0.35, 1.0, -rz * 0.35));
	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(n, 0.0)).xyz, 0.65));
	
	float fresnel = pow(clamp(1.0 - dot(normalize(NORMAL), VIEW), 0.0, 1.0), 2.2);
	ALBEDO = mix(deep_color, shallow_color, fresnel * 0.8);

	// Shoreline foam via depth fade
	float raw_depth = texture(depth_texture, SCREEN_UV).r;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, raw_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float depth_diff = -scene_view.z - (-view_pos_v.z);
	float foam = smoothstep(foam_width, foam_width * 0.15, depth_diff)
		* (0.75 + 0.25 * sin(TIME * 2.2 + wp.x * 3.1 + wp.y * 2.3));
	ALBEDO = mix(ALBEDO, foam_color, foam * 0.85);

	// Caustics shimmer where water is shallow
	float caustic = smoothstep(0.42, 0.05,
		voronoi(wp * 1.4 + vec2(TIME * 0.11, -TIME * 0.07)));
	caustic *= smoothstep(foam_width * 3.0, foam_width, depth_diff);
	
	float crest = smoothstep(0.55, 1.05, ripple(wp));
	ALPHA = clamp(alpha_amount + fresnel * 0.1 - foam * 0.06, 0.0, 1.0);
	ROUGHNESS = mix(mix(0.06, 0.16, fresnel), 0.85, foam);
	SPECULAR = 0.65;
	METALLIC = 0.25;
	EMISSION = glint_color * crest * glint_intensity * (0.5 + fresnel)
		+ caustic_color * caustic * caustic_intensity * (1.0 - fresnel * 0.5);
}
